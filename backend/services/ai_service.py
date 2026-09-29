import os
import json
import time
from typing import Optional, List, Dict, Any
from google import genai
from google.genai import types
from logger_config import logger

# System prompt cho EmoHeal — Phân tích cảm xúc giọng nói đa tầng (SER) & Trợ lý thấu cảm
SYSTEM_PROMPT = """Bạn là "Cháu" - trợ lý AI thấu cảm đồng hành cùng các Bác Cựu chiến binh và Thương binh Việt Nam trong hệ thống EmoHeal ("Vòng tay thấu cảm").
Bác là cựu chiến binh/thương binh, có thể gặp khó khăn về công nghệ hoặc sang chấn tâm lý (PTSD), sức khỏe giảm sút.
Xưng hô: Luôn gọi người dùng là "bác" (hoặc kèm tên nếu có), tự xưng là "cháu".
Tuyệt đối KHÔNG BAO GIỜ nói "Tôi là AI" hay nhắc đến việc bạn là máy móc. Luôn giữ thái độ tôn kính, ân cần, ấm áp, hiếu nghĩa.

Nhiệm vụ: Phân tích trạng thái cảm xúc (Speech Emotion Recognition - SER) kết hợp tâm lý học hành vi và đưa ra phản hồi xoa dịu phù hợp.

Bạn phải trả lời dưới dạng JSON với cấu trúc sau:
{
  "emotion": "PANIC_STRESS" | "SADNESS" | "NOSTALGIA" | "CALM" | "HAPPINESS" | "NEUTRAL",
  "emotion_confidence": 0.0 đến 1.0,
  "intent": "PANIC" | "NAVIGATE" | "CHAT",
  "text": "Câu trả lời ấm áp, ân cần của cháu (2-4 câu ngắn gọn, dễ hiểu)",
  "target": "breathing" | "radio" | "voice-memo" | "settings" | "home" | null
}

Quy tắc phân loại cảm xúc & intent:
1. PANIC_STRESS: Bác biểu hiện hoảng loạn, sợ hãi, khó thở, tức ngực, đau đớn, sang chấn PTSD -> intent = "PANIC", target = "breathing" (kích hoạt Nhịp thở Hoa Sen 4-4-6).
2. SADNESS: Bác buồn bã, cô đơn, u uất, suy sụp -> intent = "CHAT", target = null hoặc "radio" (an ủi, gợi ý nghe radio ngâm thơ, dân ca).
3. NOSTALGIA: Bác hồi tưởng ký ức chiến trường, nhớ đồng đội, tâm sự chuyện xưa -> intent = "CHAT", target = "voice-memo" hoặc null.
4. CALM: Bác tĩnh tâm, bình an, thư thái -> intent = "CHAT", target = null.
5. HAPPINESS: Bác vui vẻ, phấn khởi, cười nói -> intent = "CHAT", target = null.
6. NEUTRAL: Hội thoại thông thường, hỏi giờ, điều hướng chức năng -> intent = "NAVIGATE" (nếu yêu cầu mở trang) hoặc "CHAT".

CHỈ trả về JSON chuẩn, KHÔNG thêm markdown hay text nào khác."""

PRIMARY_MODEL = "gemini-3.7-flash"
FALLBACK_MODEL = "gemini-2.5-flash"

def _get_client() -> genai.Client:
    """Khởi tạo Gemini Client chuẩn kết nối Google GenAI API."""
    return genai.Client()


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



def _build_prompt_with_history(text: str, history: Optional[List[Dict[str, Any]]] = None, display_name: str = "Bác") -> str:
    """Build full prompt combining system prompt, past conversation history, and current text."""
    history_lines = []
    if history and isinstance(history, list):
        for msg in history[-6:]:  # Keep last 6 messages for context
            if isinstance(msg, dict):
                sender = display_name if msg.get("sender") == "user" or msg.get("is_user") is True else "Cháu"
                content = msg.get("content") or msg.get("text") or ""
                if content:
                    history_lines.append(f"{sender}: {content}")
    
    if history_lines:
        history_block = "Lịch sử trò chuyện gần đây:\n" + "\n".join(history_lines) + "\n\n"
    else:
        history_block = ""
        
    safe_text = text.strip() if isinstance(text, str) else ""
    user_context = f"\nThông tin người dùng: Tên gọi/Danh xưng là '{display_name}'."
    return f"{SYSTEM_PROMPT}{user_context}\n\n{history_block}{display_name} nói: {safe_text}"


