import os
import uuid
import time
import hashlib
import asyncio
import re
import io
import wave
from collections import OrderedDict
from typing import Optional, Dict
from google import genai
from google.genai import types
from logger_config import logger

VOICE_MAP = {
    "aoede": "Aoede",
    "charon": "Charon",
    "female": "Aoede",
    "male": "Charon",
}

DEFAULT_VOICE = "Aoede"
FALLBACK_VOICE = "Charon"

CACHE_DIR = "static/cache"
_memory_cache: Dict[str, bytes] = OrderedDict()
MAX_CACHE_BYTES = 16 * 1024 * 1024
TTS_MODEL = os.getenv("GEMINI_TTS_MODEL", "gemini-3.1-flash-tts-preview")
_synthesis_locks: Dict[str, asyncio.Lock] = {}

def sanitize_tts_text(text: str) -> str:
    """
    Chuẩn hóa ngữ âm trước khi đưa vào TTS engine:
    - Duy nhất từ 'EmoHeal' / 'emoheal' phải phát âm chuẩn bằng tiếng Anh ('I-mô-hêu' [ˈiːmoʊhiːl]).
    """
    if not text:
        return ""
    return re.sub(r'(?i)\bemoheal\b', 'I-mô-hêu', text)

# ══════════════════════════════════════════════════════════════════════════════
# MASTER VOICE SCRIPTS CATALOG (Danh mục kịch bản thoại chuẩn mực EmoHeal)
# ══════════════════════════════════════════════════════════════════════════════
MASTER_VOICE_SCRIPTS: Dict[str, str] = {
    # ── 1. Hướng dẫn Màn hình & Xác thực (Auth & Onboarding) ──
    "ONBOARDING": (
        "Kính chào Bác! Chào mừng Bác đến với EmoHeal - Vòng tay thấu cảm đồng hành cùng Cựu chiến binh và Thương binh. "
        "Bác có thể chạm vào nút Bắt đầu ngay màu xanh ở dưới, hoặc sử dụng giọng nói để điều khiển toàn bộ ứng dụng cùng cháu nhé ạ."
    ),
    "LOGIN": (
        "Kính chào Bác! Bác vui lòng nhập số điện thoại của mình rồi bấm nút Tiếp tục. "
        "Nếu là lần đầu sử dụng, cháu sẽ gửi mã xác thực về máy Bác để tạo tài khoản, "
        "còn nếu Bác đã có tài khoản rồi thì cháu sẽ đón Bác vào ứng dụng ngay nhé ạ."
    ),
    "OTP": (
        "Mã xác thực gồm bốn chữ số đã được gửi qua tin nhắn đến số điện thoại của Bác. "
        "Bác vui lòng kiểm tra tin nhắn và điền bốn số đó vào các ô bên dưới nhé ạ."
    ),

    # ── 2. Trang chủ & Trợ lý AI Tâm sự (Home & Chat) ──
    "HOME": (
        "Dạ cháu chào Bác! Đây là trang chủ EmoHeal - Vòng tay thấu cảm. Tại đây, Bác có thể mở Hồi ký giọng nói, "
        "tập Nhịp thở hoa sen, nghe Đài radio, vào Cài đặt hoặc gọi cho Người thân. "
        "Bác cũng có thể bấm giữ nút SOS lớn màu đỏ khi cần trợ giúp, hoặc chỉ cần nói để cháu tự động điều khiển toàn bộ tính năng cho Bác ạ."
    ),
    "CHAT": (
        "Dạ cháu lắng nghe Bác đây ạ. Bác có thể nhắn tin hoặc bấm giữ nút micro màu xanh để nói chuyện. "
        "Cháu có thể giải đáp tâm sự, đọc thơ, hoặc tự động chuyển màn hình theo yêu cầu của Bác nhé ạ."
    ),
    "ASSISTANT_READY": "Dạ cháu lắng nghe Bác đây ạ.",
    "ASSISTANT_NETWORK_ERROR": "Dạ kết nối mạng đang chập chờn, Bác vui lòng thử lại sau giây lát hoặc kiểm tra kết nối mạng nhé ạ.",

    # ── 3. Đài Radio & Hồi ký Giọng nói (Radio & Voice Memo) ──
    "RADIO": (
        "Chào mừng Bác đến với Đài Radio Hoài Niệm. Bác có thể chạm vào danh sách bài phát để nghe, "
        "hoặc nói tên bài hát yêu thích để cháu tự động bật cho Bác nghe nhé ạ."
    ),
    "RADIO_PLAYING": "Dạ cháu đang phát chương trình đài cho Bác thưởng thức đây ạ.",
    "VOICE_MEMO": (
        "Đây là góc lưu giữ Hồi ký Giọng nói. Bác chạm vào nút Ghi âm lớn màu xanh để bắt đầu kể lại những kỷ niệm đáng nhớ của đời mình. "
        "Cháu sẽ tự động lưu trữ an toàn cho Bác ạ."
    ),
    "RECORDING_STARTED": "Dạ cháu đang ghi âm hồi ký cho Bác rồi ạ. Bác cứ thong thả chia sẻ nhé ạ.",
    "RECORDING_SAVED": "Dạ cháu đã lưu bản hồi ký của Bác vào bộ nhớ an toàn rồi ạ.",

    # ── 4. Nhịp thở Hoa Sen (Chu kỳ 4 - 4 - 6) ──
    "BREATHING_INTRO": (
        "Chào Bác! Đây là bài tập Nhịp thở Hoa Sen giúp Bác thư giãn tâm trí và điều hòa huyết áp."
    ),
    "BREATH_INHALE": "Bác hãy hít vào từ từ nhé...",
    "BREATH_HOLD": "Bác nín thở một chút nhé...",
    "BREATH_EXHALE": "Bác hãy từ từ thở ra cùng cháu nhé...",
    "BREATHING_COMPLETED": "Chúc mừng Bác đã hoàn thành bài tập nhịp thở hoa sen. Chúc Bác có một ngày thật nhiều sức khỏe và an vui ạ.",

    # ── 5. Lịch sử, Cài đặt & Khẩn cấp (History, Settings & SOS) ──
    "HISTORY": (
        "Đây là nơi lưu giữ tất cả các bản hồi ký giọng nói của Bác. Bác có thể mở lại để nghe hoặc xem phụ đề bất cứ lúc nào ạ."
    ),
    "SETTINGS": (
        "Đây là trang Cài đặt và Hỗ trợ tiếp cận. Bác có thể đổi tên hiển thị, điều chỉnh cỡ chữ lớn hơn, "
        "bật tính năng chống chạm nhầm, kích hoạt điều khiển bằng giọng nói toàn hệ thống, và lựa chọn giọng đọc ấm áp của cháu Aoede hoặc Charon ạ."
    ),
    "SOS_TRIGGERED": "Hệ thống khẩn cấp đã được kích hoạt. Đang liên hệ với người thân của Bác ngay lập tức.",
    "SOS_NO_CONTACTS": "Bác ơi, danh bạ khẩn cấp chưa có số người thân. Mời Bác thêm số điện thoại người thân để cháu hỗ trợ Bác kịp thời khi cần thiết nhé ạ.",
    "CONTACT_SAVED": "Đã lưu số điện thoại người thân vào danh bạ khẩn cấp thành công rồi ạ.",

    # ── 6. Phản hồi Điều hướng Tức thì (Voice Navigation Shortcuts) ──
    "NAV_HOME": "Dạ cháu đang đưa Bác về Trang chủ đây ạ.",
    "NAV_VOICE_MEMO": "Dạ cháu đang mở Hồi ký Giọng nói cho Bác đây ạ.",
    "NAV_RADIO": "Dạ cháu đang mở Đài Radio Hoài Niệm cho Bác đây ạ.",
    "NAV_BREATHING": "Dạ cháu đang mở bài tập Nhịp thở Hoa Sen cho Bác đây ạ.",
    "NAV_SETTINGS": "Dạ cháu đang mở phần Cài đặt cho Bác đây ạ.",
    "NAV_HISTORY": "Dạ cháu đang mở Lịch sử Hồi ký cho Bác đây ạ.",
}

