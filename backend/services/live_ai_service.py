import os
import json
import asyncio
import datetime
import base64
import math
import uuid
import time
from contextlib import AsyncExitStack
from typing import Optional, Callable, Awaitable
from types import SimpleNamespace
from google import genai
from google.genai import types
from logger_config import logger
from services.companion_policy import CONSENT_INSTRUCTION, EMOTIONS, CONTEXTS, SIGNALS, normalize_insight
from services.parallel_companion import AnalysisOutcome, CompletedInput, ParallelTurnAnalyzer, VOICE_INSTRUCTION, analyze_turn, command_from_analysis

# Model chính thức hỗ trợ luồng đàm thoại thời gian thực Gemini Live API (bidiGenerateContent)
LIVE_MODEL = os.getenv("GEMINI_LIVE_MODEL", "gemini-3.8-live")

CANDIDATE_LIVE_MODELS = [
    LIVE_MODEL,
    "gemini-3.8-live",
    "gemini-3.1-flash-live-preview",
    "gemini-2.5-flash-native-audio-preview-12-2025",
]

TOOL_RESULT_TIMEOUT_SECONDS = 30.0
MAX_AUDIO_CHUNK_BYTES = 64 * 1024
MAX_TEXT_LENGTH = 8000
INSIGHT_ACK_TIMEOUT_SECONDS = 0.5
LEGACY_NATIVE_MODEL = "gemini-2.5-flash-native-audio-preview-12-2025"

LIVE_SEARCH_RULE = """7. Tra cứu thông tin (Google Search):
   - Khi Bác hỏi về thời tiết, tin tức, lịch âm, các ngày kỷ niệm lịch sử chiến trường xưa, hoặc chế độ chính sách: Dùng Google Search để trả lời chính xác, hiếu thảo.
"""
LIVE_NO_SEARCH_RULE = """7. Thông tin cần cập nhật:
   - Phiên này không có công cụ tra cứu web. Khi Bác cần thông tin hiện tại hoặc nguồn kiểm chứng, nói rõ cháu chưa tra cứu được; không bịa thời tiết, tin tức, ngày tháng hay chính sách mới. Vẫn hỗ trợ đầy đủ điều khiển app và lắng nghe Bác.
"""


def _encode_resumption(model: str, handle: str) -> str:
    # Provider handles belong to one model / Mã khôi phục gắn với mô hình đã mở.
    payload = json.dumps({"model": model, "handle": handle}, separators=(",", ":")).encode()
    return "eh1." + base64.urlsafe_b64encode(payload).decode().rstrip("=")


def _decode_resumption(value: str) -> tuple[str, str]:
    if not isinstance(value, str) or not value or len(value) > 12000:
        raise ValueError("Invalid resumption handle")
    if not value.startswith("eh1."):
        return LIVE_MODEL, value  # Older clients / Tương thích mã phiên cũ.
    try:
        encoded = value[4:]
        data = json.loads(base64.b64decode(encoded + "=" * (-len(encoded) % 4), altchars=b"-_", validate=True))
        model, handle = data["model"], data["handle"]
        if model not in CANDIDATE_LIVE_MODELS or not isinstance(handle, str) or not handle or len(handle) > 8000:
            raise ValueError("Invalid resumption handle")
        return model, handle
    except (ValueError, KeyError, TypeError) as exc:
        raise ValueError("Invalid resumption handle") from exc

