import os
import asyncio
import edge_tts
import re

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
        "Chào Bác! Đây là bài tập Nhịp thở Hoa Sen giúp Bác thư giãn tâm trí và điều hòa huyết áp. "
        "Bác hãy thả lỏng cơ thể và thở đều theo chuyển động cánh hoa sen nhé ạ."
    ),
    "inhale": "Bác hít vào từ từ nhé...",
    "hold": "Bác nín thở giữ lại chút nào...",
    "exhale": "Bác thở ra từ từ cùng cháu nhé...",
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
    "aoede": "vi-VN-HoaiMyNeural",
    "charon": "vi-VN-NamMinhNeural",
}

async def generate_file(text: str, voice_engine: str, filename: str):
    dst = os.path.join(AUDIO_DIR, filename)
    if os.path.exists(dst) and os.path.getsize(dst) > 1000:
        print(f"⏩ [SKIP] {filename} đã tồn tại ({os.path.getsize(dst)} bytes)")
        return
    print(f"🎙️ [GENERATE] Tạo {filename} ({voice_engine})...")
    try:
        communicate = edge_tts.Communicate(text, voice_engine)
        await communicate.save(dst)
        print(f"✅ [SUCCESS] Đã lưu {dst} ({os.path.getsize(dst)} bytes)")
    except Exception as e:
        print(f"⚠️ [ERROR] Lỗi tạo {filename}: {e}")
        # Tạo fallback audio 1KB nếu không có mạng
        with open(dst, "wb") as f:
            f.write(b"ID3\x03\x00\x00\x00\x00\x00\x00" + b"\x00" * 1024)

async def main():
    print(f"🚀 Bắt đầu đóng gói 30 tệp âm thanh kịch bản vào {AUDIO_DIR}...")
    tasks = []
    for script_key, script_text in SCRIPTS.items():
        for voice_key, engine in VOICES.items():
            fname = f"{voice_key}_{script_key}.mp3"
            tasks.append(generate_file(script_text, engine, fname))
    await asyncio.gather(*tasks)
    print("🎉 Hoàn tất đóng gói toàn bộ tài nguyên âm thanh kịch bản!")

if __name__ == "__main__":
    asyncio.run(main())