def _audio_extension(audio: bytes) -> str:
    """Validate the container, never fake success / Chỉ chấp nhận âm thanh hợp lệ."""
    if audio.startswith(b"RIFF"):
        try:
            with wave.open(io.BytesIO(audio), "rb") as recording:
                if recording.getnframes() > 0 and recording.getnchannels() == 1 and recording.getsampwidth() == 2:
                    return ".wav"
        except (wave.Error, EOFError):
            pass
    offset = 0
    if audio.startswith(b"ID3") and len(audio) >= 10:
        size = audio[6:10]
        if any(byte & 0x80 for byte in size):
            raise RuntimeError("Dạ âm thanh phản hồi chưa sẵn sàng.")
        offset = 10 + sum((byte & 0x7f) << (21 - 7 * i) for i, byte in enumerate(size))
    # An ID3 tag alone is not an MP3 / Chỉ có thẻ ID3 chưa phải âm thanh.
    for index in range(offset, min(len(audio) - 3, offset + 4096)):
        header = audio[index:index + 4]
        if header[0] == 0xff and header[1] & 0xe0 == 0xe0 and header[1] & 0x06 and header[2] & 0xf0 not in (0, 0xf0) and header[2] & 0x0c != 0x0c:
            return ".mp3"
    raise RuntimeError("Dạ âm thanh phản hồi chưa sẵn sàng.")