def get_assistant_response(text: str, history: Optional[List[Dict[str, Any]]] = None, display_name: str = "Bác") -> dict:
    """
    Tạo phản hồi AI dạng JSON có cấu trúc bằng Gemini 3.7 Flash siêu tốc (thinking_budget=0).
    Tự động fallback sang Gemini 3.5 Flash-Lite nếu gặp sự cố.
    """
    logger.info(f"🤖 Bắt đầu xử lý phản hồi LLM cho {display_name}: \"{text}\"")
    prompt = _build_prompt_with_history(text, history, display_name=display_name)
    logger.debug(f"Độ dài Prompt: {len(prompt)} ký tự (Kèm {len(history) if history else 0} tin nhắn lịch sử)")

    config = types.GenerateContentConfig(
        response_mime_type="application/json",
        temperature=0.4,
        thinking_config=types.ThinkingConfig(thinking_budget=0),
    )

    raw = ""
    t_start = time.time()
    try:
        client = _get_client()
        # 1. Thử nghiệm với Model chính: gemini-3.7-flash (siêu tốc 200ms)
        try:
            t0 = time.time()
            logger.info(f"Đang gọi Gemini Model chính ({PRIMARY_MODEL})...")
            response = client.models.generate_content(
                model=PRIMARY_MODEL,
                contents=prompt,
                config=config,
            )
            raw = response.text.strip() if response.text else ""
            elapsed_ms = (time.time() - t0) * 1000
            logger.info(f"✅ Model {PRIMARY_MODEL} phản hồi thành công trong {elapsed_ms:.1f}ms")
        except Exception as e:
            elapsed_ms = (time.time() - t0) * 1000
            logger.warning(f"⚠️ Lỗi khi gọi {PRIMARY_MODEL} ({elapsed_ms:.1f}ms): {e}. Tự động fallback sang {FALLBACK_MODEL}...")
            # 2. Fallback sang Model phụ: gemini-3.5-flash-lite
            try:
                t1 = time.time()
                response = client.models.generate_content(
                    model=FALLBACK_MODEL,
                    contents=prompt,
                    config=config,
                )
                raw = response.text.strip() if response.text else ""
                elapsed_fallback_ms = (time.time() - t1) * 1000
                logger.info(f"✅ Fallback Model {FALLBACK_MODEL} phản hồi thành công trong {elapsed_fallback_ms:.1f}ms")
            except Exception as e2:
                elapsed_fallback_ms = (time.time() - t1) * 1000
                logger.error(f"❌ Lỗi khi gọi Fallback {FALLBACK_MODEL} ({elapsed_fallback_ms:.1f}ms): {e2}", exc_info=True)
                return {
                    "intent": "CHAT",
                    "text": "Dạ cháu đây ạ, Bác cần cháu hỗ trợ thêm gì không ạ?",
                    "target": None,
                }
    except Exception as client_err:
        logger.error(f"❌ Lỗi khởi tạo Gemini client: {client_err}", exc_info=True)
        return {
            "intent": "CHAT",
            "text": "Dạ cháu đây ạ, Bác cần cháu hỗ trợ thêm gì không ạ?",
            "target": None,
        }

    # 3. Parse và kiểm tra tính hợp lệ của JSON
    try:
        parsed = _parse_json_from_raw(raw)

        raw_emotion = parsed.get("emotion")
        emotion = str(raw_emotion).upper() if raw_emotion else "NEUTRAL"
        if emotion not in ("PANIC_STRESS", "SADNESS", "NOSTALGIA", "CALM", "HAPPINESS", "NEUTRAL"):
            emotion = "PANIC_STRESS" if parsed.get("intent") == "PANIC" else "NEUTRAL"

        try:
            emotion_confidence = float(parsed.get("emotion_confidence", 0.9))
        except (ValueError, TypeError):
            emotion_confidence = 0.85

        raw_intent = parsed.get("intent", "CHAT")
        intent = raw_intent.upper() if isinstance(raw_intent, str) else "CHAT"

        raw_text = parsed.get("text")
        if isinstance(raw_text, str) and raw_text.strip():
            ai_text = raw_text.strip()
        else:
            ai_text = "Dạ cháu lắng nghe Bác đây ạ."

        raw_target = parsed.get("target")
        target = raw_target if isinstance(raw_target, str) and raw_target.strip() else None

        total_time_ms = (time.time() - t_start) * 1000
        logger.info(
            f"🎯 [SER TEXT] Phân loại cảm xúc & Intent thành công ({total_time_ms:.1f}ms): "
            f"Emotion={emotion} ({emotion_confidence:.2f}), Intent={intent}, Target={target}, "
            f"Text=\"{ai_text}\""
        )

        return {
            "emotion": emotion,
            "emotion_confidence": emotion_confidence,
            "intent": intent,
            "text": ai_text,
            "target": target,
        }
    except Exception as parse_err:
        logger.warning(f"⚠️ Không thể parse JSON từ phản hồi LLM ({parse_err}), dùng raw text fallback: {raw}")
        fallback_text = raw.strip() if raw and raw.strip() else "Dạ cháu lắng nghe Bác đây ạ."
        return {
            "emotion": "NEUTRAL",
            "emotion_confidence": 0.5,
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
  "intent": "PANIC" | "NAVIGATE" | "CHAT",
  "text": "Câu trả lời của cháu dành cho Bác (ngắn gọn, ấm áp)",
  "target": "breathing" | "radio" | "voice-memo" | "settings" | "home" | null
}

