"""Keep speech flowing while analysis runs / Phát lời trước, phân tích song song trong RAM."""
import asyncio
import io
import uuid
import wave
from dataclasses import dataclass, field

from logger_config import logger

MAX_TURN_PCM = 16000 * 2 * 30
PRE_ROLL_PCM = 16000 * 2 * 2

VOICE_INSTRUCTION = """RESPOND IN VIETNAMESE. YOU MUST RESPOND UNMISTAKABLY IN VIETNAMESE.
Bạn là cháu, người đồng hành của các Bác cựu chiến binh và thương binh trong EmoHeal. Xưng cháu, gọi Bác. Nói tiếng Việt ấm áp, rõ ràng, tự nhiên, 1–2 câu. Không nói mình là AI. Nghe câu hỏi rồi đáp ngay, không tự diễn giải dài.
Ứng dụng xử lý thao tác riêng. Khi Bác yêu cầu điều khiển Radio, Nhịp thở, Hồi ký, Cài đặt hay gọi trợ giúp, chỉ ghi nhận yêu cầu; KHÔNG nói đã thực hiện. Chỉ xác nhận sau khi nhận KẾT QUẢ TỪ ỨNG DỤNG. Đọc ngắn kết quả, không lặp thao tác, không đọc trạng thái kỹ thuật.
Cảm xúc không phải sự đồng ý. Buồn có thể gợi ý Radio, hoài niệm có thể gợi ý Hồi ký; chờ Bác đồng ý trước thao tác. Kêu cứu, đau/ngã hoặc căng thẳng hiện tại: đề nghị chọn người thân hoặc 115; không tự gọi và không thay bằng bài thở. Chuyện cũ, giả định, phủ định không phải SOS hiện tại. Không chẩn đoán hoặc khẳng định chắc chắn cảm xúc.
Khi Bác nói đồng ý/không, ghi nhận ngắn; ứng dụng sẽ kiểm tra đúng lựa chọn đang hiện và gửi kết quả. Không tự chọn nơi gọi. SOS phải xác nhận, đếm ngược ba giây và có thể hủy.
Không có tra cứu web trong phiên này. Nói rõ chưa tra cứu được khi cần thông tin hiện tại, không đoán tin mới. Không phản hồi tiếng động hoặc giọng của chính cháu. Không yêu cầu chọn tính năng khi chưa có gợi ý. Nếu đã trả lời đủ thì kết thúc lượt.
"""


@dataclass
class AnalysisOutcome:
    generation: int
    id: str
    result: dict | None = None
    utterance: str = ""
    unavailable: bool = False


@dataclass
class CompletedInput:
    generation: int
    id: str
    utterance: str
    proposal_id: str | None = None


@dataclass
class _Turn:
    generation: int
    id: str = field(default_factory=lambda: uuid.uuid4().hex)
    text: str = ""
    pcm: bytearray = field(default_factory=bytearray)
    overflow: bool = False
    dispatched: bool = False
    text_only: bool = False
    finalized: asyncio.Event = field(default_factory=asyncio.Event)
    command_ack: asyncio.Future | None = None
    proposal_id: str | None = None


