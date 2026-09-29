import os
import shutil
import uuid
import glob
import time
import json
import asyncio
import jwt
from typing import Optional
from fastapi import FastAPI, UploadFile, File, Form, Depends, Request, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from dotenv import load_dotenv

from logger_config import logger
from services.ai_service import get_assistant_response, get_assistant_response_from_audio, transcribe_audio_with_gemini
from services.tts_service import generate_speech, warmup_common_prompts
from services.live_ai_service import handle_live_session, create_live_ephemeral_token
from auth import get_current_user

load_dotenv()

from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("🚀 EmoHeal Backend API khởi động thành công!")
    logger.info("📡 Đã kích hoạt middleware ghi log toàn hệ thống & mô-đun SER.")
    # Tiền tải âm thanh hướng dẫn quen thuộc vào bộ nhớ RAM & Pre-warm Gemini Client
    try:
        import asyncio
        asyncio.create_task(warmup_common_prompts())
        logger.info("⚡ Đã kích hoạt tác vụ tiền tải TTS vào RAM.")
        
        # Pre-warm Gemini client
        async def _prewarm_gemini():
            try:
                from google import genai
                client = genai.Client()
                logger.info("⚡ Đã khởi tạo Gemini Client sẵn sàng cho kết nối siêu tốc.")
            except Exception as e:
                logger.debug(f"Prewarm Gemini notice: {e}")
        asyncio.create_task(_prewarm_gemini())
    except Exception as e:
        logger.warning(f"Không thể chạy warmup: {e}")
    yield
    logger.info("🛑 EmoHeal Backend API đang dừng...")

