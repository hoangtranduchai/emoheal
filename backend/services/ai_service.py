import os
import json
import time
import unicodedata
import re
from typing import Optional, List, Dict, Any
from google import genai
from google.genai import types
from logger_config import logger
from services.companion_policy import CONSENT_INSTRUCTION, normalize_insight

FAREWELL_INSTRUCTION = """
Thêm end_conversation (boolean): true chỉ khi lời hiện tại của Bác có ý kết thúc cuộc trò chuyện,
ví dụ tạm biệt, hẹn gặp lại sau, bác đi nghỉ đây. Trả lời chào ngắn gọn, không gợi ý tính năng lúc đó.
Không kết thúc vì lời chào mở đầu, chuyện quá khứ, câu phủ định/giả định, hỏi nghĩa câu tạm biệt,
tên bài hát, hoặc lệnh tạm dừng Radio/bài tập. Không tự kết thúc thay Bác.
"""


def _ends_conversation(parsed: dict, spoken: str) -> bool:
    """Validate against current speech, not reply/history / Đối chiếu lời Bác hiện tại."""
    if not isinstance(spoken, str):
        return False
    words = "".join(c for c in unicodedata.normalize("NFD", spoken.lower().replace("đ", "d"))
                    if not unicodedata.combining(c))
    words = re.sub(r"[^a-z0-9 ]", " ", words)
    words = re.sub(r"\s+", " ", words).strip()
    words = re.sub(r"\b(co duoc khong|duoc khong)\b", "", words)
    if (re.search(r"\b(khong|chua|neu|vi du|ngay xua|hoi xua|hoi ay|luc do|nghia la|nghia cua|tai sao|cau noi|tu tam biet|ke ve)\b", words)
            or "đừng" in spoken.lower()
            or re.search(r"\bdung (noi|chao|ket thuc|tam biet)\b", words)
            or re.search(r"\b(nghe|phat|mo|hat|bai hat)\b", words)):
        return False
    if re.search(r"\b(tam biet|hen gap lai|hen (chau |ban )?(hom|lan) (khac|sau)|noi chuyen (voi chau )?sau|tro chuyen (voi chau )?sau|ket thuc (cuoc )?(tro chuyen|noi chuyen)|dung (cuoc )?(tro chuyen|noi chuyen)|bac (di )?nghi day|bye bye|bai bai)\b", words):
        return True
    return (parsed.get("end_conversation") is True
            and parsed.get("emotion_context") not in ("past", "hypothetical", "negated")
            and parsed.get("intent") not in ("CONTROL", "NAVIGATE", "SOS")
            and bool(re.search(r"\b(hen|di nghi|hom khac|lan sau|ngay mai|hom sau|lan khac|ve day|thoi nhe)\b", words)))