LIVE_SYSTEM_INSTRUCTION = """RESPOND IN VIETNAMESE. YOU MUST RESPOND UNMISTAKABLY IN VIETNAMESE.
Bạn là "Cháu" - người đồng hành ấm áp, ân cần, kiên nhẫn và hiếu thảo dành riêng cho các Bác Cựu chiến binh và Thương binh Việt Nam trong hệ thống EmoHeal ("Vòng tay thấu cảm").

Quy tắc xưng hô và ngôn phong:
1. Luôn tự xưng là "cháu", gọi người dùng là "Bác" (hoặc kèm tên nếu biết, ví dụ "Bác Hải").
2. Giọng điệu: Nhẹ nhàng, tôn kính, ấm áp, nói tiếng Việt chuẩn, chậm rãi, tự nhiên, dễ nghe.
3. Tuyệt đối KHÔNG BAO GIỜ nói "Tôi là AI" hay "Tôi là trợ lý ảo".
4. Phản hồi ngắn gọn, súc tích (1-2 câu ân cần), lắng nghe chân thành, giải thích thao tác Bác yêu cầu một cách ấm áp.

Quy tắc điều khiển ứng dụng bằng giọng nói (Voice App Control & Function Calling):
1. Điều khiển Đài Radio:
   - Khi Bác muốn mở đài, nghe nhạc, nghe thơ: Nói lời ân cần và gọi open_radio(genre=...).
   - Khi Bác muốn chuyển bài, nghe bài kế tiếp ("chuyển bài", "bài sau"): Gọi control_radio(action='next').
   - Khi Bác muốn nghe lại bài trước ("bài trước", "quay lại"): Gọi control_radio(action='prev').
   - Khi Bác muốn tạm dừng đài ("dừng phát", "tạm dừng", "tắt đài"): Gọi control_radio(action='pause').
   - Khi Bác muốn nghe tiếp ("bật tiếp", "phát tiếp", "nghe tiếp"): Gọi control_radio(action='resume').
   - Khi Bác chọn thể loại ("mở dân ca", "nghe thơ", "bật nhạc cách mạng"): Gọi control_radio(action='select_genre', genre='dan_ca'|'tho'|'nhac_cach_mang').

2. Điều khiển Nhịp thở Hoa Sen:
   - Khi nhận thấy Bác căng thẳng hoặc báo đau/ngã hiện tại: đề nghị chọn gọi người thân/115; không tự mở bài thở hoặc chẩn đoán.
   - Khi Bác muốn bắt đầu tập thở ("bắt đầu thở", "tập thở"): Gọi control_breathing(action='start').
   - Khi Bác muốn tạm dừng thở ("tạm dừng", "nghỉ một lát"): Gọi control_breathing(action='pause').
   - Khi Bác muốn tiếp tục hoặc kết thúc ("tiếp tục thở", "dừng thở", "kết thúc"): Gọi control_breathing(action='resume'|'stop').

3. Điều khiển Hồi ký Giọng nói:
   - Khi Bác kể chuyện xưa: đồng cảm và gợi ý Hồi ký. Chỉ mở sau khi Bác đồng ý hoặc yêu cầu mở rõ ràng.
   - Khi Bác muốn bắt đầu thu âm ("bắt đầu ghi âm", "thu âm hồi ký"): Gọi control_voice_memo(action='start_recording').
   - Khi Bác muốn tạm dừng thu âm: Gọi control_voice_memo(action='pause_recording').
   - Khi Bác muốn hoàn thành, lưu hồi ký ("lưu lại", "gửi hồi ký", "xong rồi"): Gọi control_voice_memo(action='stop_and_save').
   - Khi Bác muốn đổi chủ đề ("chuyển sang chuyện con cháu", "chủ đề chiến trường"): Gọi control_voice_memo(action='change_topic', topic=...).

4. Điều khiển Cài đặt & Trợ năng:
   - Khi Bác thấy chữ nhỏ ("cho chữ to lên", "chữ bé quá", "phóng to chữ"): Gọi adjust_settings(setting_type='font_size', font_delta=0.15).
   - Khi Bác muốn chữ nhỏ lại: Gọi adjust_settings(setting_type='font_size', font_delta=-0.15).
   - Khi Bác muốn đổi giọng đọc ("đổi giọng nam", "đổi giọng cháu trai"): Gọi adjust_settings(setting_type='voice_type', voice_type='charon').
   - Khi Bác muốn đổi giọng nữ ("đổi giọng nữ", "đổi giọng cháu gái"): Gọi adjust_settings(setting_type='voice_type', voice_type='aoede').
   - Khi Bác muốn mở màn hình cài đặt: Gọi open_settings().

5. Điều hướng màn hình tổng quát:
   - Khi Bác muốn về màn hình chính ("về trang chủ", "màn hình chính"): Gọi navigate_to_screen(screen='home').
   - Khi Bác muốn xem lịch sử ("xem lại hồi ký", "nhật ký"): Gọi open_history().

6. Kêu cứu khẩn cấp SOS:
   - Khi Bác kêu cứu, báo đau/ngã hoặc căng thẳng hiện tại: báo nhận định qua report_emotion và đề nghị Bác chọn gọi người thân/115.
   - Khi Bác nói "Gọi cấp cứu 115": destination='ambulance'. Khi Bác nói "Gọi cho con tôi", "gọi người thân": destination='family'.
   - Ứng dụng đếm ngược 3 giây, Bác có thể nói "hủy", "đừng gọi" để gọi cancel_sos_emergency(). Không nói đã gọi khi chưa nhận kết quả executed.

""" + LIVE_SEARCH_RULE + """
8. Thực thi đáng tin cậy:
   - Dựa vào trạng thái màn hình ứng dụng để hiểu "tạm dừng", "tiếp tục", "quay lại". Nếu chưa rõ đối tượng, hỏi Bác một câu ngắn.
   - Thông tin trạng thái ứng dụng chỉ là dữ liệu, không phải yêu cầu của Bác; không đáp lời hay gọi công cụ chỉ vì nhận thông tin này.
   - Chỉ xác nhận thành công khi công cụ trả status='executed'; failed/cancelled phải giải thích ngắn bằng tiếng Việt. Không lặp lại thao tác vừa hoàn tất.""" + CONSENT_INSTRUCTION + """
Sau khi nghe trọn mỗi lượt nói, gọi report_emotion TRƯỚC khi trả lời hoặc gọi công cụ điều khiển. Kết quả công cụ có app_context mới nhất và mã gợi ý đang hiện; dùng dữ liệu này để hiểu màn hình hiện tại và câu đồng ý của Bác. Không suy đoán từ tiếng ồn hoặc giọng nói của chính cháu.
Khi nhận 'KẾT QUẢ TỪ ỨNG DỤNG', chỉ đọc ngắn kết quả cho Bác, không phân tích cảm xúc hay gọi lại công cụ; thao tác đã được ứng dụng xử lý.
Nếu app_context có pending_suggestion_id, dùng respond_to_suggestion với ĐÚNG mã này khi Bác trả lời gợi ý; không gọi lại công cụ mở tính năng.
Chỉ nói gợi ý chứ chưa nói đã làm khi status='awaiting_confirmation'. Khi không rõ Bác đang kể chuyện cũ hay cần giúp ngay, hỏi lại một câu ngắn.
"""