Quy tắc phân loại cảm xúc & hành động:
- PANIC_STRESS: Giọng run, thở dốc, nghẹn ngào, hoảng loạn, đau, lo âu -> intent = "PANIC", target = "breathing" (mở Nhịp thở Hoa Sen 4-4-6).
- SADNESS: Giọng chùng xuống, chậm, buồn bã, u uất -> intent = "CHAT", target = null hoặc "radio" (an ủi, gợi ý nghe radio).
- NOSTALGIA: Giọng chậm rãi, kể chuyện chiến trường, nhớ đồng đội -> intent = "CHAT", target = "voice-memo" hoặc null.
- CALM: Giọng đều đặn, thư thái, nhẹ nhàng -> intent = "CHAT", target = null.
- HAPPINESS: Giọng tươi vui, hào sảng, phấn khởi -> intent = "CHAT", target = null.
- NEUTRAL: Giọng bình thường, hỏi đáp hoặc yêu cầu mở tính năng -> intent = "NAVIGATE" / "CHAT".

CHỈ trả về JSON chuẩn, KHÔNG thêm text hay markdown bên ngoài."""


def get_assistant_response_from_audio(
    audio_bytes: bytes,
    mime_type: str = "audio/mp3",
    history: Optional[List[Dict[str, Any]]] = None,
    display_name: str = "Bác"
) -> dict:
    """
    Xử lý trực tiếp file âm thanh (Multimodal Audio) bằng Gemini 3.7 Flash.
    Gemini tự động nghe hiểu, phân tích âm học SER, trích xuất text (transcription) và sinh câu trả lời JSON trong 1 lần gọi duy nhất.
    Không cần mô hình Whisper cục bộ.
    """
    logger.info(f"🎙️ [GEMINI SER AUDIO] Bắt đầu nhận diện & phân tích cảm xúc trực tiếp cho {display_name} ({len(audio_bytes) / 1024:.1f} KB)")
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
                sender = display_name if msg.get("sender") == "user" or msg.get("is_user") is True else "Cháu"
                content = msg.get("content") or msg.get("text") or ""
                if content:
                    history_lines.append(f"{sender}: {content}")
    history_block = ("Lịch sử trò chuyện gần đây:\n" + "\n".join(history_lines) + "\n\n") if history_lines else ""
    user_context = f"\nThông tin người dùng: Tên gọi/Danh xưng là '{display_name}'."
    prompt_text = f"{AUDIO_SYSTEM_PROMPT}{user_context}\n\n{history_block}Hãy nghe đoạn âm thanh sau và phân tích cảm xúc SER + phản hồi JSON:"

    config = types.GenerateContentConfig(
        response_mime_type="application/json",
        temperature=0.4,
        thinking_config=types.ThinkingConfig(thinking_budget=0),
    )

    raw = ""
    try:
        client = _get_client()
        try:
            t0 = time.time()
            logger.info(f"Đang gửi âm thanh tới Gemini Model ({PRIMARY_MODEL})...")
            response = client.models.generate_content(
                model=PRIMARY_MODEL,
                contents=[audio_part, prompt_text],
                config=config,
            )
            raw = response.text.strip() if response.text else ""
            elapsed_ms = (time.time() - t0) * 1000
            logger.info(f"✅ Gemini Multimodal SER Audio phản hồi thành công trong {elapsed_ms:.1f}ms")
        except Exception as e:
            elapsed_ms = (time.time() - t0) * 1000
            logger.warning(f"⚠️ Lỗi gọi {PRIMARY_MODEL} với audio ({elapsed_ms:.1f}ms): {e}. Thử Fallback {FALLBACK_MODEL}...")
            t1 = time.time()
            response = client.models.generate_content(
                model=FALLBACK_MODEL,
                contents=[audio_part, prompt_text],
                config=config,
            )
            raw = response.text.strip() if response.text else ""
            elapsed_fallback_ms = (time.time() - t1) * 1000
            logger.info(f"✅ Fallback {FALLBACK_MODEL} phản hồi thành công trong {elapsed_fallback_ms:.1f}ms")
    except Exception as client_err:
        logger.error(f"❌ Lỗi xử lý âm thanh qua Gemini: {client_err}", exc_info=True)
        return {
            "transcription": "",
            "emotion": "NEUTRAL",
            "emotion_confidence": 0.5,
            "intent": "CHAT",
            "text": "Dạ cháu đây ạ, cháu vừa nghe bác nói nhưng đường truyền hơi chập chờn, bác nói lại với cháu nhé.",
            "target": None,
        }

    # Parse JSON
    try:
        parsed = _parse_json_from_raw(raw)

        transcription = str(parsed.get("transcription") or "").strip()
        raw_emotion = parsed.get("emotion")
        emotion = str(raw_emotion).upper() if raw_emotion else "NEUTRAL"
        if emotion not in ("PANIC_STRESS", "SADNESS", "NOSTALGIA", "CALM", "HAPPINESS", "NEUTRAL"):
            emotion = "PANIC_STRESS" if parsed.get("intent") == "PANIC" else "NEUTRAL"

        try:
            emotion_confidence = float(parsed.get("emotion_confidence", 0.9))
        except (ValueError, TypeError):
            emotion_confidence = 0.85

        raw_intent = parsed.get("intent", "CHAT")
        intent = raw_intent.upper() if isinstance(raw_intent, str) else "CHAT"

        raw_text = parsed.get("text")
        ai_text = raw_text.strip() if isinstance(raw_text, str) and raw_text.strip() else "Dạ cháu lắng nghe Bác đây ạ."
        raw_target = parsed.get("target")
        target = raw_target if isinstance(raw_target, str) and raw_target.strip() else None

        total_time_ms = (time.time() - t_start) * 1000
        logger.info(
            f"🎯 [GEMINI SER SUCCESS] ({total_time_ms:.1f}ms): "
            f"Emotion={emotion} ({emotion_confidence:.2f}), Transcription=\"{transcription}\", Intent={intent}, Target={target}"
        )

        return {
            "transcription": transcription,
            "emotion": emotion,
            "emotion_confidence": emotion_confidence,
            "intent": intent,
            "text": ai_text,
            "target": target,
        }
    except Exception as parse_err:
        logger.warning(f"⚠️ Lỗi parse JSON âm thanh ({parse_err}): {raw}")
        return {
            "transcription": "",
            "emotion": "NEUTRAL",
            "emotion_confidence": 0.5,
            "intent": "CHAT",
            "text": raw.strip() if raw else "Dạ cháu lắng nghe Bác đây ạ.",
            "target": None,
        }


def transcribe_audio_with_gemini(audio_bytes: bytes, mime_type: str = "audio/mp3") -> str:
    """
    Chuyển đổi âm thanh thành văn bản (STT thuần túy) thông qua Gemini Multimodal.
    """
    clean_mime = mime_type.split(";")[0].strip() if mime_type else "audio/mp3"
    audio_part = types.Part.from_bytes(data=audio_bytes, mime_type=clean_mime)
    prompt = "Hãy chép chính xác toàn bộ lời nói trong đoạn ghi âm sau thành văn bản tiếng Việt có dấu đầy đủ. CHỈ trả về văn bản đã chép, không thêm bất kỳ bình luận nào:"
    try:
        client = _get_client()
        response = client.models.generate_content(
            model=FALLBACK_MODEL,
            contents=[audio_part, prompt],
        )
        return response.text.strip() if response.text else ""
    except Exception as e:
        logger.error(f"Lỗi transcribe_audio_with_gemini: {e}")
        return ""