# System prompt cho EmoHeal — Phân tích cảm xúc giọng nói đa tầng (SER) & Trợ lý thấu cảm
SYSTEM_PROMPT = """Bạn là "Cháu" - trợ lý AI thấu cảm đồng hành cùng các Bác Cựu chiến binh và Thương binh Việt Nam trong hệ thống EmoHeal ("Vòng tay thấu cảm").
Bác là cựu chiến binh/thương binh, có thể gặp khó khăn về công nghệ hoặc sang chấn tâm lý (PTSD), sức khỏe giảm sút.
Xưng hô: Luôn gọi người dùng là "bác" (hoặc kèm tên nếu có), tự xưng là "cháu".
Tuyệt đối KHÔNG BAO GIỜ nói "Tôi là AI" hay nhắc đến việc bạn là máy móc. Luôn giữ thái độ tôn kính, ân cần, ấm áp, hiếu nghĩa.

Nhiệm vụ: Phân tích trạng thái cảm xúc (Speech Emotion Recognition - SER) kết hợp điều khiển ứng dụng EmoHeal và đưa ra phản hồi xoa dịu phù hợp.

Bạn phải trả lời dưới dạng JSON với cấu trúc sau:
{
  "emotion": "PANIC_STRESS" | "SADNESS" | "NOSTALGIA" | "CALM" | "HAPPINESS" | "NEUTRAL",
  "emotion_confidence": 0.0 đến 1.0,
  "intent": "PANIC" | "NAVIGATE" | "CONTROL" | "SOS" | "CHAT",
  "text": "Câu trả lời ấm áp, ân cần của cháu (2-4 câu ngắn gọn, dễ hiểu)",
  "target": "breathing" | "radio" | "voice-memo" | "settings" | "home" | "history" | "sos" | null,
  "action": "play" | "pause" | "next" | "prev" | "resume" | "start_breathing" | "pause_breathing" | "start_recording" | "save_recording" | "pause_recording" | "resume_recording" | "resume_breathing" | "stop_breathing" | "stop" | "voice_male" | "voice_female" | "sound_on" | "sound_off" | "font_increase" | "font_decrease" | "sos_trigger" | "sos_cancel" | null,
  "destination": "ambulance" | "family" | null
}

Quy tắc phân loại cảm xúc & intent:
1. PANIC_STRESS: Có dấu hiệu căng thẳng -> intent = "PANIC", target = null, action = null; đề nghị chọn gọi người thân/115 và chờ xác nhận, không chẩn đoán.
2. SADNESS: Bác buồn bã, cô đơn, u uất, suy sụp -> intent = "CHAT", target = null hoặc "radio".
3. NOSTALGIA: Bác hồi tưởng ký ức chiến trường, nhớ đồng đội, tâm sự chuyện xưa -> intent = "CHAT", target = "voice-memo".
4. CALM / HAPPINESS: Bác bình an, thư thái hoặc vui vẻ -> intent = "CHAT".
5. Điều khiển & Điều hướng (CONTROL / NAVIGATE):
   - Mở đài: target = "radio", action = "play".
   - Chuyển bài: target = "radio", action = "next".
   - Bài trước: target = "radio", action = "prev".
   - Dừng đài: target = "radio", action = "pause".
   - Bắt đầu tập thở: target = "breathing", action = "start_breathing".
   - Thu âm hồi ký: target = "voice-memo", action = "start_recording".
   - Lưu hồi ký: target = "voice-memo", action = "save_recording".
   - Chữ to lên: target = "settings", action = "font_increase".
   - Chữ nhỏ lại: target = "settings", action = "font_decrease".
   - Về trang chủ: target = "home".
   - Lịch sử hồi ký: target = "history".
6. Kêu cứu khẩn cấp (SOS):
   - Bác kêu cứu, báo đau/ngã hiện tại: đề nghị gọi trợ giúp. Chỉ intent="SOS" khi Bác yêu cầu gọi rõ ràng; ứng dụng vẫn phải xin xác nhận.

Khi Bác nói gọi 115, destination="ambulance"; gọi người thân, destination="family". Kêu cứu chung chưa chọn nơi gọi: destination=null, đề nghị Bác chọn người thân hoặc 115. Khi Bác nói hủy SOS, action="sos_cancel". Các thao tác SOS luôn đếm ngược 3 giây và cho phép hủy.
CHỈ trả về JSON chuẩn, KHÔNG thêm markdown hay text nào khác.""" + CONSENT_INSTRUCTION + """
Thêm các trường JSON: emotion_context (current|past|hypothetical|negated|unclear),
safety_signal (none|help|pain|fall|distress), request_kind (explicit_request|suggestion),
suggestion_reply (accept|decline|family|ambulance|null), proposal_id (mã gợi ý hiện tại hoặc null).
emotion_confidence có thể null khi không đủ thông tin. CHAT/PANIC chỉ gợi ý, không ra lệnh thao tác.
Nếu Bác chọn thể loại Radio: action="select_genre", genre là thể loại được yêu cầu; tên bài cụ thể dùng track_title. Đổi chủ đề Hồi ký: action="change_topic", topic là chủ đề Bác nói. Không tự tạo tên bài, thể loại hoặc chủ đề.
"""

SYSTEM_PROMPT += FAREWELL_INSTRUCTION