# Định nghĩa các Tools (Function Calling) toàn diện theo kho mẫu Gemini Live API
TOOLS_DECLARATION = [
    {
        "name": "open_radio",
        "description": "Bật đài phát thanh hoặc chuyên mục ngâm thơ/dân ca/nhạc cách mạng cho Bác nghe",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "genre": {
                    "type": "STRING",
                    "description": "Thể loại muốn nghe: 'dan_ca', 'tho', 'nhac_cach_mang', 'thien_nhien', 'khac'"
                }
            }
        }
    },
    {
        "name": "control_radio",
        "description": "Điều khiển thao tác phát nhạc đài radio (chuyển bài tiếp theo, bài trước, tạm dừng, phát tiếp hoặc chọn thể loại)",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "action": {
                    "type": "STRING",
                    "description": "Hành động: 'play', 'pause', 'next', 'prev', 'stop', 'resume', 'select_genre'"
                },
                "genre": {
                    "type": "STRING",
                    "description": "Thể loại khi chọn: 'dan_ca', 'tho', 'nhac_cach_mang', 'thien_nhien', 'khac'"
                },
                "track_title": {
                    "type": "STRING",
                    "description": "Tên bài hát hoặc đài muốn phát cụ thể"
                }
            },
            "required": ["action"]
        }
    },
    {
        "name": "start_breathing_exercise",
        "description": "Kích hoạt màn hình và bài tập Nhịp Thở Hoa Sen khi Bác cảm thấy mệt mỏi, khó thở, lo âu hoặc căng thẳng",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "technique": {
                    "type": "STRING",
                    "description": "Kỹ thuật Nhịp thở Hoa Sen 4-4-6: 'lotus_4_4_6'"
                }
            }
        }
    },
    {
        "name": "control_breathing",
        "description": "Điều khiển tiến trình bài tập thở hoa sen (bắt đầu, tạm dừng, tiếp tục, kết thúc)",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "action": {
                    "type": "STRING",
                    "description": "Hành động: 'start', 'pause', 'resume', 'stop'"
                }
            },
            "required": ["action"]
        }
    },
    {
        "name": "open_voice_memo",
        "description": "Mở màn hình Ghi âm Hồi ký chiến trường khi Bác muốn lưu giữ ký ức, tâm sự",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "prompt_title": {
                    "type": "STRING",
                    "description": "Tiêu đề gợi mở cho hồi ký (ví dụ: 'Kỷ niệm trận đánh năm xưa')"
                }
            }
        }
    },
    {
        "name": "control_voice_memo",
        "description": "Điều khiển tính năng ghi âm và lưu hồi ký giọng nói bằng giọng nói",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "action": {
                    "type": "STRING",
                    "description": "Hành động: 'start_recording', 'pause_recording', 'stop_and_save', 'change_topic'"
                },
                "topic": {
                    "type": "STRING",
                    "description": "Tên chủ đề hồi ký khi đổi: 'Chiến trường & Đồng đội', 'Niềm vui & Con cháu', 'Lá thư gửi tương lai'"
                }
            },
            "required": ["action"]
        }
    },
    {
        "name": "open_history",
        "description": "Mở danh sách Hồi ký Giọng nói đã lưu của Bác",
        "parameters": {
            "type": "OBJECT",
            "properties": {}
        }
    },
    {
        "name": "open_settings",
        "description": "Mở màn hình Cài đặt ứng dụng hoặc Đổi giọng đọc trợ lý",
        "parameters": {
            "type": "OBJECT",
            "properties": {}
        }
    },
    {
        "name": "adjust_settings",
        "description": "Điều chỉnh cài đặt trợ năng của ứng dụng theo yêu cầu bằng giọng nói (cỡ chữ, giọng đọc, âm thanh)",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "setting_type": {
                    "type": "STRING",
                    "description": "Loại cài đặt: 'font_size', 'voice_type', 'sound'"
                },
                "font_delta": {
                    "type": "NUMBER",
                    "description": "Mức tăng/giảm cỡ chữ (+0.15 cho chữ to lên, -0.15 cho chữ nhỏ lại)"
                },
                "voice_type": {
                    "type": "STRING",
                    "description": "Giọng đọc muốn đổi: 'charon' (nam) hoặc 'aoede' (nữ)"
                },
                "sound_enabled": {
                    "type": "BOOLEAN",
                    "description": "Trạng thái bật/tắt âm thanh hướng dẫn"
                }
            },
            "required": ["setting_type"]
        }
    },
    {
        "name": "navigate_to_screen",
        "description": "Điều hướng Bác đến màn hình chức năng cụ thể trong ứng dụng",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "screen": {
                    "type": "STRING",
                    "description": "Tên màn hình: 'home', 'voice_memo', 'radio', 'breathing', 'settings', 'history'"
                }
            },
            "required": ["screen"]
        }
    },
    {
        "name": "trigger_sos_emergency",
        "description": "Kích hoạt báo động khẩn cấp SOS và kết nối người thân khi Bác bị ngã hoặc gặp nguy hiểm",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "reason": {
                    "type": "STRING",
                    "description": "Lý do khẩn cấp phát hiện từ giọng nói"
                },
                "destination": {
                    "type": "STRING",
                    "enum": ["ambulance", "family"],
                    "description": "ambulance khi Bác yêu cầu cấp cứu 115; family khi yêu cầu người thân hoặc kêu cứu chung"
                },
                "contact_name": {
                    "type": "STRING",
                    "description": "Tên người thân Bác yêu cầu gọi nếu Bác đã nói rõ tên"
                }
            }
        }
    },
    {
        "name": "cancel_sos_emergency",
        "description": "Hủy cuộc gọi SOS đang đếm ngược khi Bác nói hủy hoặc đừng gọi",
        "parameters": {"type": "OBJECT", "properties": {}}
    },
    {
        "name": "report_emotion",
        "description": "Báo nhận định tạm từ lời nói/ngữ điệu, phân biệt chuyện hiện tại/quá khứ/phủ định. Chỉ cung cấp dữ liệu để GỢI Ý; không thực hiện tính năng hay gọi điện.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "emotion": {"type": "STRING", "enum": list(EMOTIONS)},
                "confidence": {"type": "NUMBER", "nullable": True, "minimum": 0, "maximum": 1, "description": "Ước lượng từ nội dung và âm thanh thực sự nhận được; null khi chưa đủ dữ liệu. Không khẳng định đây là độ chính xác đã kiểm chứng."},
                "context": {"type": "STRING", "enum": list(CONTEXTS)},
                "safety_signal": {"type": "STRING", "enum": list(SIGNALS)},
            },
            "required": ["emotion", "confidence", "context", "safety_signal"],
        },
    },
    {
        "name": "respond_to_suggestion",
        "description": "Trả lời gợi ý ĐANG HIỆN. Lấy proposal_id từ pending_suggestion_id trong trạng thái app; không tự tạo mã và không xác nhận thay Bác.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "proposal_id": {"type": "STRING"},
                "decision": {"type": "STRING", "enum": ["accept", "decline", "family", "ambulance"]},
            },
            "required": ["proposal_id", "decision"],
        },
    },
]

