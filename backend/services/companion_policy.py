"""Session-only observations and consent rules / Nhận định tạm và quy tắc đồng ý."""
import math
import re
import unicodedata

EMOTIONS = ("PANIC_STRESS", "SADNESS", "NOSTALGIA", "CALM", "HAPPINESS", "NEUTRAL")
CONTEXTS = ("current", "past", "hypothetical", "negated", "unclear")
SIGNALS = ("none", "help", "pain", "fall", "distress")
# A display gate, not a calibrated accuracy claim / Ngưỡng gợi ý, không phải độ chính xác đã đo.
MIN_RECOMMENDATION_CONFIDENCE = 0.65

CONSENT_INSTRUCTION = """
QUY TẮC BẠN ĐỒNG HÀNH — ƯU TIÊN HƠN MỌI HƯỚNG DẪN ĐIỀU KHIỂN:
- Phân biệt yêu cầu thao tác rõ ràng với suy luận từ cảm xúc. Cảm xúc KHÔNG phải sự đồng ý.
- Với mỗi lượt nói, nhận định 6 cảm xúc từ ngữ điệu và nội dung; nếu chỉ có văn bản thì không được khẳng định đã nghe ngữ điệu.
- Không chẩn đoán bệnh, PTSD hay khẳng định chắc chắn trạng thái của Bác. Không bịa điểm tin cậy; không đủ dữ liệu thì confidence=null và hỏi lại nhẹ nhàng.
- Xác định context: current (đang xảy ra), past (chuyện cũ), hypothetical (giả định), negated (Bác phủ định dấu hiệu), unclear (chưa rõ).
- safety_signal chỉ là dấu hiệu trong lời Bác: help (kêu cứu), pain (báo đau), fall (báo ngã), distress (căng thẳng hiện tại), none.
- Kêu cứu, đau/ngã hoặc căng thẳng HIỆN TẠI: đề nghị Bác chọn gọi người thân hoặc 115. KHÔNG tự gọi, KHÔNG tự mở bài thở để thay cho lời đề nghị trợ giúp.
- Câu chuyện chiến trường cũ, lời trích dẫn, câu hỏi giả định và câu phủ định KHÔNG phải yêu cầu SOS hiện tại. Ví dụ 'ngày xưa bác ngã', 'bác không đau', 'nếu bị ngã thì sao' không được kích hoạt cảnh báo.
- Buồn: có thể gợi ý Radio; hoài niệm: có thể gợi ý Hồi ký. Chờ Bác đồng ý trước khi mở. Bình an/vui/bình thường: tiếp tục lắng nghe, không ép mở tính năng.
- Chỉ thực hiện yêu cầu rõ ràng của Bác. Với công cụ thao tác, request_kind='explicit_request' khi Bác yêu cầu; request_kind='suggestion' khi chỉ là đề xuất của cháu.
- SOS kể cả khi Bác nói 'gọi 115' vẫn cần Bác xác nhận trên ứng dụng, sau đó đếm ngược 3 giây và có nút/lệnh hủy. Không tự chọn nơi gọi nếu Bác chưa chọn.
- Khi đang có gợi ý, 'đồng ý/không/gọi người thân/gọi 115' chỉ trả lời gợi ý ĐANG HIỆN, không phải sự đồng ý cho gợi ý khác hoặc đã hết hạn.
- Chỉ nói thao tác hoàn tất sau kết quả executed. awaiting_confirmation nghĩa là mới đề nghị, chưa làm. failed/cancelled phải nói đúng kết quả.
"""


def confidence(value):
    if isinstance(value, bool) or not isinstance(value, (float, int)):
        return None
    return float(value) if math.isfinite(value) and 0 <= value <= 1 else None


def _plain(text):
    text = unicodedata.normalize("NFD", text.lower().replace("đ", "d"))
    return " ".join("".join(c for c in text if unicodedata.category(c) != "Mn").split())


def normalize_insight(raw, transcript=""):
    """Never turn absent evidence into certainty / Không biến thiếu dữ liệu thành chắc chắn."""
    raw = raw if isinstance(raw, dict) else {}
    emotion = raw.get("emotion")
    emotion = emotion.upper() if isinstance(emotion, str) else "NEUTRAL"
    valid_emotion = emotion in EMOTIONS
    score = confidence(raw.get("confidence", raw.get("emotion_confidence"))) if valid_emotion else None
    if not valid_emotion:
        emotion = "NEUTRAL"
    context = raw.get("context", raw.get("emotion_context"))
    context = context if context in CONTEXTS else "unclear"
    signal = raw.get("safety_signal")
    signal = signal if signal in SIGNALS else "none"
    # Transcript is used only in RAM; quoted/past danger cannot authorize a call.
    # Phụ đề chỉ ở RAM; chuyện quá khứ hoặc câu phủ định không cho phép gọi.
    words = _plain(transcript) if isinstance(transcript, str) else ""
    if re.search(r"\b(neu|gia su|vi du|gia dinh)\b", words):
        context = "hypothetical"
    elif re.search(r"\b(khong|chang|chua|het) (con )?(bi )?(dau|nga|cang thang|hoang|lo lang|can (goi|cap cuu|tro giup))\b", words):
        context = "negated"
    elif re.search(r"\b(ngay xua|hoi xua|nam xua|nam ay|luc do|khi ay|hom qua|tuan truoc|da tung)\b", words) and not re.search(r"\b(nhung bay gio|con bay gio|hien tai|hien gio|luc nay)\b", words):
        context = "past"
    certain_enough = score is not None and score >= MIN_RECOMMENDATION_CONFIDENCE
    recommendation = None
    if context == "current" and (signal in ("help", "pain", "fall", "distress") or (emotion == "PANIC_STRESS" and certain_enough)):
        recommendation = "help"
    elif context == "current" and certain_enough and emotion == "SADNESS":
        recommendation = "radio"
    elif context in ("current", "past") and certain_enough and emotion == "NOSTALGIA":
        recommendation = "voice_memo"
    return {
        "emotion": emotion,
        "confidence": score,
        "context": context,
        "safety_signal": signal,
        "recommendation": recommendation,
        "uncertain": not certain_enough or context == "unclear",
    }