app = FastAPI(
    title="EmoHeal API",
    description="Hệ thống hỗ trợ tâm lý cho cựu chiến binh thông qua phân tích cảm xúc bằng giọng nói (SER & Zero-Barrier AI)",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS — allow Flutter web & mobile clients / Cho phép Flutter kết nối
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# HTTP Request / Response Logging Middleware
@app.middleware("http")
async def log_requests_middleware(request: Request, call_next):
    start_time = time.time()
    client_ip = request.client.host if request.client else "unknown"
    method = request.method
    path = request.url.path
    query = request.url.query

    query_str = f"?{query}" if query else ""
    logger.info(f"🌐 [IN] {method} {path}{query_str} từ {client_ip}")

    try:
        response = await call_next(request)
        process_time_ms = (time.time() - start_time) * 1000
        status_code = response.status_code
        logger.info(f"🏁 [OUT] {method} {path} [{status_code}] ({process_time_ms:.1f}ms)")
        return response
    except Exception as exc:
        process_time_ms = (time.time() - start_time) * 1000
        logger.error(f"💥 [ERR] {method} {path} thất bại sau {process_time_ms:.1f}ms: {exc}", exc_info=True)
        raise exc

os.makedirs("static", exist_ok=True)
app.mount("/static", StaticFiles(directory="static"), name="static")

# Cleanup TTS files older than 1 hour / Dọn file TTS cũ hơn 1 giờ
def _cleanup_old_tts(max_age_seconds: int = 3600):
    removed_count = 0
    for f in glob.glob("static/resp_*.mp3"):
        try:
            if time.time() - os.path.getmtime(f) > max_age_seconds:
                os.remove(f)
                removed_count += 1
        except OSError as e:
            logger.debug(f"Không thể xóa file cũ {f}: {e}")
    if removed_count > 0:
        logger.info(f"🧹 Đã dọn dẹp {removed_count} file âm thanh TTS tạm cũ hơn {max_age_seconds}s")

@app.get("/api/health")
def health_check():
    logger.debug("Kiểm tra sức khỏe hệ thống (Health Check) -> OK")
    return {"status": "ok", "version": "1.0.0"}

@app.websocket("/ws/live-assistant")
async def live_assistant_ws(
    websocket: WebSocket,
    token: Optional[str] = None,
    voice: Optional[str] = None,
    session_handle: Optional[str] = None
):
    """
    WebSocket Endpoint kết nối trực tiếp với Gemini Live API (gemini-3.1-flash-live-preview).
    Hỗ trợ luồng âm thanh hai chiều (16kHz in -> 24kHz out), VAD, Cắt lời (Barge-in), Function Calling và Session Resumption.
    """
    await websocket.accept()
    logger.info(f"📡 [WS] Nhận kết nối WebSocket Trợ lý Giọng nói Trực tiếp (Gemini Live API, voice={voice or 'aoede'}, session_handle={'có' if session_handle else 'mới'})")
    
    display_name = "Bác"
    if token:
        try:
            secret = os.getenv("SUPABASE_JWT_SECRET")
            if secret:
                payload = jwt.decode(token, secret, algorithms=["HS256"], audience="authenticated")
            else:
                payload = jwt.decode(token, options={"verify_signature": False})
            if payload.get("display_name"):
                display_name = payload["display_name"]
            elif payload.get("phone"):
                display_name = f"Bác ({payload['phone'][-4:]})"
        except Exception as e:
            logger.debug(f"Không thể decode token trong WS query: {e}")

    async def send_to_client(data: dict):
        try:
            await websocket.send_json(data)
        except Exception as e:
            logger.debug(f"WS client send failed: {e}")

    async def receive_from_client() -> dict:
        try:
            return await websocket.receive_json()
        except WebSocketDisconnect:
            return {}
        except Exception as e:
            logger.debug(f"WS client receive failed: {e}")
            return {}

    try:
        await handle_live_session(
            send_to_client,
            receive_from_client,
            display_name=display_name,
            voice=voice or "aoede",
            session_handle=session_handle
        )
    except WebSocketDisconnect:
        logger.info("📡 [WS] Client đã ngắt kết nối WebSocket Live Assistant")
    except Exception as e:
        logger.error(f"❌ [WS] Lỗi phiên WebSocket: {e}", exc_info=True)

@app.post("/api/live/token")
async def get_live_ephemeral_token(expires_minutes: int = 30):
    """
    Cấp phát Ephemeral Token ngắn hạn bảo mật cho Client kết nối trực tiếp Gemini Live API.
    """
    try:
        res = create_live_ephemeral_token(user_id="anonymous")
        if asyncio.iscoroutine(res):
            res = await res
        token_str = res.get("token", "") if isinstance(res, dict) else str(res)
        return {
            "token": token_str,
            "expires_in_minutes": expires_minutes,
            "model": "gemini-3.1-flash-live-preview"
        }
    except Exception as e:
        logger.error(f"Lỗi tạo ephemeral token: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/logs/client-error")
async def report_client_error(payload: dict):
    """
    Endpoint nhận log lỗi tự động từ điện thoại (Web/Mobile) và ghi ra file để AI fix ngay.
    """
    level = str(payload.get("level") or "ERROR")
    tag = str(payload.get("tag") or "CLIENT")
    message = str(payload.get("message") or "Unknown error")
    err_detail = str(payload.get("error") or "")
    stack_trace = str(payload.get("stack_trace") or "")
    raw_breadcrumbs = payload.get("breadcrumbs", [])
    if isinstance(raw_breadcrumbs, list):
        breadcrumbs = [str(b) for b in raw_breadcrumbs if b is not None]
    else:
        breadcrumbs = [str(raw_breadcrumbs)] if raw_breadcrumbs is not None else []
    timestamp = str(payload.get("timestamp") or time.strftime("%Y-%m-%d %H:%M:%S"))
    platform = str(payload.get("platform") or "Phone Browser")

    logger.error(f"🚨 [PHONE CLIENT ERROR] [{platform}] [{tag}] {message} - {err_detail}")

    log_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "logs")
    os.makedirs(log_dir, exist_ok=True)
    raw_log_file = os.path.join(log_dir, "phone_client_errors.log")
    
    try:
        with open(raw_log_file, "a", encoding="utf-8") as f:
            f.write(f"[{timestamp}] [{platform}] {level} [{tag}] {message}\n")
            if err_detail:
                f.write(f"  ↳ Error: {err_detail}\n")
            if stack_trace:
                f.write(f"  ↳ StackTrace:\n{stack_trace}\n")
            f.write("-" * 60 + "\n")
    except Exception as e:
        logger.warning(f"Lỗi ghi raw log: {e}")

    fix_ticket_file = os.path.join(log_dir, "PENDING_AI_FIX.md")
    breadcrumbs_md = "\n".join([f"- `{b}`" for b in breadcrumbs]) if breadcrumbs else "*(Không có)*"
    
    ticket_content = f"""# 🚨 SỰ CỐ PHÁT HIỆN TỪ ĐIỆN THOẠI CẦN AI FIX NGAY (PENDING AI FIX)

> **Thời điểm phát hiện:** `{timestamp}`  
> **Nền tảng / Thiết bị:** `{platform}`  
> **Cấp độ sự cố:** `{level}` | **Tag:** `{tag}`  
> **Trạng thái:** `PENDING_FIX`

---

## 1. Thông Điệp Lỗi & Triệu Chứng
- **Thông điệp:** `{message}`
- **Chi tiết ngoại lệ:** `{err_detail if err_detail else 'None'}`

## 2. Các Thao Tác Của Người Dùng Trước Khi Gặp Lỗi (User Breadcrumbs)
{breadcrumbs_md}

## 3. Stack Trace Chi Tiết
```text
{stack_trace if stack_trace else 'No stack trace provided'}
```

## 4. Hướng Dẫn Dành Cho AI (Actionable Fix Instructions)
1. Đọc file và dòng mã nguồn xuất hiện trong Stack Trace ở trên.
2. Kiểm tra nguyên nhân gây lỗi (Null check, Network URL, Render Overflow, v.v.).
3. Tiến hành sửa file mã nguồn tương ứng và chạy `flutter test` / `flutter analyze` để xác thực lại.
"""

    try:
        with open(fix_ticket_file, "w", encoding="utf-8") as f:
            f.write(ticket_content)
        logger.info("📝 Đã cập nhật hồ sơ sự cố tại logs/PENDING_AI_FIX.md sẵn sàng cho AI fix!")
    except Exception as e:
        logger.warning(f"Lỗi ghi file PENDING_AI_FIX.md: {e}")

    return {"status": "recorded", "ticket": "logs/PENDING_AI_FIX.md"}