# Missing provenance is a suggestion, never implicit consent / Thiếu nguồn yêu cầu thì phải hỏi.
_CONSENT_TOOLS = {"open_radio", "control_radio", "start_breathing_exercise", "control_breathing", "open_voice_memo", "control_voice_memo", "navigate_to_screen", "adjust_settings", "open_settings", "open_history"}
for _declaration in TOOLS_DECLARATION:
    if _declaration["name"] in _CONSENT_TOOLS:
        _declaration["parameters"]["properties"]["request_kind"] = {
            "type": "STRING", "enum": ["explicit_request", "suggestion"],
            "description": "explicit_request chỉ khi Bác đã yêu cầu rõ ràng; suggestion khi suy từ cảm xúc hoặc đang đề xuất.",
        }
        _declaration["parameters"].setdefault("required", []).append("request_kind")

# Schema enums prevent unsupported commands / Ràng buộc lệnh đúng chức năng.
_TOOL_ENUMS = {
    "open_radio": {"genre": ["dan_ca", "tho", "nhac_cach_mang", "thien_nhien", "khac"]},
    "control_radio": {"action": ["play", "pause", "next", "prev", "stop", "resume", "select_genre"], "genre": ["dan_ca", "tho", "nhac_cach_mang", "thien_nhien", "khac"]},
    "start_breathing_exercise": {"technique": ["lotus_4_4_6"]},
    "control_breathing": {"action": ["start", "pause", "resume", "stop"]},
    "control_voice_memo": {"action": ["start_recording", "pause_recording", "resume_recording", "stop_and_save", "change_topic"]},
    "adjust_settings": {"setting_type": ["font_size", "voice_type", "sound"], "voice_type": ["aoede", "charon"]},
    "navigate_to_screen": {"screen": ["home", "voice_memo", "radio", "breathing", "settings", "history"]},
}
for _tool in TOOLS_DECLARATION:
    for _key, _values in _TOOL_ENUMS.get(_tool["name"], {}).items():
        _tool["parameters"]["properties"][_key]["enum"] = _values

_TOOLS_BY_NAME = {tool["name"]: tool for tool in TOOLS_DECLARATION}

# Bản đồ giọng đọc Google Gemini Live API
# Aoede: Nữ trầm ấm, truyền cảm | Charon: Nam trung niên đĩnh đạc
LIVE_VOICE_MAP = {
    "aoede": "Aoede",
    "charon": "Charon",
    "kore": "Kore",
    "fenrir": "Fenrir",
    "puck": "Puck",
}

def _live_config(model: str, voice: str, display_name: str = "Bác",
                 session_handle: Optional[str] = None) -> types.LiveConnectConfig:
    legacy = model == LEGACY_NATIVE_MODEL
    instruction = VOICE_INSTRUCTION if legacy else LIVE_SYSTEM_INSTRUCTION
    tools = [{"function_declarations": [
        {**tool, **({"behavior": "BLOCKING"} if model == "gemini-3.8-live" else {})}
        for tool in TOOLS_DECLARATION
    ]}]
    # Legacy speech is separate from app control / Tách giọng và xử lý lệnh ở bản dự phòng.
    if legacy:
        tools = []
    else:
        tools.insert(0, {"google_search": {}})
    # Resumption is enabled on the first connection too / Cho phép khôi phục từ phiên đầu.
    config = dict(
        response_modalities=[types.Modality.AUDIO],
        system_instruction=types.Content(parts=[types.Part(
            text=f"{instruction}\nDanh xưng người dùng: {display_name[:100]}"
        )]),
        speech_config=types.SpeechConfig(voice_config=types.VoiceConfig(
            prebuilt_voice_config=types.PrebuiltVoiceConfig(
                voice_name=LIVE_VOICE_MAP.get(voice.lower(), "Aoede")
            )
        )),
        # 3.8 defaults to async; acknowledgements must arrive before success speech.
        # Chờ kết quả thật trước khi nói hoàn tất thao tác.
        tools=tools,
        context_window_compression=types.ContextWindowCompressionConfig(
            sliding_window=types.SlidingWindow()
        ),
        session_resumption=types.SessionResumptionConfig(handle=session_handle),
        input_audio_transcription=types.AudioTranscriptionConfig(),
        output_audio_transcription=types.AudioTranscriptionConfig(),
        realtime_input_config=types.RealtimeInputConfig(
            automatic_activity_detection=types.AutomaticActivityDetection(
                # A natural pause without a long wait / Nghỉ giữa câu vừa đủ, phản hồi sớm hơn.
                disabled=False,
                start_of_speech_sensitivity=types.StartSensitivity.START_SENSITIVITY_LOW,
                end_of_speech_sensitivity=types.EndSensitivity.END_SENSITIVITY_LOW,
                prefix_padding_ms=200,
                silence_duration_ms=700,
            )
        ),
    )
    # 3.8 Live rejects thinking_config / 3.8 Live không nhận thinking_config.
    if model == "gemini-3.1-flash-live-preview":
        config["thinking_config"] = types.ThinkingConfig(thinking_level="minimal")
    elif legacy:
        # Avoid dynamic reasoning delays in spoken turns / Giảm chờ suy luận khi trò chuyện.
        config["thinking_config"] = types.ThinkingConfig(thinking_budget=0)
    return types.LiveConnectConfig(**config)


