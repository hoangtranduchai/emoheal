import os
import json
import logging
from google import genai
from google.genai import types

logger = logging.getLogger(__name__)

# System prompt cho LotusHaven — Định dạng JSON theo AI architecture spec
SYSTEM_PROMPT = """Bạn là người cháu ngoan ngoãn, ân cần đang trò chuyện với bác của mình.
Bác là cựu chiến binh/thương binh, có thể gặp khó khăn về công nghệ hoặc sức khỏe.
Xưng hô: Luôn gọi người dùng là "bác", tự xưng là "cháu".
Tuyệt đối KHÔNG BAO GIỜ nói "Tôi là AI" hay nhắc đến việc bạn là máy móc.

Bạn phải trả lời dưới dạng JSON với cấu trúc sau:
{
  "intent": "PANIC" | "NAVIGATE" | "CHAT",
  "text": "Câu trả lời của bạn dành cho bác (ngắn gọn, ấm áp, 2-4 câu)",
  "target": "breathing" | "radio" | "voice-memo" | "settings" | "home" | null
}

Quy tắc phân loại intent:
- PANIC: Khi bác bày tỏ lo lắng, buồn, sợ hãi, mệt mỏi, căng thẳng, đau → target = "breathing"
- NAVIGATE: Khi bác muốn mở chức năng (radio, ghi âm, cài đặt, trang chủ) → target = tên màn hình tương ứng
- CHAT: Trò chuyện thông thường → target = null

CHỈ trả về JSON chuẩn, KHÔNG thêm markdown hay text nào khác."""

PRIMARY_MODEL = "gemini-3.7-flash"
FALLBACK_MODEL = "gemini-3.5-flash-lite"


def get_assistant_response(text: str, history: list = None) -> dict:
    """
    Tạo phản hồi AI dạng JSON có cấu trúc bằng Gemini 3.7 Flash
    Tự động fallback sang Gemini 3.5 Flash-Lite nếu gặp sự cố.
    """
    client = genai.Client()
    prompt = f"{SYSTEM_PROMPT}\n\nBác nói: {text}"

    config = types.GenerateContentConfig(
        response_mime_type="application/json",
        temperature=0.7,
    )

    raw = ""
    # 1. Thử nghiệm với Model chính: gemini-3.7-flash
    try:
        response = client.models.generate_content(
            model=PRIMARY_MODEL,
            contents=prompt,
            config=config,
        )
        raw = response.text.strip()
    except Exception as e:
        logger.warning(f"Lỗi khi gọi {PRIMARY_MODEL}, chuyển sang {FALLBACK_MODEL}: {e}")
        # 2. Fallback sang Model phụ: gemini-3.5-flash-lite
        try:
            response = client.models.generate_content(
                model=FALLBACK_MODEL,
                contents=prompt,
                config=config,
            )
            raw = response.text.strip()
        except Exception as e2:
            logger.error(f"Lỗi khi gọi {FALLBACK_MODEL}: {e2}")
            return {
                "intent": "CHAT",
                "text": "Dạ cháu đây ạ, Bác cần cháu hỗ trợ thêm gì không ạ?",
                "target": None,
            }

    # 3. Parse và kiểm tra tính hợp lệ của JSON
    try:
        if raw.startswith("```"):
            raw = raw.split("\n", 1)[1].rsplit("```", 1)[0].strip()
        parsed = json.loads(raw)

        return {
            "intent": parsed.get("intent", "CHAT"),
            "text": parsed.get("text", "Dạ cháu lắng nghe Bác đây ạ."),
            "target": parsed.get("target"),
        }
    except (json.JSONDecodeError, AttributeError):
        return {
            "intent": "CHAT",
            "text": raw if raw else "Dạ cháu lắng nghe Bác đây ạ.",
            "target": None,
        }