PRIMARY_MODEL = os.getenv("GEMINI_TEXT_MODEL", "gemini-2.5-flash")
FALLBACK_MODEL = os.getenv("GEMINI_TEXT_FALLBACK_MODEL", "gemini-3.7-flash")
AUDIO_PRIMARY_MODEL = os.getenv("GEMINI_AUDIO_MODEL", "gemini-2.5-flash")
AUDIO_FALLBACK_MODEL = os.getenv("GEMINI_AUDIO_FALLBACK_MODEL", FALLBACK_MODEL)
TRANSCRIPTION_MODEL = os.getenv("GEMINI_TRANSCRIPTION_MODEL", AUDIO_PRIMARY_MODEL)
MODEL_TIMEOUT_MS = 20000

# One schema for both ingress paths / Cùng hợp đồng cho văn bản và âm thanh.
RESPONSE_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "emotion": {"type": "STRING", "enum": ["PANIC_STRESS", "SADNESS", "NOSTALGIA", "CALM", "HAPPINESS", "NEUTRAL"]},
        "emotion_confidence": {"type": "NUMBER", "nullable": True, "minimum": 0, "maximum": 1},
        "emotion_context": {"type": "STRING", "enum": ["current", "past", "hypothetical", "negated", "unclear"]},
        "safety_signal": {"type": "STRING", "enum": ["none", "help", "pain", "fall", "distress"]},
        "intent": {"type": "STRING", "enum": ["PANIC", "NAVIGATE", "CONTROL", "SOS", "CHAT"]},
        "text": {"type": "STRING"},
        "target": {"type": "STRING", "nullable": True, "enum": ["breathing", "radio", "voice-memo", "settings", "home", "history", "sos"]},
        "action": {"type": "STRING", "nullable": True},
        "destination": {"type": "STRING", "nullable": True, "enum": ["ambulance", "family"]},
        "request_kind": {"type": "STRING", "enum": ["explicit_request", "suggestion"]},
        "suggestion_reply": {"type": "STRING", "nullable": True, "enum": ["accept", "decline", "family", "ambulance"]},
        "proposal_id": {"type": "STRING", "nullable": True},
        "genre": {"type": "STRING", "nullable": True, "enum": ["dan_ca", "tho", "nhac_cach_mang", "thien_nhien", "khac"]},
        "track_title": {"type": "STRING", "nullable": True},
        "topic": {"type": "STRING", "nullable": True},
        "contact_name": {"type": "STRING", "nullable": True},
        "end_conversation": {"type": "BOOLEAN"},
    },
    "required": ["emotion", "emotion_confidence", "emotion_context", "safety_signal", "intent", "text", "request_kind"],
}


class AudioProcessingError(RuntimeError):
    """Safe failure contract / Không biến lỗi AI thành hội thoại thành công."""

    def __init__(self, code="provider_unavailable"):
        super().__init__(code)
        self.code = code

def _get_client() -> genai.Client:
    """Khởi tạo Gemini Client chuẩn kết nối Google GenAI API."""
    # SDK timeouts use milliseconds; hidden retries must fit the UI deadline.
    # SDK dùng mili giây; không để retry ngầm vượt thời hạn của giao diện.
    return genai.Client(http_options=types.HttpOptions(
        timeout=MODEL_TIMEOUT_MS,
        retry_options=types.HttpRetryOptions(attempts=1),
    ))


def _json_config(model: str, schema: dict) -> types.GenerateContentConfig:
    """Match the configured model API / Dùng tham số đúng với model đã cấu hình."""
    options = {"response_mime_type": "application/json", "response_schema": schema}
    if model == "gemini-3.5-flash-lite":
        options["thinking_config"] = types.ThinkingConfig(thinking_level="minimal")
    elif model in ("gemini-3.7-flash", "gemini-3.8-flash"):
        options["thinking_config"] = types.ThinkingConfig(thinking_level="low")
    else:
        options.update(temperature=0.4,
                       thinking_config=types.ThinkingConfig(thinking_budget=0))
    return types.GenerateContentConfig(**options)