async def create_live_ephemeral_token(user_id: str, voice: str = "aoede",
                                      expires_minutes: int = 30) -> dict:
    """Create a constrained, single-use token / Cấp token một lần có ràng buộc."""
    api_key = os.getenv("GEMINI_API_KEY", "")
    if not api_key:
        raise RuntimeError("Dạ máy chủ chưa sẵn sàng cho cuộc gọi, Bác thử lại sau nhé.")
    if not 1 <= expires_minutes <= 30:
        raise ValueError("Thời hạn cuộc gọi phải từ 1 đến 30 phút.")
    now = datetime.datetime.now(datetime.timezone.utc)
    expires_at = now + datetime.timedelta(minutes=expires_minutes)
    config = types.CreateAuthTokenConfig(
        uses=1,
        expire_time=expires_at,
        new_session_expire_time=now + datetime.timedelta(minutes=1),
        live_connect_constraints=types.LiveConnectConstraints(
            model=LIVE_MODEL, config=_live_config(LIVE_MODEL, voice)
        ),
    )
    client = genai.Client(api_key=api_key)
    try:
        token = await client.aio.auth_tokens.create(config=config)
        if not token.name:
            raise RuntimeError("Dạ chưa thể mở cuộc gọi, Bác thử lại sau nhé.")
        return {
            "token": token.name,
            "expires_at": expires_at.isoformat(),
            "expires_in_minutes": expires_minutes,
            "model": LIVE_MODEL,
            "voice": LIVE_VOICE_MAP.get(voice.lower(), "Aoede"),
        }
    finally:
        await client.aio.aclose()


def _validate_tool(name: str, args: object) -> dict:
    tool = _TOOLS_BY_NAME.get(name)
    if tool is None or not isinstance(args, dict):
        raise ValueError("Dạ thao tác này chưa được hỗ trợ.")
    schema = tool["parameters"]
    properties = schema.get("properties", {})
    if set(args) - set(properties):
        raise ValueError("Dạ cháu cần kiểm tra lại thao tác Bác yêu cầu.")
    for required in schema.get("required", []):
        if required not in args:
            raise ValueError("Dạ Bác nói rõ thao tác muốn thực hiện giúp cháu nhé.")
    clean = dict(args)
    for key, value in clean.items():
        prop = properties[key]
        if value is None and prop.get("nullable"):
            continue
        kind = prop["type"]
        if kind == "STRING" and (not isinstance(value, str) or len(value) > 500):
            raise ValueError("Dạ nội dung thao tác chưa hợp lệ.")
        if kind == "BOOLEAN" and not isinstance(value, bool):
            raise ValueError("Dạ trạng thái cài đặt chưa hợp lệ.")
        if kind == "NUMBER" and (isinstance(value, bool) or not isinstance(value, (float, int)) or not math.isfinite(value)):
            raise ValueError("Dạ mức điều chỉnh chưa hợp lệ.")
        if "enum" in prop and value not in prop["enum"]:
            raise ValueError("Dạ thao tác này chưa được hỗ trợ.")
        if kind == "NUMBER" and (("minimum" in prop and value < prop["minimum"]) or ("maximum" in prop and value > prop["maximum"])):
            raise ValueError("Dạ mức nhận định chưa hợp lệ.")
    if name == "adjust_settings":
        key = {"font_size": "font_delta", "voice_type": "voice_type", "sound": "sound_enabled"}[clean["setting_type"]]
        if key not in clean:
            raise ValueError("Dạ Bác nói rõ cài đặt muốn thay đổi giúp cháu nhé.")
        if key == "font_delta" and not -0.3 <= clean[key] <= 0.3:
            raise ValueError("Dạ mức thay đổi cỡ chữ quá lớn.")
    if name == "control_radio" and clean.get("action") == "select_genre" and "genre" not in clean:
        raise ValueError("Dạ Bác muốn nghe thể loại nào ạ?")
    if name == "control_voice_memo" and clean.get("action") == "change_topic" and not clean.get("topic"):
        raise ValueError("Dạ Bác muốn kể về chủ đề nào ạ?")
    if name in _CONSENT_TOOLS:
        clean.setdefault("request_kind", "suggestion")
    return clean


def _sanitize_context(context: object) -> dict:
    if not isinstance(context, dict):
        raise ValueError("Dạ trạng thái ứng dụng chưa hợp lệ.")
    # Keep only UI state, never personal data / Chỉ giữ trạng thái giao diện.
    allowed = {
        "route", "radio_playing", "radio_genre", "breathing_state",
        "memo_state", "voice_control_enabled", "sound_enabled", "sos_pending",
        "pending_suggestion_id", "pending_suggestion_type",
        "local_commands",
    }
    result = {}
    for key in allowed:
        value = context.get(key)
        if isinstance(value, bool):
            result[key] = value
        elif isinstance(value, str) and len(value) <= 100:
            result[key] = value
    return result


def _provider_error(exc: Exception) -> tuple[str, bool, bool]:
    detail = str(exc).lower()
    quota = any(word in detail for word in ("quota", "resource_exhausted", "resourceexhausted", "429", "exceeded"))
    unsupported = any(word in detail for word in ("not found", "not supported", "unsupported", "deprecated", "404", "invalid argument", "invalid_argument"))
    if quota:
        message = "Dạ chế độ trò chuyện trực tiếp đang tạm không khả dụng với hạn mức hiện tại. Cháu sẽ thử chế độ dự phòng cho Bác nhé."
    else:
        message = "Dạ đường truyền cuộc gọi đang chập chờn, Bác thử kết nối lại giúp cháu nhé."
    return message, quota, unsupported


