import os
import io
import wave
import asyncio
from dotenv import load_dotenv
load_dotenv('backend/.env')
from google import genai
from google.genai import types

AUDIO_DIR = "assets/audio"
os.makedirs(AUDIO_DIR, exist_ok=True)

SCRIPTS = {
    "onboarding": (
        "Kính chào Bác! Chào mừng Bác đến với I-mô-hêu - Vòng tay thấu cảm đồng hành cùng Cựu chiến binh và Thương binh. "
        "Bác có thể chạm vào nút Bắt đầu ngay màu xanh ở dưới, hoặc sử dụng giọng nói để điều khiển toàn bộ ứng dụng cùng cháu nhé ạ."
    ),
    "login": (
        "Kính chào Bác! Bác vui lòng nhập số điện thoại của mình rồi bấm nút Tiếp tục. "
        "Nếu là lần đầu sử dụng, cháu sẽ gửi mã xác thực về máy Bác để tạo tài khoản, "
        "còn nếu Bác đã có tài khoản rồi thì cháu sẽ đón Bác vào ứng dụng ngay nhé ạ."
    ),
    "otp": (
        "Mã xác thực gồm bốn chữ số đã được gửi qua tin nhắn đến số điện thoại của Bác. "
        "Bác vui lòng kiểm tra tin nhắn và điền bốn số đó vào các ô bên dưới nhé ạ."
    ),
    "home": (
        "Dạ cháu chào Bác! Đây là trang chủ I-mô-hêu - Vòng tay thấu cảm. Tại đây, Bác có thể mở Hồi ký giọng nói, "
        "tập Nhịp thở hoa sen, nghe Đài radio, vào Cài đặt hoặc gọi cho Người thân. "
        "Bác cũng có thể bấm giữ nút SOS lớn màu đỏ khi cần trợ giúp, hoặc chỉ cần nói để cháu tự động điều khiển toàn bộ tính năng cho Bác ạ."
    ),
    "chat": (
        "Dạ cháu lắng nghe Bác đây ạ. Bác có thể nhắn tin hoặc bấm giữ nút micro màu xanh để nói chuyện. "
        "Cháu có thể giải đáp tâm sự, đọc thơ, hoặc tự động chuyển màn hình theo yêu cầu của Bác nhé ạ."
    ),
    "radio": (
        "Chào mừng Bác đến với Đài Radio Hoài Niệm. Bác có thể chạm vào danh sách bài phát để nghe, "
        "hoặc nói tên bài hát yêu thích để cháu tự động bật cho Bác nghe nhé ạ."
    ),
    "voicememo": (
        "Đây là góc lưu giữ Hồi ký Giọng nói. Bác chạm vào nút Ghi âm lớn màu xanh để bắt đầu kể lại những kỷ niệm đáng nhớ của đời mình. "
        "Cháu sẽ tự động lưu trữ an toàn cho Bác ạ."
    ),
    "breathing_intro": (
        "Chào Bác! Đây là bài tập Nhịp thở Hoa Sen giúp Bác thư giãn tâm trí và điều hòa huyết áp."
    ),
    "inhale": "Bác hãy hít vào từ từ nhé...",
    "hold": "Bác nín thở một chút nhé...",
    "exhale": "Bác hãy từ từ thở ra cùng cháu nhé...",
    "breathing_completed": "Chúc mừng Bác đã hoàn thành bài tập nhịp thở hoa sen. Chúc Bác có một ngày thật nhiều sức khỏe và an vui ạ.",
    "history": (
        "Đây là nơi lưu giữ tất cả các bản hồi ký giọng nói của Bác. Bác có thể mở lại để nghe hoặc xem phụ đề bất cứ lúc nào ạ."
    ),
    "settings": (
        "Đây là trang Cài đặt và Hỗ trợ tiếp cận. Bác có thể đổi tên hiển thị, điều chỉnh cỡ chữ lớn hơn, "
        "bật tính năng chống chạm nhầm, kích hoạt điều khiển bằng giọng nói toàn hệ thống, và lựa chọn giọng đọc ấm áp của cháu ạ."
    ),
    "sos": "Hệ thống khẩn cấp đã được kích hoạt. Đang liên hệ với người thân của Bác ngay lập tức.",
}