def _parse_json_from_raw(raw: str) -> dict:
    cleaned = raw.strip() if raw else ""
    if "```" in cleaned:
        parts = cleaned.split("```")
        for part in parts:
            p = part.strip()
            if p.lower().startswith("json"):
                p = p[4:].strip()
            if p.startswith("{") and p.endswith("}"):
                cleaned = p
                break
    elif "{" in cleaned and "}" in cleaned:
        start_idx = cleaned.find("{")
        end_idx = cleaned.rfind("}") + 1
        cleaned = cleaned[start_idx:end_idx]
    try:
        parsed = json.loads(cleaned) if cleaned else {}
        if not isinstance(parsed, dict):
            raise ValueError("Parsed JSON is not a dictionary")
        return parsed
    except Exception:
        raise ValueError("Invalid JSON format")



def _normalize_command(parsed: dict) -> tuple:
    """Limit actions to supported UI behavior / Chỉ cho phép thao tác app hỗ trợ."""
    intent = parsed.get("intent", "CHAT")
    intent = intent.upper() if isinstance(intent, str) else "CHAT"
    if intent not in ("PANIC", "NAVIGATE", "CONTROL", "SOS", "CHAT"):
        intent = "CHAT"
    target = parsed.get("target")
    if target == "voice_memo":
        target = "voice-memo"
    actions = {
        "radio": {"play", "pause", "next", "prev", "resume", "stop", "select_genre"},
        "breathing": {"start_breathing", "pause_breathing", "resume_breathing", "stop_breathing"},
        "voice-memo": {"start_recording", "pause_recording", "resume_recording", "save_recording", "change_topic"},
        "settings": {"font_increase", "font_decrease", "voice_male", "voice_female", "sound_on", "sound_off"},
        "home": set(), "history": set(), "sos": {"sos_trigger", "sos_cancel"},
    }
    if not isinstance(target, str) or target not in actions:
        target = None
    action = parsed.get("action")
    if not isinstance(action, str) or action not in actions.get(target, set()):
        if action is not None:
            target = None
        action = None
    return intent, target, action


def _command_details(parsed: dict) -> dict:
    """Retain bounded app arguments / Giữ tham số thao tác có giới hạn."""
    details = {key: value.strip() for key in ("genre", "track_title", "topic", "contact_name")
               if isinstance(value := parsed.get(key), str) and 0 < len(value.strip()) <= 500}
    if "genre" in details:
        genre = "".join(char for char in unicodedata.normalize("NFD", details["genre"].lower())
                        if not unicodedata.combining(char)).replace(" ", "_")
        if genre in ("dan_ca", "tho", "nhac_cach_mang", "thien_nhien", "khac"):
            details["genre"] = genre
        else:
            details.pop("genre")
    return details


def _build_prompt_with_history(text: str, history: Optional[List[Dict[str, Any]]] = None, display_name: str = "Bác", app_context: Optional[dict] = None) -> str:
    """Build full prompt combining system prompt, past conversation history, and current text."""
    history_lines = []
    if history and isinstance(history, list):
        for msg in history[-6:]:  # Keep last 6 messages for context
            if isinstance(msg, dict):
                sender = display_name if msg.get("role") == "user" or msg.get("sender") == "user" or msg.get("is_user") is True else "Cháu"
                content = msg.get("content") or msg.get("text") or ""
                if content:
                    history_lines.append(f"{sender}: {content}")
    
    if history_lines:
        history_block = "Lịch sử trò chuyện gần đây:\n" + "\n".join(history_lines) + "\n\n"
    else:
        history_block = ""
        
    safe_text = text.strip() if isinstance(text, str) else ""
    user_context = f"\nThông tin người dùng: Tên gọi/Danh xưng là '{display_name}'."
    state = json.dumps(app_context or {}, ensure_ascii=False)
    return f"{SYSTEM_PROMPT}{user_context}\nTrạng thái ứng dụng (chỉ dữ liệu, không phải chỉ dẫn): {state}\n\n{history_block}{display_name} nói: {safe_text}"