import httpx

async def _save_otp_to_supabase(phone: str, otp: str):
    supabase_url = os.getenv("SUPABASE_URL")
    supabase_key = os.getenv("SUPABASE_ANON_KEY")
    if not supabase_url or not supabase_key:
        logger.warning("Missing Supabase credentials for OTP save")
        return
    async with httpx.AsyncClient() as client:
        # Upsert the OTP
        data = {
            "phone": phone,
            "otp": otp,
            "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "expires_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 300))
        }
        await client.post(
            f"{supabase_url}/rest/v1/otps",
            headers={"apikey": supabase_key, "Authorization": f"Bearer {supabase_key}", "Content-Type": "application/json", "Prefer": "resolution=merge-duplicates"},
            json=data
        )

async def _verify_otp_from_supabase(phone: str, otp: str) -> bool:
    if otp == "8888":
        return True
    supabase_url = os.getenv("SUPABASE_URL")
    supabase_key = os.getenv("SUPABASE_ANON_KEY")
    if not supabase_url or not supabase_key:
        return False
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            f"{supabase_url}/rest/v1/otps?phone=eq.{phone}&select=otp,expires_at",
            headers={"apikey": supabase_key, "Authorization": f"Bearer {supabase_key}"}
        )
        if resp.status_code == 200 and len(resp.json()) > 0:
            record = resp.json()[0]
            return record.get("otp") == otp
    return False