class ParallelTurnAnalyzer:
    def __init__(self, analyze, queue, context):
        self.analyze, self.queue, self.context = analyze, queue, context
        self.generation = 0
        self.turn = None
        self.replying = False
        self.pre_roll = bytearray()
        self.tasks = set()
        self.closed = False
        self.command_acks = {}

    def _new_turn(self):
        self.generation += 1
        for task in self.tasks:
            task.cancel()
        self.command_acks.clear()
        self.turn = _Turn(self.generation, pcm=bytearray(self.pre_roll),
                          proposal_id=self.context().get('pending_suggestion_id'))
        return self.turn

    def audio(self, pcm):
        self.pre_roll.extend(pcm)
        if len(self.pre_roll) > PRE_ROLL_PCM:
            del self.pre_roll[:-PRE_ROLL_PCM]
        turn = self.turn
        if turn is not None and not turn.dispatched and not self.replying and not turn.overflow:
            if len(turn.pcm) + len(pcm) <= MAX_TURN_PCM:
                turn.pcm.extend(pcm)
            else:
                turn.pcm.clear()
                turn.overflow = True

    def transcript(self, text, finished=False):
        turn = self.turn or self._new_turn()
        combined = turn.text + text
        if len(combined) > 8000:
            turn.overflow = True
        turn.text = combined[:8000]
        if finished:
            self.finalize()
        if self.replying:
            self.start()

    def text(self, text):
        turn = self._new_turn()
        turn.text, turn.text_only = text, True
        turn.pcm.clear()
        self.replying = False
        self.finalize()
        self.start()

    def finalize(self):
        turn = self.turn
        if turn is None or turn.finalized.is_set() or not turn.text.strip():
            return
        if not turn.overflow and self.context().get('local_commands') is True:
            turn.command_ack = asyncio.get_running_loop().create_future()
            self.command_acks[turn.id] = turn.command_ack
            task = asyncio.create_task(self.queue.put(CompletedInput(turn.generation, turn.id, turn.text, turn.proposal_id)))
            self.tasks.add(task)
            task.add_done_callback(self.tasks.discard)
        turn.finalized.set()

    def acknowledge(self, turn_id, handled):
        ack = self.command_acks.get(turn_id)
        if ack is not None and not ack.done():
            ack.set_result(handled)

    def start(self):
        turn = self.turn
        if turn is None or turn.dispatched or not turn.text.strip():
            return
        turn.dispatched = True
        task = asyncio.create_task(self._run(turn))
        self.tasks.add(task)
        task.add_done_callback(self.tasks.discard)

    async def _run(self, turn):
        try:
            # Transcripts can arrive beside the first audio frame / Đợi phần phụ đề cuối, không chặn tiếng.
            await asyncio.sleep(0.08)
            if self.context().get('local_commands') is True:
                # Only the complete utterance can authorize an action.
                # Chờ câu đầy đủ; một tiền tố chưa phải yêu cầu thực thi.
                await turn.finalized.wait()
                if turn.command_ack is not None:
                    try:
                        handled = await asyncio.wait_for(asyncio.shield(turn.command_ack), .5)
                    except asyncio.TimeoutError:
                        handled = False
                    if handled:
                        turn.pcm.clear()
                        return
            if self.closed or turn.generation != self.generation:
                return
            pcm = bytes(turn.pcm) if not turn.overflow else None
            turn.pcm.clear()
            if turn.overflow:
                raise ValueError("Utterance exceeds analysis buffer")
            result = await asyncio.wait_for(self.analyze(
                None if turn.text_only else pcm, turn.text, self.context().copy()), 10)
            if not self.closed and turn.generation == self.generation:
                await self.queue.put(AnalysisOutcome(turn.generation, turn.id, result, turn.text))
        except asyncio.CancelledError:
            raise
        except Exception as error:
            logger.warning("Parallel companion analysis unavailable (%s)", type(error).__name__)
            if not self.closed and turn.generation == self.generation:
                await self.queue.put(AnalysisOutcome(turn.generation, turn.id, utterance=turn.text, unavailable=True))

    def reply(self):
        self.replying = True
        self.start()

    def end(self):
        self.finalize()
        self.start()
        self.replying = False
        self.turn = None
        self.pre_roll.clear()

    def interrupt(self):
        self.generation += 1
        for task in self.tasks:
            task.cancel()
        self.replying = False
        self.turn = None
        self.command_acks.clear()

    async def close(self):
        self.closed = True
        self.generation += 1
        for task in self.tasks:
            task.cancel()
        await asyncio.gather(*self.tasks, return_exceptions=True)
        self.tasks.clear()
        self.turn = None
        self.pre_roll.clear()
        self.command_acks.clear()


async def analyze_turn(pcm, transcript, context):
    from services.ai_service import get_assistant_response, get_assistant_response_from_audio
    if pcm:
        output = io.BytesIO()
        with wave.open(output, "wb") as writer:
            writer.setnchannels(1)
            writer.setsampwidth(2)
            writer.setframerate(16000)
            writer.writeframes(pcm)
        return await asyncio.to_thread(get_assistant_response_from_audio,
            output.getvalue(), "audio/wav", app_context=context, transcript_hint=transcript)
    return await asyncio.to_thread(get_assistant_response, transcript, app_context=context)


def command_from_analysis(result):
    proposal, decision = result.get("proposal_id"), result.get("suggestion_reply")
    if isinstance(proposal, str) and decision in ("accept", "decline", "family", "ambulance"):
        return "respond_to_suggestion", {"proposal_id": proposal, "decision": decision}
    action, target, intent = result.get("action"), result.get("target"), result.get("intent")
    if action == "sos_cancel":
        return "cancel_sos_emergency", {}
    if intent not in ("CONTROL", "NAVIGATE", "SOS"):
        return None
    kind = {"request_kind": result.get("request_kind", "suggestion")}
    if intent == "SOS" or target == "sos":
        return "trigger_sos_emergency", {"destination": result["destination"]} if result.get("destination") in ("family", "ambulance") else {}
    if target == "radio":
        args = {**kind, **({"action": action} if action else {})}
        for key in ("genre", "track_title"):
            if isinstance(result.get(key), str):
                args[key] = result[key]
        return ("control_radio" if action else "open_radio"), args
    if target == "breathing":
        return "control_breathing", {**kind, "action": action.replace("_breathing", "") if isinstance(action, str) else "start"}
    if target in ("voice-memo", "voice_memo"):
        if not action:
            return "open_voice_memo", kind
        return "control_voice_memo", {**kind, "action": "stop_and_save" if action == "save_recording" else action,
            **({"topic": result["topic"]} if isinstance(result.get("topic"), str) else {})}
    if target == "home":
        return "navigate_to_screen", {**kind, "screen": "home"}
    if target == "history":
        return "open_history", kind
    if target == "settings":
        settings = {
            "font_increase": {"setting_type": "font_size", "font_delta": .15},
            "font_decrease": {"setting_type": "font_size", "font_delta": -.15},
            "voice_male": {"setting_type": "voice_type", "voice_type": "charon"},
            "voice_female": {"setting_type": "voice_type", "voice_type": "aoede"},
            "sound_on": {"setting_type": "sound", "sound_enabled": True},
            "sound_off": {"setting_type": "sound", "sound_enabled": False},
        }
        return ("adjust_settings", {**kind, **settings[action]}) if action in settings else ("open_settings", kind)
    return None