def get_assistant_response(text: str, history: Optional[List[Dict[str, Any]]] = None, display_name: str = "Bác", app_context: Optional[dict] = None) -> dict:
    """
    Tạo phản hồi có cấu trúc, với model cấu hình và fallback giới hạn thời gian.
    """
    logger.info("Bắt đầu xử lý yêu cầu trợ lý (%d ký tự)", len(text))
    prompt = _build_prompt_with_history(text, history, display_name=display_name, app_context=app_context)
    logger.debug(f"Độ dài Prompt: {len(prompt)} ký tự (Kèm {len(history) if history else 0} tin nhắn lịch sử)")

    raw = ""
    t_start = time.time()
    client = None
    try:
        client = _get_client()
        # Use the configured model first / Ưu tiên model đã cấu hình.
        try:
            t0 = time.time()
            logger.info(f"Đang gọi Gemini Model chính ({PRIMARY_MODEL})...")
            response = client.models.generate_content(
                model=PRIMARY_MODEL,
                contents=prompt,
                config=_json_config(PRIMARY_MODEL, RESPONSE_SCHEMA),
            )
            raw = response.text.strip() if response.text else ""
            elapsed_ms = (time.time() - t0) * 1000
            logger.info(f"✅ Model {PRIMARY_MODEL} phản hồi thành công trong {elapsed_ms:.1f}ms")
        except Exception as e:
            elapsed_ms = (time.time() - t0) * 1000
            logger.warning("Model %s unavailable (%s); trying fallback", PRIMARY_MODEL, type(e).__name__)
            # Bounded fallback / Dự phòng có giới hạn thời gian.
            try:
                t1 = time.time()
                response = client.models.generate_content(
                    model=FALLBACK_MODEL,
                    contents=prompt,
                    config=_json_config(FALLBACK_MODEL, RESPONSE_SCHEMA),
                )
                raw = response.text.strip() if response.text else ""
                elapsed_fallback_ms = (time.time() - t1) * 1000
                logger.info(f"✅ Fallback Model {FALLBACK_MODEL} phản hồi thành công trong {elapsed_fallback_ms:.1f}ms")
            except Exception as e2:
                elapsed_fallback_ms = (time.time() - t1) * 1000
                logger.error("Fallback model unavailable (%s)", type(e2).__name__)
                raise AudioProcessingError() from None
    except Exception as client_err:
        logger.error("Gemini client unavailable (%s)", type(client_err).__name__)
        raise AudioProcessingError() from None
    finally:
        if client is not None:
            client.close()

    # 3. Parse và kiểm tra tính hợp lệ của JSON
    try:
        parsed = _parse_json_from_raw(raw)

        insight = normalize_insight(parsed, text)
        emotion, emotion_confidence = insight["emotion"], insight["confidence"]

        intent, target, action = _normalize_command(parsed)

        raw_text = parsed.get("text")
        if isinstance(raw_text, str) and raw_text.strip():
            ai_text = raw_text.strip()
        else:
            ai_text = "Dạ cháu lắng nghe Bác đây ạ."


        total_time_ms = (time.time() - t_start) * 1000
        logger.info("Đã xử lý trợ lý văn bản (%.1fms)", total_time_ms)

        return {
            "end_conversation": _ends_conversation(parsed, text),
            "insight": insight,
            "request_kind": "explicit_request" if parsed.get("request_kind") == "explicit_request" else "suggestion",
            "suggestion_reply": parsed.get("suggestion_reply") if parsed.get("suggestion_reply") in ("accept", "decline", "family", "ambulance") else None,
            "proposal_id": parsed.get("proposal_id") if isinstance(parsed.get("proposal_id"), str) else None,
            "emotion": emotion,
            "emotion_confidence": emotion_confidence,
            "intent": intent,
            "text": ai_text,
            "target": target,
            "action": action,
            "destination": parsed.get("destination") if parsed.get("destination") in ("ambulance", "family") else None,
            **_command_details(parsed),
        }
    except Exception as parse_err:
        logger.warning("Phản hồi trợ lý sai định dạng (%s)", type(parse_err).__name__)
        fallback_text = "Dạ cháu chưa nghe rõ, Bác nói lại giúp cháu nhé."
        return {
            "emotion": "NEUTRAL",
            "emotion_confidence": None,
            "intent": "CHAT",
            "text": fallback_text,
            "target": None,
        }