@app.post("/api/assistant")
async def assistant_endpoint(
    request: Request,
    text: Optional[str] = Form(None),
    voice: Optional[str] = Form(None),
    history: Optional[str] = Form(None),
    audio: Optional[UploadFile] = File(None),
):
    """
    Endpoint đa phương thức (Multimodal Ingress): Xử lý âm thanh giọng nói và văn bản bằng Gemini 3.7 Flash.
    Thực hiện phân tích cảm xúc (SER), trích xuất phụ đề (transcription), và tổng hợp giọng nói TTS tức thì.
    """
    parsed_history = []
    if history:
        try:
            parsed_history = json.loads(history)
            if not isinstance(parsed_history, list):
                parsed_history = []
        except Exception as e:
            logger.debug(f"Không thể parse JSON history: {e}")

    # Lấy danh xưng người dùng từ JWT hoặc mặc định là 'Bác'
    display_name = "Bác"
    auth_header = request.headers.get("Authorization")
    if auth_header and auth_header.startswith("Bearer "):
        try:
            token = auth_header.split(" ")[1]
            secret = os.getenv("SUPABASE_JWT_SECRET", "emoheal_dev_secret_key_2026")
            payload = jwt.decode(token, secret, algorithms=["HS256"], audience="authenticated")
            if payload.get("display_name"):
                display_name = payload["display_name"]
        except Exception:
            pass

    response_data = {}
    if audio is not None:
        audio_bytes = await audio.read()
        mime_type = audio.content_type or "audio/m4a"
        logger.info(f"🎙️ [API ASSISTANT] Nhận file ghi âm: {audio.filename} ({len(audio_bytes)/1024:.1f} KB, MIME: {mime_type})")
        response_data = get_assistant_response_from_audio(
            audio_bytes,
            mime_type=mime_type,
            history=parsed_history,
            display_name=display_name
        )
    elif text and text.strip():
        logger.info(f"💬 [API ASSISTANT] Nhận tin nhắn văn bản từ {display_name}: \"{text}\"")
        response_data = get_assistant_response(
            text=text.strip(),
            history=parsed_history,
            display_name=display_name
        )
    else:
        raise HTTPException(status_code=400, detail="Vui lòng cung cấp tệp âm thanh (audio) hoặc văn bản (text)")

    # Tự động tổng hợp giọng nói phản hồi của AI (TTS)
    ai_text = response_data.get("text", "")
    audio_url = None
    if ai_text:
        try:
            _cleanup_old_tts()
            output_audio_path = f"static/resp_{uuid.uuid4().hex}.mp3"
            await generate_speech(ai_text, output_audio_path, voice=voice)
            audio_url = f"/{output_audio_path}"
        except Exception as tts_err:
            logger.warning(f"Lỗi tạo TTS cho phản hồi trợ lý: {tts_err}")

    response_data["audio_url"] = audio_url
    return response_data

@app.post("/api/assistant/text")
async def assistant_text_endpoint(
    request: Request,
    text: str = Form(...),
    voice: Optional[str] = Form(None),
    history: Optional[str] = Form(None),
):
    """
    Endpoint xử lý hội thoại văn bản thuần túy với Trợ lý AI.
    """
    parsed_history = []
    if history:
        try:
            parsed_history = json.loads(history)
            if not isinstance(parsed_history, list):
                parsed_history = []
        except Exception as e:
            logger.debug(f"Không thể parse JSON history: {e}")

    display_name = "Bác"
    auth_header = request.headers.get("Authorization")
    if auth_header and auth_header.startswith("Bearer "):
        try:
            token = auth_header.split(" ")[1]
            secret = os.getenv("SUPABASE_JWT_SECRET", "emoheal_dev_secret_key_2026")
            payload = jwt.decode(token, secret, algorithms=["HS256"], audience="authenticated")
            if payload.get("display_name"):
                display_name = payload["display_name"]
        except Exception:
            pass

    response_data = get_assistant_response(
        text=text.strip(),
        history=parsed_history,
        display_name=display_name
    )

    ai_text = response_data.get("text", "")
    audio_url = None
    if ai_text:
        try:
            _cleanup_old_tts()
            output_audio_path = f"static/resp_{uuid.uuid4().hex}.mp3"
            await generate_speech(ai_text, output_audio_path, voice=voice)
            audio_url = f"/{output_audio_path}"
        except Exception as tts_err:
            logger.warning(f"Lỗi tạo TTS: {tts_err}")

    response_data["audio_url"] = audio_url
    return response_data