def _get_cache_path(text: str, voice: str) -> str:
    os.makedirs(CACHE_DIR, exist_ok=True)
    key = hashlib.sha256(f"{text}_{voice}".encode("utf-8")).hexdigest()
    return os.path.join(CACHE_DIR, f"tts_{key}.mp3")


def _remember(key: str, audio: bytes):
    while _memory_cache and sum(len(value) for value in _memory_cache.values()) + len(audio) > MAX_CACHE_BYTES:
        _memory_cache.pop(next(iter(_memory_cache)))
    if len(audio) <= MAX_CACHE_BYTES:
        _memory_cache[key] = audio


def _write_audio(audio: bytes, requested_path: str) -> str:
    extension = _audio_extension(audio)
    final_path = os.path.splitext(requested_path)[0] + extension
    os.makedirs(os.path.dirname(final_path) or ".", exist_ok=True)
    with open(final_path, "wb") as output:
        output.write(audio)
    return final_path


async def _synthesize(phonetic_text: str, voice: str) -> bytes:
    api_key = os.getenv("GEMINI_API_KEY")
    if api_key:
        client = genai.Client(api_key=api_key, http_options=types.HttpOptions(
            timeout=12000, retry_options=types.HttpRetryOptions(attempts=1)))
        try:
            response = await asyncio.wait_for(client.aio.models.generate_content(
                model=TTS_MODEL,
                contents=f"Hãy đọc nguyên văn, chậm rãi, ấm áp bằng tiếng Việt: {phonetic_text}",
                config=types.GenerateContentConfig(
                    response_modalities=["AUDIO"],
                    speech_config=types.SpeechConfig(voice_config=types.VoiceConfig(
                        prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name=voice)
                    )),
                ),
            ), timeout=12)
            chunks, mime = [], None
            for candidate in response.candidates or []:
                for part in candidate.content.parts or []:
                    if part.inline_data and part.inline_data.data:
                        current_mime = part.inline_data.mime_type or ""
                        if mime is not None and current_mime != mime:
                            raise RuntimeError("Mixed audio formats")
                        mime = current_mime
                        chunks.append(part.inline_data.data)
            audio = b"".join(chunks)
            if mime and (mime.startswith("audio/pcm") or mime.startswith("audio/L16")):
                if not audio or len(audio) % 2:
                    raise RuntimeError("Invalid PCM")
                rate_match = re.search(r"rate=(\d+)", mime)
                rate = int(rate_match.group(1)) if rate_match else 24000
                if not 8000 <= rate <= 48000:
                    raise RuntimeError("Invalid sample rate")
                with io.BytesIO() as buffer:
                    with wave.open(buffer, "wb") as recording:
                        recording.setnchannels(1)
                        recording.setsampwidth(2)
                        recording.setframerate(rate)
                        recording.writeframes(audio)
                    audio = buffer.getvalue()
            _audio_extension(audio)
            return audio
        except Exception as exc:
            logger.warning("Native TTS unavailable (%s, code=%s); using Vietnamese fallback",
                           type(exc).__name__, getattr(exc, "code", None))
        finally:
            await client.aio.aclose()
    import edge_tts
    engine_voice = "vi-VN-HoaiMyNeural" if voice == "Aoede" else "vi-VN-NamMinhNeural"
    communicate = edge_tts.Communicate(phonetic_text, engine_voice)
    chunks = []
    async def collect():
        async for chunk in communicate.stream():
            if chunk["type"] == "audio":
                chunks.append(chunk["data"])
    try:
        await asyncio.wait_for(collect(), timeout=12)
    except Exception as error:
        # Never log the provider URL or token / Không ghi URL chứa token vào log.
        logger.warning("Vietnamese TTS unavailable (%s, status=%s)",
                       type(error).__name__, getattr(error, "status", None))
        raise RuntimeError("Dạ giọng đọc chưa sẵn sàng.") from None
    audio = b"".join(chunks)
    _audio_extension(audio)
    return audio