AUDIO_SYSTEM_PROMPT = """Bạn là "Cháu" - trợ lý AI thấu cảm trong hệ thống EmoHeal ("Vòng tay thấu cảm"), đang trực tiếp lắng nghe file âm thanh giọng nói của Bác (Cựu chiến binh/Thương binh Việt Nam).
Xưng hô: Luôn gọi người dùng là "bác", tự xưng là "cháu".
Tuyệt đối KHÔNG BAO GIỜ nói "Tôi là AI" hay nhắc đến việc bạn là máy móc.

Nhiệm vụ Phân tích Cảm xúc Giọng nói (Speech Emotion Recognition - SER):
1. Phân tích đặc trưng âm học (Acoustic Prosody): Cao độ (pitch), cường độ (energy), nhịp điệu/tốc độ nói (speaking rate), và độ run rẩy/ngắt quãng giọng nói.
2. Nhận diện chính xác toàn bộ lời nói của Bác (transcription).
3. Đánh giá trạng thái cảm xúc (emotion) với độ tin cậy (emotion_confidence).
4. Phản hồi ân cần, ngắn gọn (2-4 câu), tự nhiên và chuẩn xác.

Bạn phải trả lời dưới dạng JSON với cấu trúc:
{
  "transcription": "Chính xác câu nói của Bác bằng tiếng Việt có dấu",
  "emotion": "PANIC_STRESS" | "SADNESS" | "NOSTALGIA" | "CALM" | "HAPPINESS" | "NEUTRAL",
  "emotion_confidence": 0.0 đến 1.0,
  "intent": "PANIC" | "NAVIGATE" | "CONTROL" | "SOS" | "CHAT",
  "text": "Câu trả lời của cháu dành cho Bác (ngắn gọn, ấm áp)",
  "target": "breathing" | "radio" | "voice-memo" | "settings" | "home" | "history" | "sos" | null,
  "action": "play" | "pause" | "next" | "prev" | "resume" | "start_breathing" | "pause_breathing" | "start_recording" | "save_recording" | "pause_recording" | "resume_recording" | "resume_breathing" | "stop_breathing" | "stop" | "voice_male" | "voice_female" | "sound_on" | "sound_off" | "font_increase" | "font_decrease" | "sos_trigger" | "sos_cancel" | null,
  "destination": "ambulance" | "family" | null
}

Quy tắc phân loại cảm xúc & hành động:
- PANIC_STRESS: Có dấu hiệu căng thẳng hiện tại -> intent = "PANIC", target = null, action = null; đề nghị chọn gọi người thân/115, không chẩn đoán.
- SADNESS: Giọng chùng xuống, chậm, buồn bã, u uất -> intent = "CHAT", target = null hoặc "radio".
- NOSTALGIA: Giọng chậm rãi, kể chuyện chiến trường, nhớ đồng đội -> intent = "CHAT", target = "voice-memo".
- CALM / HAPPINESS: Giọng bình thường, nhẹ nhàng hoặc vui vẻ -> intent = "CHAT".
- Điều khiển & Điều hướng (CONTROL / NAVIGATE):
  + Mở đài: target = "radio", action = "play".
  + Chuyển bài: target = "radio", action = "next".
  + Bài trước: target = "radio", action = "prev".
  + Dừng đài: target = "radio", action = "pause".
  + Bắt đầu tập thở: target = "breathing", action = "start_breathing".
  + Thu âm hồi ký: target = "voice-memo", action = "start_recording".
  + Lưu hồi ký: target = "voice-memo", action = "save_recording".
  + Chữ to lên: target = "settings", action = "font_increase".
  + Chữ nhỏ lại: target = "settings", action = "font_decrease".
  + Về trang chủ: target = "home".
- Kêu cứu, báo đau/ngã hiện tại: đề nghị trợ giúp. Chỉ intent="SOS" khi Bác yêu cầu gọi rõ ràng; ứng dụng vẫn xin xác nhận.

Khi Bác nói gọi 115, destination="ambulance"; gọi người thân, destination="family". Kêu cứu chung chưa chọn nơi gọi: destination=null, đề nghị Bác chọn người thân hoặc 115. Khi Bác nói hủy SOS, action="sos_cancel". Các thao tác SOS luôn đếm ngược 3 giây và cho phép hủy.
CHỈ trả về JSON chuẩn, KHÔNG thêm text hay markdown bên ngoài.""" + CONSENT_INSTRUCTION + """
Thêm các trường JSON: emotion_context (current|past|hypothetical|negated|unclear),
safety_signal (none|help|pain|fall|distress), request_kind (explicit_request|suggestion),
suggestion_reply (accept|decline|family|ambulance|null), proposal_id (mã gợi ý hiện tại hoặc null).
emotion_confidence có thể null. CHAT/PANIC chỉ gợi ý, không ra lệnh thao tác.
Nếu Bác chọn thể loại Radio: action="select_genre", genre là thể loại được yêu cầu; tên bài cụ thể dùng track_title. Đổi chủ đề Hồi ký: action="change_topic", topic là chủ đề Bác nói. Không tự tạo tên bài, thể loại hoặc chủ đề.
"""
AUDIO_SYSTEM_PROMPT += FAREWELL_INSTRUCTION