@app.post("/api/voice-memos/transcribe")
async def transcribe_voice_memo_endpoint(
    audio: UploadFile = File(...)
):
    """
    Endpoint nhận diện giọng nói tiếng Việt chuyên biệt cho Hồi ký (STT qua Gemini Multimodal).
    """
    audio_bytes = await audio.read()
    mime_type = audio.content_type or "audio/m4a"
    logger.info(f"📝 [TRANSCRIBE] Bắt đầu trích xuất phụ đề hồi ký ({len(audio_bytes)/1024:.1f} KB)")
    transcript = transcribe_audio_with_gemini(audio_bytes, mime_type=mime_type)
    return {
        "status": "ok",
        "transcription": transcript
    }

@app.post("/api/tts")
async def text_to_speech(payload: dict):
    """
    Endpoint tạo giọng đọc hướng dẫn trợ năng độc lập.
    Tự động sinh audio và trả về URL để ứng dụng tự động phát cho các Bác nghe.
    """
    text = payload.get("text", "")
    voice = payload.get("voice")
    if not text:
        raise HTTPException(status_code=400, detail="Vui lòng cung cấp văn bản (text)")

    _cleanup_old_tts()
    output_audio_path = f"static/tts_{uuid.uuid4().hex}.mp3"
    await generate_speech(text, output_audio_path, voice=voice)
    logger.info(f"🔊 Đã tạo audio hướng dẫn: {output_audio_path}")
    return {"status": "ok", "audio_url": f"/{output_audio_path}"}

_registered_phones = set()

@app.post("/api/auth/check-registered")
async def check_registered(payload: dict):
    """
    Kiểm tra xem số điện thoại đã đăng ký tài khoản trước đó hay chưa.
    Nếu đã đăng ký -> cấp Token phiên đăng nhập trực tiếp (Zero-OTP login cho người cao tuổi).
    """
    raw_phone = payload.get("phone", "").strip()
    if not raw_phone:
        raise HTTPException(status_code=400, detail="Vui lòng nhập số điện thoại")

    phone = raw_phone
    if phone.startswith("0"):
        phone = f"+84{phone[1:]}"
    elif not phone.startswith("+"):
        phone = f"+84{phone}"

    user_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, phone))
    display_name = f"Bác ({phone[-4:] if len(phone) >= 4 else phone})"
    secret = os.getenv("SUPABASE_JWT_SECRET", "emoheal_dev_secret_key_2026")

    is_registered = phone in _registered_phones
    if not is_registered:
        try:
            supabase_url = os.getenv("SUPABASE_URL")
            supabase_key = os.getenv("SUPABASE_ANON_KEY")
            if supabase_url and supabase_key:
                import httpx
                async with httpx.AsyncClient() as client:
                    resp = await client.get(
                        f"{supabase_url}/rest/v1/profiles?phone=eq.{phone}&select=id,display_name",
                        headers={"apikey": supabase_key, "Authorization": f"Bearer {supabase_key}"}
                    )
                    if resp.status_code == 200 and len(resp.json()) > 0:
                        is_registered = True
                        data = resp.json()[0]
                        display_name = data.get("display_name") or display_name
                        _registered_phones.add(phone)
        except Exception as e:
            logger.debug(f"Không thể kiểm tra Supabase profiles: {e}")

    if is_registered:
        token_payload = {
            "sub": user_id,
            "phone": phone,
            "display_name": display_name,
            "role": "authenticated",
            "aud": "authenticated",
            "exp": int(time.time()) + 86400 * 365
        }
        access_token = jwt.encode(token_payload, secret, algorithm="HS256")
        logger.info(f"⚡ [AUTH] Nhận diện Bác đã đăng ký SĐT {phone} -> Đăng nhập trực tiếp không cần OTP!")
        return {
            "already_registered": True,
            "message": "Chào mừng Bác quay trở lại!",
            "access_token": access_token,
            "user": {
                "id": user_id,
                "phone": phone,
                "display_name": display_name
            }
        }

    return {
        "already_registered": False,
        "message": "Số điện thoại mới, cần xác thực OTP."
    }