VOICES = {
    "aoede": "Aoede",
    "charon": "Charon",
}

def pcm_to_wav(pcm_bytes: bytes) -> bytes:
    with io.BytesIO() as wav_io:
        with wave.open(wav_io, "wb") as wav_file:
            wav_file.setnchannels(1)
            wav_file.setsampwidth(2)
            wav_file.setframerate(24000)
            wav_file.writeframes(pcm_bytes)
        return wav_io.getvalue()

sem = asyncio.Semaphore(3)

async def synthesize_gemini_voice(client: genai.Client, text: str, voice_name: str, out_filename: str):
    dst_mp3 = os.path.join(AUDIO_DIR, out_filename)
    dst_wav = os.path.join(AUDIO_DIR, out_filename.replace('.mp3', '.wav'))
    
    if os.path.exists(dst_wav) and os.path.getsize(dst_wav) > 10000:
        print(f"⏩ [SKIP] {out_filename} đã có sẵn ({os.path.getsize(dst_wav)} bytes)", flush=True)
        return True

    async with sem:
        print(f"🎙️ [GEMINI NATIVE LIVE] Đang sinh giọng Google Gemini [{voice_name}]: {out_filename}...", flush=True)
        config = types.LiveConnectConfig(
            response_modalities=[types.Modality.AUDIO],
            system_instruction=types.Content(
                parts=[types.Part(text="Bạn là trợ lý đọc văn bản tiếng Việt cho người cao tuổi. Hãy đọc chính xác từng từ trong câu được yêu cầu bằng chất giọng tiếng Việt ấm áp, chậm rãi, tự nhiên, rõ ràng. Không thêm bớt lời.")]
            ),
            speech_config=types.SpeechConfig(
                voice_config=types.VoiceConfig(
                    prebuilt_voice_config=types.PrebuiltVoiceConfig(
                        voice_name=voice_name
                    )
                )
            )
        )
        
        model = os.getenv("GEMINI_LIVE_MODEL", "gemini-3.1-flash-live-preview")
        for attempt in range(3):
            try:
                async with client.aio.live.connect(model=model, config=config) as session:
                    await session.send(input=f"Hãy đọc to rõ ràng bằng tiếng Việt câu sau: {text}", end_of_turn=True)
                    audio_chunks = []
                    async for resp in session.receive():
                        if resp.server_content and resp.server_content.model_turn:
                            for part in resp.server_content.model_turn.parts:
                                if part.inline_data and part.inline_data.data:
                                    audio_chunks.append(part.inline_data.data)
                        if resp.server_content and resp.server_content.turn_complete:
                            break

                    if audio_chunks:
                        raw_pcm = b"".join(audio_chunks)
                        wav_bytes = pcm_to_wav(raw_pcm)
                        with open(dst_wav, "wb") as f_w:
                            f_w.write(wav_bytes)
                        with open(dst_mp3, "wb") as f_m:
                            f_m.write(wav_bytes)
                        print(f"✅ [SUCCESS] Đã lưu thành công âm thanh thuần Google Gemini {voice_name}: {out_filename} ({len(wav_bytes)} bytes)", flush=True)
                        return True
            except Exception as e:
                print(f"⚠️ [RETRY {attempt+1}] Lỗi sinh giọng Gemini cho {out_filename}: {e}", flush=True)
                await asyncio.sleep(1.5)
        return False

async def main():
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        print("❌ Thiếu GEMINI_API_KEY trong .env", flush=True)
        return
    client = genai.Client(api_key=api_key)
    print("🚀 Bắt đầu sinh 100% Thuần Google Gemini Native Voice (Aoede & Charon) song song 3 workers...", flush=True)
    
    tasks = []
    for script_key, script_text in SCRIPTS.items():
        for voice_key, voice_name in VOICES.items():
            fname = f"{voice_key}_{script_key}.mp3"
            tasks.append(synthesize_gemini_voice(client, script_text, voice_name, fname))
            
    await asyncio.gather(*tasks)
    print("🎉 Hoàn tất sinh 100% file âm thanh thuần Google Gemini Native Voice!", flush=True)

if __name__ == "__main__":
    asyncio.run(main())