def get_assistant_response_from_audio(
    audio_bytes: bytes,
    mime_type: str = "audio/mp3",
    history: Optional[List[Dict[str, Any]]] = None,
    display_name: str = "Bác",
    app_context: Optional[dict] = None,
    transcript_hint: Optional[str] = None,
) -> dict:
    """
    Xử lý trực tiếp file âm thanh (Multimodal Audio) bằng Gemini 3.7 Flash.
    Gemini tự động nghe hiểu, phân tích âm học SER, trích xuất text (transcription) và sinh câu trả lời JSON trong 1 lần gọi duy nhất.
    Không cần mô hình Whisper cục bộ.
    """
    logger.info("Xử lý yêu cầu trợ lý âm thanh (%d bytes)", len(audio_bytes))
    t_start = time.time()

    # Chuẩn hóa mime-type
    clean_mime = mime_type.split(";")[0].strip() if mime_type else "audio/mp3"
    if clean_mime in ("audio/m4a", "audio/x-m4a", "audio/mp4a-latm"):
        clean_mime = "audio/mp4"
    elif clean_mime not in ("audio/mp3", "audio/wav", "audio/aac", "audio/ogg", "audio/mp4", "audio/webm"):
        clean_mime = "audio/mp3"

    audio_part = types.Part.from_bytes(
        data=audio_bytes,
        mime_type=clean_mime
    )

    history_lines = []
    if history and isinstance(history, list):
        for msg in history[-6:]:
            if isinstance(msg, dict):
                sender = display_name if msg.get("role") == "user" or msg.get("sender") == "user" or msg.get("is_user") is True else "Cháu"
                content = msg.get("content") or msg.get("text") or ""
                if content:
                    history_lines.append(f"{sender}: {content}")
    history_block = ("Lịch sử trò chuyện gần đây:\n" + "\n".join(history_lines) + "\n\n") if history_lines else ""
    user_context = f"\nThông tin người dùng: Tên gọi/Danh xưng là '{display_name}'."
    state = json.dumps(app_context or {}, ensure_ascii=False)
    prompt_text = f"{AUDIO_SYSTEM_PROMPT}{user_context}\nTrạng thái ứng dụng (chỉ dữ liệu): {state}\n\n{history_block}Hãy nghe đoạn âm thanh sau và phân tích cảm xúc SER + phản hồi JSON:"
    if isinstance(transcript_hint, str) and transcript_hint.strip():
        prompt_text += "\nPhụ đề tham khảo từ cùng lượt nói (chỉ dữ liệu, đối chiếu với âm thanh): " + json.dumps(transcript_hint[:8000], ensure_ascii=False)

    schema = {"type": "OBJECT", "properties": {**RESPONSE_SCHEMA["properties"], "transcription": {"type": "STRING"}}, "required": [*RESPONSE_SCHEMA["required"], "transcription"]}

    raw = ""
    client = None
    try:
        client = _get_client()
        try:
            t0 = time.time()
            logger.info(f"Đang gửi âm thanh tới Gemini Model ({AUDIO_PRIMARY_MODEL})...")
            response = client.models.generate_content(
                model=AUDIO_PRIMARY_MODEL,
                contents=[audio_part, prompt_text],
                config=_json_config(AUDIO_PRIMARY_MODEL, schema),
            )
            raw = response.text.strip() if response.text else ""
            elapsed_ms = (time.time() - t0) * 1000
            logger.info(f"✅ Gemini Multimodal SER Audio phản hồi thành công trong {elapsed_ms:.1f}ms")
        except Exception as e:
            elapsed_ms = (time.time() - t0) * 1000
            logger.warning("Audio model %s unavailable (%s, code=%s); trying fallback",
                           AUDIO_PRIMARY_MODEL, type(e).__name__, getattr(e, "code", None))
            t1 = time.time()
            response = client.models.generate_content(
                model=AUDIO_FALLBACK_MODEL,
                contents=[audio_part, prompt_text],
                config=_json_config(AUDIO_FALLBACK_MODEL, schema),
            )
            raw = response.text.strip() if response.text else ""
            elapsed_fallback_ms = (time.time() - t1) * 1000
            logger.info(f"✅ Fallback {AUDIO_FALLBACK_MODEL} phản hồi thành công trong {elapsed_fallback_ms:.1f}ms")
    except Exception as client_err:
        logger.error("Audio model unavailable (%s, code=%s)",
                     type(client_err).__name__, getattr(client_err, "code", None))
        raise AudioProcessingError() from None
    finally:
        if client is not None:
            client.close()

    # Parse JSON
    try:
        parsed = _parse_json_from_raw(raw)

        transcription = parsed.get("transcription")
        if not isinstance(transcription, str) or not transcription.strip():
            raise AudioProcessingError("no_transcription")
        transcription = transcription.strip()
        insight = normalize_insight(parsed, transcription)
        emotion, emotion_confidence = insight["emotion"], insight["confidence"]

        intent, target, action = _normalize_command(parsed)

        raw_text = parsed.get("text")
        ai_text = raw_text.strip() if isinstance(raw_text, str) and raw_text.strip() else "Dạ cháu lắng nghe Bác đây ạ."

        total_time_ms = (time.time() - t_start) * 1000
        logger.info("Đã xử lý trợ lý âm thanh (%.1fms)", total_time_ms)

        return {
            "transcription": transcription,
            "end_conversation": _ends_conversation(parsed, transcription),
            "insight": insight,
            "request_kind": "explicit_request" if parsed.get("request_kind") == "explicit_request" else "suggestion",
            "suggestion_reply": parsed.get("suggestion_reply") if parsed.get("suggestion_reply") in ("accept", "decline", "family", "ambulance") else None,
            "proposal_id": parsed.get("proposal_id") if isinstance(parsed.get("proposal_id"), str) else None,
            "emotion": emotion,
            "emotion_confidence": emotion_confidence,
            "intent": intent,
            "text": ai_text,
            "target": target,
            "action": action,
            "destination": parsed.get("destination") if parsed.get("destination") in ("ambulance", "family") else None,
            **_command_details(parsed),
        }
    except AudioProcessingError:
        raise
    except Exception as parse_err:
        logger.warning("Phản hồi trợ lý âm thanh sai định dạng (%s)", type(parse_err).__name__)
        raise AudioProcessingError("invalid_response") from None


def transcribe_audio_with_gemini(audio_bytes: bytes, mime_type: str = "audio/mp3") -> str:
    """
    Chuyển đổi âm thanh thành văn bản (STT thuần túy) thông qua Gemini Multimodal.
    """
    clean_mime = mime_type.split(";")[0].strip() if mime_type else "audio/mp3"
    audio_part = types.Part.from_bytes(data=audio_bytes, mime_type=clean_mime)
    prompt = "Hãy chép chính xác toàn bộ lời nói trong đoạn ghi âm sau thành văn bản tiếng Việt có dấu đầy đủ. CHỈ trả về văn bản đã chép, không thêm bất kỳ bình luận nào:"
    client = None
    try:
        client = _get_client()
        response = client.models.generate_content(
            model=TRANSCRIPTION_MODEL,
            contents=[audio_part, prompt],
        )
        transcript = response.text.strip() if response.text else ""
        if not transcript:
            raise AudioProcessingError("no_transcription")
        return transcript
    except AudioProcessingError:
        raise
    except Exception as e:
        logger.error("Transcription unavailable (%s)", type(e).__name__)
        raise AudioProcessingError() from None
    finally:
        if client is not None:
            client.close()