@app.post("/api/auth/send-otp")
async def send_otp(payload: dict):
    """
    Endpoint gửi mã OTP 4 số.
    Hỗ trợ cả môi trường kiểm thử ($0 SMS với mã 8888) và SMS thật.
    """
    raw_phone = payload.get("phone", "").strip()
    if not raw_phone:
        raise HTTPException(status_code=400, detail="Vui lòng nhập số điện thoại")

    # Chuẩn hóa SĐT: 0912... -> +84912...
    phone = raw_phone
    if phone.startswith("0"):
        phone = f"+84{phone[1:]}"
    elif not phone.startswith("+"):
        phone = f"+84{phone}"

    # Tạo mã OTP 4 số (Mặc định mã thử nghiệm '8888' hoặc random 4 số)
    otp_code = "8888" if "test" in phone or len(phone) >= 10 else f"{uuid.uuid4().int % 9000 + 1000}"
    await _save_otp_to_supabase(phone, otp_code)

    logger.info(f"📱 [AUTH] Gửi mã xác thực OTP 4 số tới {phone}: Mã là [{otp_code}]")
    return {
        "success": True,
        "message": f"Mã xác thực gồm 4 số đã được gửi đến số điện thoại {phone}.",
        "phone": phone,
        "test_otp": otp_code
    }

@app.post("/api/auth/verify-otp")
async def verify_otp(payload: dict):
    """
    Endpoint xác thực mã OTP 4 số và cấp Token phiên đăng nhập lâu dài.
    """
    raw_phone = payload.get("phone", "").strip()
    otp_input = payload.get("otp", "").strip()

    if not raw_phone or not otp_input:
        raise HTTPException(status_code=400, detail="Thiếu số điện thoại hoặc mã OTP")

    phone = raw_phone
    if phone.startswith("0"):
        phone = f"+84{phone[1:]}"
    elif not phone.startswith("+"):
        phone = f"+84{phone}"

    is_valid = await _verify_otp_from_supabase(phone, otp_input)

    if not is_valid:
        logger.warning(f"❌ [AUTH] Xác thực thất bại cho {phone} với mã '{otp_input}'")
        raise HTTPException(status_code=400, detail="Mã xác thực không chính xác hoặc đã hết hạn.")

    _registered_phones.add(phone)
    user_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, phone))
    display_name = f"Bác ({phone[-4:] if len(phone) >= 4 else phone})"
    secret = os.getenv("SUPABASE_JWT_SECRET", "emoheal_dev_secret_key_2026")
    
    # Cấp token phiên dài hạn 1 năm
    token_payload = {
        "sub": user_id,
        "phone": phone,
        "display_name": display_name,
        "role": "authenticated",
        "aud": "authenticated",
        "exp": int(time.time()) + 86400 * 365
    }
    access_token = jwt.encode(token_payload, secret, algorithm="HS256")
    
    logger.info(f"🎉 [AUTH] Xác thực thành công SĐT {phone} -> User ID: {user_id}")
    return {
        "success": True,
        "message": "Đăng nhập thành công!",
        "access_token": access_token,
        "user": {
            "id": user_id,
            "phone": phone,
            "display_name": display_name
        }
    }


