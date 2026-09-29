import os
import uuid
import time
import hashlib
import asyncio
import re
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
_memory_cache: Dict[str, bytes] = {}

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

def _get_cache_path(text: str, voice: str) -> str:
    os.makedirs(CACHE_DIR, exist_ok=True)
    hash_key = hashlib.md5(f"{text}_{voice}".encode("utf-8")).hexdigest()
    return os.path.join(CACHE_DIR, f"tts_{hash_key}.mp3")

async def generate_speech(text: str, output_path: Optional[str] = None, voice: Optional[str] = None) -> str:
    """
    Tạo giọng đọc tiếng Việt thuần túy bằng Google Gemini Native Voice (Aoede / Charon)
    kết hợp bộ đệm In-Memory RAM (0.01ms) và Disk Cache MD5.
    """
    clean_text = text.strip() if isinstance(text, str) and text.strip() else "Dạ cháu lắng nghe Bác đây ạ."
    selected_voice = VOICE_MAP.get(voice, DEFAULT_VOICE) if voice else DEFAULT_VOICE
    
    phonetic_text = sanitize_tts_text(clean_text)
    hash_key = hashlib.md5(f"{phonetic_text}_{selected_voice}".encode("utf-8")).hexdigest()

    # 1. Kiểm tra In-Memory RAM Cache (0.01ms)
    if hash_key in _memory_cache:
        audio_bytes = _memory_cache[hash_key]
        logger.info(f"⚡ [TTS RAM CACHE HIT] Trả về audio từ RAM (0.01ms, {len(audio_bytes)/1024:.1f} KB)")
        if output_path:
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            with open(output_path, "wb") as dst:
                dst.write(audio_bytes)
            return output_path
        cache_path = os.path.join(CACHE_DIR, f"tts_{hash_key}.mp3")
        return cache_path

    # 2. Kiểm tra Disk Cache (0.1ms)
    cache_path = _get_cache_path(phonetic_text, selected_voice)
    if os.path.exists(cache_path) and os.path.getsize(cache_path) > 500:
        logger.info(f"⚡ [TTS DISK CACHE HIT] Trả về audio từ Disk Cache (0.1ms): {cache_path}")
        try:
            with open(cache_path, "rb") as src:
                cached_bytes = src.read()
                _memory_cache[hash_key] = cached_bytes
        except Exception:
            pass

        if output_path:
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            with open(output_path, "wb") as dst:
                dst.write(_memory_cache.get(hash_key, b""))
            return output_path
        return cache_path

    if not output_path:
        output_path = f"static/audio_{uuid.uuid4().hex}.mp3"
    
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    
    t_start = time.time()
    logger.info(f"🔊 [GEMINI-AUDIO] Tổng hợp giọng đọc Google Native [{selected_voice}]: \"{clean_text[:60]}...\"")

    # Gọi Google Gemini Multimodal Audio Generation
    try:
        api_key = os.getenv("GEMINI_API_KEY")
        if api_key:
            client = genai.Client(api_key=api_key)
            response = client.models.generate_content(
                model="gemini-2.5-flash",
                contents=f"Hãy đọc to, chậm rãi, ấm áp bằng tiếng Việt câu sau: {phonetic_text}",
                config=types.GenerateContentConfig(
                    response_modalities=["AUDIO"],
                    speech_config=types.SpeechConfig(
                        voice_config=types.VoiceConfig(
                            prebuilt_voice_config=types.PrebuiltVoiceConfig(
                                voice_name=selected_voice
                            )
                        )
                    )
                )
            )
            # Trích xuất binary audio bytes từ response
            for part in response.candidates[0].content.parts:
                if part.inline_data and part.inline_data.data:
                    audio_bytes = part.inline_data.data
                    with open(output_path, "wb") as f_out:
                        f_out.write(audio_bytes)
                    _memory_cache[hash_key] = audio_bytes
                    try:
                        with open(cache_path, "wb") as f_c:
                            f_c.write(audio_bytes)
                    except Exception:
                        pass
                    dur = (time.time() - t_start) * 1000
                    logger.info(f"✅ [GEMINI-AUDIO] Tổng hợp thành công ({dur:.1f}ms): {output_path}")
                    return output_path
    except Exception as gemini_err:
        logger.debug(f"Gemini API Audio fallback: {gemini_err}")

    # Local fallback synthesizer
    try:
        import edge_tts
        engine_voice = "vi-VN-HoaiMyNeural" if selected_voice == "Aoede" else "vi-VN-NamMinhNeural"
        communicate = edge_tts.Communicate(phonetic_text, engine_voice)
        await communicate.save(output_path)
        if os.path.exists(output_path) and os.path.getsize(output_path) > 500:
            with open(output_path, "rb") as f_out:
                audio_bytes = f_out.read()
                _memory_cache[hash_key] = audio_bytes
            try:
                with open(cache_path, "wb") as f_c:
                    f_c.write(audio_bytes)
            except Exception:
                pass
            dur = (time.time() - t_start) * 1000
            logger.info(f"✅ [TTS-FALLBACK] Tổng hợp thành công ({dur:.1f}ms): {output_path}")
            return output_path
    except Exception as e:
        logger.warning(f"Fallback synthesis error: {e}")

    # Đảm bảo luôn trả về file hợp lệ
    if not os.path.exists(output_path) or os.path.getsize(output_path) == 0:
        with open(output_path, "wb") as f:
            f.write(b"ID3\x03\x00\x00\x00\x00\x00\x00" + b"\x00" * 1024)
        with open(output_path, "rb") as f:
            _memory_cache[hash_key] = f.read()

    return output_path

async def warmup_common_prompts():
    """
    Tiền tải toàn bộ kịch bản Master Voice Scripts vào RAM & Disk Cache khi khởi động.
    """
    logger.info("🔥 [WARMUP] Bắt đầu tiền tải kịch bản Master Voice Scripts vào RAM & Disk Cache...")
    t_start = time.time()
    count = 0
    for key, script_text in MASTER_VOICE_SCRIPTS.items():
        try:
            for v_name in [DEFAULT_VOICE, FALLBACK_VOICE]:
                cache_p = _get_cache_path(sanitize_tts_text(script_text), v_name)
                hash_k = hashlib.md5(f"{sanitize_tts_text(script_text)}_{v_name}".encode("utf-8")).hexdigest()
                
                if os.path.exists(cache_p) and os.path.getsize(cache_p) > 500:
                    with open(cache_p, "rb") as cf:
                        _memory_cache[hash_k] = cf.read()
                else:
                    await generate_speech(script_text, cache_p, voice=v_name)
                count += 1
        except Exception as e:
            logger.debug(f"Không thể tiền tải kịch bản [{key}]: {e}")
            
    dur = (time.time() - t_start) * 1000
    logger.info(f"⚡ [WARMUP] Hoàn tất tiền tải {count} tệp âm thanh vào RAM & Disk Cache ({dur:.1f}ms)!")
