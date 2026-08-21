import os
import json
from google import genai

# System prompt for LotusHaven — structured JSON response per AI architecture spec
# Prompt hệ thống — trả JSON có cấu trúc theo spec
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

CHỈ trả về JSON, KHÔNG thêm markdown hay text nào khác."""


def get_assistant_response(text: str) -> str:
    """Generate structured JSON AI response / Tạo phản hồi AI dạng JSON có cấu trúc"""
    client = genai.Client()

    prompt = f"{SYSTEM_PROMPT}\n\nBác nói: {text}"

    response = client.models.generate_content(
        model='gemini-2.5-flash',
        contents=prompt,
    )

    raw = response.text.strip()

    # Parse and validate JSON / Kiểm tra JSON hợp lệ
    try:
        # Strip markdown code fences if present / Loại bỏ markdown nếu có
        if raw.startswith("```"):
            raw = raw.split("\n", 1)[1].rsplit("```", 1)[0].strip()
        parsed = json.loads(raw)

        # Ensure required fields / Đảm bảo có đủ trường bắt buộc
        result = {
            "intent": parsed.get("intent", "CHAT"),
            "text": parsed.get("text", "Cháu xin lỗi bác, cháu chưa hiểu ạ."),
            "target": parsed.get("target"),
        }
        return result
    except (json.JSONDecodeError, AttributeError):
        # Fallback if Gemini doesn't return valid JSON / Fallback khi JSON lỗi
        return {
            "intent": "CHAT",
            "text": raw if raw else "Cháu xin lỗi bác, cháu chưa hiểu ạ.",
            "target": None,
        }