async def generate_private_speech(text: str, voice: str = "aoede") -> tuple[bytes, str]:
    """No file/cache for conversations / Hội thoại chỉ xử lý trong RAM."""
    if not isinstance(text, str) or not text.strip() or len(text) > 2000:
        raise ValueError("Nội dung giọng đọc chưa hợp lệ.")
    if voice not in ("aoede", "charon"):
        raise ValueError("Giọng đọc chưa hợp lệ.")
    audio = await asyncio.wait_for(
        _synthesize(sanitize_tts_text(text.strip()), VOICE_MAP[voice]), timeout=7)
    extension = _audio_extension(audio)
    return audio, "audio/wav" if extension == ".wav" else "audio/mpeg"


async def generate_speech(text: str, output_path: Optional[str] = None,
                          voice: Optional[str] = None, cache: bool = True) -> str:
    """Return real audio with matching extension / Trả âm thanh thật và đúng định dạng."""
    clean = text.strip() if isinstance(text, str) and text.strip() else "Dạ cháu lắng nghe Bác đây ạ."
    if len(clean) > 8000:
        raise ValueError("Nội dung giọng đọc quá dài.")
    selected = VOICE_MAP.get(voice.lower(), DEFAULT_VOICE) if isinstance(voice, str) else DEFAULT_VOICE
    phonetic = sanitize_tts_text(clean)
    key = hashlib.md5(f"{phonetic}_{selected}".encode("utf-8")).hexdigest()
    output_path = output_path or f"static/audio_{uuid.uuid4().hex}.mp3"
    # Private conversation audio never enters persistent cache / Hội thoại không vào cache lâu dài.
    if not cache:
        return _write_audio(await _synthesize(phonetic, selected), output_path)
    lock = _synthesis_locks.setdefault(key, asyncio.Lock())
    try:
        async with lock:
            audio = _memory_cache.get(key)
            if audio:
                try:
                    return _write_audio(audio, output_path)
                except RuntimeError:
                    _memory_cache.pop(key, None)
            cache_path = _get_cache_path(phonetic, selected)
            for extension in (".wav", ".mp3"):
                candidate = os.path.splitext(cache_path)[0] + extension
                if os.path.exists(candidate):
                    with open(candidate, "rb") as source:
                        audio = source.read()
                    try:
                        _audio_extension(audio)
                    except RuntimeError:
                        continue
                    _remember(key, audio)
                    return _write_audio(audio, output_path)
            audio = await _synthesize(phonetic, selected)
            _write_audio(audio, cache_path)
            _remember(key, audio)
            return _write_audio(audio, output_path)
    finally:
        if not lock.locked() and not getattr(lock, "_waiters", None):
            _synthesis_locks.pop(key, None)


async def warmup_common_prompts():
    """Load cached guides without competing with memoirs for provider quota.
    Chỉ nạp hướng dẫn có sẵn, không tranh hạn mức API với lời kể của Bác.
    """
    for script in MASTER_VOICE_SCRIPTS.values():
        for shortcut in ("aoede", "charon"):
            try:
                cache_path = _get_cache_path(sanitize_tts_text(script), VOICE_MAP[shortcut])
                for extension in (".wav", ".mp3"):
                    candidate = os.path.splitext(cache_path)[0] + extension
                    if not os.path.exists(candidate):
                        continue
                    with open(candidate, "rb") as source:
                        audio = source.read()
                    _audio_extension(audio)
                    phonetic = sanitize_tts_text(script)
                    key = hashlib.md5(f"{phonetic}_{VOICE_MAP[shortcut]}".encode("utf-8")).hexdigest()
                    _remember(key, audio)
                    break
            except Exception as exc:
                logger.debug("Guide warmup skipped (%s)", type(exc).__name__)