async def _bridge_session(session, receive_from_client, send_to_client, model=None, analyzer=None):
    started_at = time.monotonic()
    audio_frames = interruptions = turns = 0
    pending = {}
    completed = {}
    tool_tasks = set()
    tool_failure = asyncio.get_running_loop().create_future()
    app_context = {}
    insight_acks = {}
    turn_input = ""
    response_queue = asyncio.Queue(maxsize=64)
    parallel = ParallelTurnAnalyzer(analyzer, response_queue, lambda: app_context) if analyzer else None
    local_calls = set()
    speaking = False
    spoken_results = []

    async def deliver_result(call_id, name, result, provider_id):
        if call_id in local_calls:
            if name != "report_emotion":
                outcome = {"status": result["status"], "message": result["message"]}
                if speaking:
                    # A finished analysis must not cut the spoken reply in half.
                    # Kết quả phân tích không được cắt ngang câu đang phát.
                    spoken_results.append(outcome)
                else:
                    await session.send_realtime_input(text="KẾT QUẢ TỪ ỨNG DỤNG (chỉ đọc kết quả, không thực hiện lại): " + json.dumps(outcome, ensure_ascii=False))
        else:
            await session.send_tool_response(function_responses=[
                types.FunctionResponse(id=provider_id, name=name, response=result)
            ])

    async def receive_provider():
        try:
            while True:
                received = False
                async for response in session.receive():
                    received = True
                    await response_queue.put(response)
                if not received:
                    raise ConnectionError("Live provider ended the stream")
        except asyncio.CancelledError:
            raise
        except Exception as error:
            await response_queue.put(error)

    async def responses():
        while True:
            response = await response_queue.get()
            if isinstance(response, Exception):
                raise response
            if isinstance(response, CompletedInput):
                if parallel and response.generation == parallel.generation:
                    await send_to_client({'type':'input_turn', 'id':response.id, 'text':response.utterance,
                                          'proposal_id':response.proposal_id})
                continue
            if isinstance(response, AnalysisOutcome):
                if parallel is None or response.generation != parallel.generation:
                    continue
                if response.unavailable:
                    await send_to_client({"type": "analysis_unavailable", "id": response.id,
                                          "turn_id": response.id, "utterance": response.utterance})
                    continue
                result = response.result or {}
                utterance = result.get("transcription") or response.utterance
                utterance = utterance[:MAX_TEXT_LENGTH] if isinstance(utterance, str) else response.utterance
                command = command_from_analysis(result)
                calls = []
                if command is None or command[0] != "respond_to_suggestion":
                    insight = result.get("insight") or normalize_insight(result, utterance)
                    calls.append(SimpleNamespace(id=f"analysis-{response.id}-emotion", name="report_emotion",
                        args={key: insight.get(key) for key in ("emotion", "confidence", "context", "safety_signal")}, utterance=utterance, turn_id=response.id))
                if command is not None:
                    calls.append(SimpleNamespace(id=f"analysis-{response.id}-command", name=command[0], args=command[1], utterance=utterance, turn_id=response.id))
                local_calls.update(call.id for call in calls)
                response = SimpleNamespace(session_resumption_update=None, go_away=None, tool_call_cancellation=None,
                    server_content=None, tool_call=SimpleNamespace(function_calls=calls))
            yield response
            if response.server_content and response.server_content.turn_complete:
                return

    async def respond_to_tool(call_id, name, future, provider_id):
        try:
            try:
                result = await asyncio.wait_for(asyncio.shield(future), TOOL_RESULT_TIMEOUT_SECONDS)
            except asyncio.TimeoutError:
                result = {"status": "failed", "message": "Dạ thao tác chưa hoàn tất kịp, Bác thử lại giúp cháu nhé."}
                await send_to_client({"type": "tool_call_cancellation", "ids": [call_id]})
            if app_context:
                result = {**result, "app_context": app_context.copy()}
            completed[call_id] = (name, result)
            # Bounded session-only memory / Giới hạn bộ nhớ tạm trong phiên.
            await deliver_result(call_id, name, result, provider_id)
        finally:
            pending.pop(call_id, None)

    def check_tool_tasks():
        for task in list(tool_tasks):
            if task.done():
                tool_tasks.discard(task)
                if not task.cancelled():
                    task.result()

    def tool_finished(task):
        if not task.cancelled() and task.exception() and not tool_failure.done():
            tool_failure.set_exception(task.exception())

    async def upstream():
        nonlocal app_context, turn_input, audio_frames
        while True:
            msg = await receive_from_client()
            if msg is None or msg == {}:
                return
            if not isinstance(msg, dict):
                raise ValueError("Dạ tín hiệu cuộc gọi chưa hợp lệ.")
            kind = msg.get("type")
            if kind == "audio":
                encoded = msg.get("data")
                if not isinstance(encoded, str) or len(encoded) > (MAX_AUDIO_CHUNK_BYTES * 4 // 3 + 8):
                    raise ValueError("Dạ đoạn âm thanh chưa hợp lệ.")
                try:
                    pcm = base64.b64decode(encoded, validate=True)
                except (ValueError, TypeError) as exc:
                    raise ValueError("Dạ đoạn âm thanh chưa hợp lệ.") from exc
                if not pcm or len(pcm) > MAX_AUDIO_CHUNK_BYTES or len(pcm) % 2:
                    raise ValueError("Dạ đoạn âm thanh chưa hợp lệ.")
                audio_frames += 1
                if parallel:
                    parallel.audio(pcm)
                await session.send_realtime_input(audio=types.Blob(data=pcm, mime_type="audio/pcm;rate=16000"))
            elif kind == "text":
                text = msg.get("text")
                if not isinstance(text, str) or not text.strip() or len(text) > MAX_TEXT_LENGTH:
                    raise ValueError("Dạ lời nói chưa hợp lệ.")
                turn_input = text
                if parallel:
                    parallel.text(text)
                if app_context:
                    text = "Thông tin trạng thái ứng dụng: " + json.dumps(app_context, ensure_ascii=False) + "\nLời Bác: " + text
                await session.send_realtime_input(text=text)
            elif kind in ("audio_stream_end", "end_of_turn"):
                await session.send_realtime_input(audio_stream_end=True)
            elif kind == "app_context":
                app_context = _sanitize_context(msg.get("context"))
                # State travels in tool acknowledgements, never as a new user turn.
                # Trạng thái đi kèm kết quả công cụ, không cắt ngang lời nói.
            elif kind == 'input_turn_ack':
                turn_id, handled = msg.get('id'), msg.get('handled')
                if not isinstance(turn_id, str) or len(turn_id) > 100 or not isinstance(handled, bool):
                    raise ValueError('Kết quả nhận lệnh chưa hợp lệ.')
                if parallel:
                    parallel.acknowledge(turn_id, handled)
            elif kind == "insight_ack":
                call_id = msg.get("id")
                future = insight_acks.get(call_id) if isinstance(call_id, str) else None
                if future is not None and not future.done():
                    app_context = _sanitize_context(msg.get("context"))
                    future.set_result(None)
            elif kind == "ui_result":
                result = msg.get("result")
                if not isinstance(result, dict) or result.get("status") not in ("executed", "failed", "cancelled", "awaiting_confirmation"):
                    raise ValueError("Kết quả thao tác chưa hợp lệ.")
                message = result.get("message")
                if not isinstance(message, str) or not message.strip() or len(message) > 1000:
                    raise ValueError("Thông báo thao tác chưa hợp lệ.")
                outcome = {"status": result["status"], "message": message, "app_context": app_context}
                if parallel and msg.get('turn_id') in parallel.command_acks and speaking:
                    spoken_results.append(outcome)
                else:
                    await session.send_realtime_input(text="KẾT QUẢ TỪ ỨNG DỤNG (chỉ đọc kết quả, không gọi công cụ): " + json.dumps(outcome, ensure_ascii=False))
            elif kind == "tool_result":
                call_id, name, result = msg.get("id"), msg.get("name"), msg.get("result")
                entry = pending.get(call_id) if isinstance(call_id, str) else None
                if entry and entry[0] == name and not entry[1].done():
                    if not isinstance(result, dict) or result.get("status") not in ("executed", "failed", "cancelled", "awaiting_confirmation"):
                        raise ValueError("Dạ kết quả thao tác chưa hợp lệ.")
                    message = result.get("message")
                    if not isinstance(message, str) or not message.strip() or len(message) > 1000:
                        raise ValueError("Dạ thông báo thao tác chưa hợp lệ.")
                    clean_result = {"status": result["status"], "message": message.strip()}
                    data = result.get("data")
                    if isinstance(data, dict) and isinstance(data.get("proposal_id"), str) and len(data["proposal_id"]) <= 100:
                        clean_result["data"] = {"proposal_id": data["proposal_id"]}
                    entry[1].set_result(clean_result)
            elif kind == "close":
                return
            else:
                raise ValueError("Dạ tín hiệu cuộc gọi chưa được hỗ trợ.")
            check_tool_tasks()

    async def downstream():
        nonlocal turn_input, interruptions, turns, speaking
        # SDK receive ends after one model turn / Nhận liên tục qua nhiều lượt thoại.
        while True:
            check_tool_tasks()
            received = False
            async for response in responses():
                received = True
                update = response.session_resumption_update
                if update and update.resumable and update.new_handle:
                    handle = _encode_resumption(model, update.new_handle) if model else update.new_handle
                    await send_to_client({"type": "resumption_handle", "handle": handle})
                if response.go_away:
                    await send_to_client({"type": "go_away", "time_left": str(response.go_away.time_left)})
                cancellation = response.tool_call_cancellation
                if cancellation:
                    ids = list(cancellation.ids or [])
                    await send_to_client({"type": "tool_call_cancellation", "ids": ids})
                    for call_id in ids:
                        entry = pending.get(call_id)
                        if entry:
                            entry[2].cancel()
                            completed[call_id] = (entry[0], {"status": "cancelled", "message": "Dạ thao tác đã được hủy."})
                content = response.server_content
                if content:
                    if content.interrupted:
                        speaking = False
                        spoken_results.clear()
                        interruptions += 1
                        turn_input = ""
                        if parallel:
                            parallel.interrupt()
                            ids = [call_id for call_id in pending if call_id in local_calls]
                            if ids:
                                await send_to_client({"type": "tool_call_cancellation", "ids": ids})
                            for call_id in ids:
                                pending[call_id][2].cancel()
                        await send_to_client({"type": "interrupted"})
                    if content.model_turn:
                        for part in content.model_turn.parts or []:
                            if part.inline_data and part.inline_data.data:
                                speaking = True
                                await send_to_client({
                                    "type": "audio_chunk",
                                    "data": base64.b64encode(part.inline_data.data).decode("ascii"),
                                    "mime_type": part.inline_data.mime_type or "audio/pcm;rate=24000",
                                })
                    for field, event in (("input_transcription", "transcript_input"), ("output_transcription", "transcript_output")):
                        transcript = getattr(content, field, None)
                        if transcript and transcript.text:
                            if event == "transcript_input":
                                turn_input = (turn_input + transcript.text)[-MAX_TEXT_LENGTH:]
                                if parallel:
                                    parallel.transcript(transcript.text, bool(getattr(transcript, 'finished', False)))
                            await send_to_client({"type": event, "text": transcript.text, "final": bool(getattr(transcript, "finished", False))})
                    grounding = getattr(content, "grounding_metadata", None)
                    if grounding:
                        sources = [{"title": chunk.web.title, "uri": chunk.web.uri} for chunk in grounding.grounding_chunks or [] if chunk.web]
                        await send_to_client({"type": "search_grounding", "queries": grounding.web_search_queries or [], "sources": sources})
                    if content.generation_complete:
                        await send_to_client({"type": "generation_complete"})
                    if parallel and content.model_turn and any(part.inline_data and part.inline_data.data for part in content.model_turn.parts or []):
                        parallel.reply()
                    if content.turn_complete:
                        speaking = False
                        turns += 1
                        if parallel:
                            parallel.end()
                        await send_to_client({"type": "turn_complete"})
                        if spoken_results:
                            outcomes = list(spoken_results)
                            spoken_results.clear()
                            await session.send_realtime_input(text="KẾT QUẢ TỪ ỨNG DỤNG (chỉ đọc kết quả, không thực hiện lại): " + json.dumps(outcomes, ensure_ascii=False))
                if response.tool_call:
                    for call in response.tool_call.function_calls or []:
                        call_id = call.id or uuid.uuid4().hex
                        if call_id in pending:
                            continue
                        if call_id in completed:
                            old_name, result = completed[call_id]
                            await deliver_result(call_id, old_name, result, call.id)
                            continue
                        try:
                            args = _validate_tool(call.name, call.args if call.args is not None else {})
                        except ValueError as exc:
                            await deliver_result(call_id, call.name, {"status": "failed", "message": str(exc)}, call.id)
                            continue
                        if len(pending) >= 32 or len(completed) >= 1024:
                            raise RuntimeError("Too many voice commands in one session")
                        if call.name == "report_emotion":
                            insight = normalize_insight(args, getattr(call, "utterance", turn_input))
                            ack = asyncio.get_running_loop().create_future()
                            insight_acks[call_id] = ack
                            await send_to_client({"type": "companion_insight", "id": call_id, "insight": insight,
                                                  "turn_id": getattr(call, 'turn_id', None)})
                            try:
                                await asyncio.wait_for(ack, INSIGHT_ACK_TIMEOUT_SECONDS)
                            except asyncio.TimeoutError:
                                pass  # Old clients still receive insights / Bản cũ vẫn nhận gợi ý.
                            finally:
                                insight_acks.pop(call_id, None)
                            awaiting_choice = bool(app_context.get("pending_suggestion_id"))
                            instruction = (
                                "Gợi ý đang hiện trong app_context. Hỏi ngắn Bác về đúng gợi ý đó; chưa thực hiện thao tác hoặc gọi điện."
                                if awaiting_choice else
                                "Không có lựa chọn đang chờ. Tiếp tục trả lời Bác ngay, ngắn gọn; không yêu cầu Bác chọn."
                            )
                            result = {"status": "reported", "insight": insight, "app_context": app_context.copy(),
                                      "awaiting_user_choice": awaiting_choice,
                                      "message": instruction + " Nếu đã trả lời đủ thì kết thúc lượt, không lặp câu vừa nói."}
                            completed[call_id] = (call.name, result)
                            await deliver_result(call_id, call.name, result, call.id)
                            continue
                        future = asyncio.get_running_loop().create_future()
                        # Client dedupe IDs must not replace missing provider IDs.
                        # Mã chống lặp trên app không được giả làm mã của nhà cung cấp.
                        task = asyncio.create_task(respond_to_tool(call_id, call.name, future, call.id))
                        task.add_done_callback(tool_finished)
                        pending[call_id] = (call.name, future, task)
                        tool_tasks.add(task)
                        await send_to_client({"type": "tool_call", "id": call_id, "name": call.name, "args": args, "utterance": getattr(call, "utterance", turn_input),
                                              "turn_id": getattr(call, 'turn_id', None)})
                if content and content.turn_complete:
                    turn_input = ""
                check_tool_tasks()
            if not received:
                raise ConnectionError("Live provider ended the stream")

    provider_task = asyncio.create_task(receive_provider())
    tasks = [asyncio.create_task(upstream()), asyncio.create_task(downstream())]
    try:
        done, _ = await asyncio.wait([*tasks, tool_failure], return_when=asyncio.FIRST_COMPLETED)
        for task in done:
            task.result()
    finally:
        for task in tasks + list(tool_tasks) + [tool_failure, provider_task]:
            task.cancel()
        if parallel:
            await parallel.close()
        await asyncio.gather(*tasks, *tool_tasks, tool_failure, provider_task, return_exceptions=True)
        pending.clear()
        completed.clear()
        insight_acks.clear()
        local_calls.clear()
        app_context.clear()
        logger.info("Live session ended (model=%s seconds=%.1f audio_frames=%s turns=%s interruptions=%s)",
                    model, time.monotonic() - started_at, audio_frames, turns, interruptions)


async def handle_live_session(
    receive_from_client: Callable[[], Awaitable[Optional[dict]]],
    send_to_client: Callable[[dict], Awaitable[None]],
    voice: str = "aoede",
    display_name: str = "Bác",
    session_handle: Optional[str] = None,
):
    """Proxy live audio and acknowledged tools / Chuyển thoại và kết quả thao tác thật."""
    api_key = os.getenv("GEMINI_API_KEY", "")
    if not api_key:
        await send_to_client({"type": "error", "is_quota": False, "message": "Dạ cuộc gọi chưa sẵn sàng, Bác thử lại sau nhé."})
        return
    models = list(dict.fromkeys(CANDIDATE_LIVE_MODELS))
    if session_handle:
        try:
            resumed_model, session_handle = _decode_resumption(session_handle)
            models = [resumed_model]
        except ValueError:
            await send_to_client({"type": "error", "is_quota": False, "message": "Dạ phiên cũ chưa khôi phục được. Bác kết nối lại giúp cháu nhé."})
            return
    client = genai.Client(api_key=api_key, http_options=types.HttpOptions(timeout=10000))
    try:
        deadline = time.monotonic() + 8
        for index, model in enumerate(models):
            started = False
            try:
                async with AsyncExitStack() as stack:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        raise asyncio.TimeoutError()
                    session = await asyncio.wait_for(stack.enter_async_context(client.aio.live.connect(
                        model=model, config=_live_config(model, voice, display_name, session_handle)
                    )), timeout=min(4, remaining))
                    started = True
                    await send_to_client({"type": "session_started", "model": model,
                                          "analysis_mode": "parallel" if model == LEGACY_NATIVE_MODEL else "tools",
                                          **({'local_command_handoff':True} if model == LEGACY_NATIVE_MODEL else {})})
                    await _bridge_session(session, receive_from_client, send_to_client, model=model,
                                          analyzer=analyze_turn if model == LEGACY_NATIVE_MODEL else None)
                    return
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                message, quota, unsupported = _provider_error(exc)
                # Do not replay side effects after a started session / Không phát lại lệnh sau phiên đã mở.
                if not started and not session_handle and (quota or unsupported) and index + 1 < len(models):
                    logger.warning("Live model unavailable; trying documented fallback: %s", model)
                    continue
                code = getattr(getattr(exc, "rcvd", None), "code", None) or getattr(exc, "code", None)
                logger.warning("Live session failed (model=%s type=%s code=%s started=%s)", model, type(exc).__name__, code, started)
                await send_to_client({"type": "error", "is_quota": quota, "message": message})
                return
    finally:
        await client.aio.aclose()
