import os
import shutil
import uuid
import glob
import time
from fastapi import FastAPI, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from dotenv import load_dotenv

from services.stt_service import transcribe_audio
from services.ai_service import get_assistant_response
from services.tts_service import generate_speech

load_dotenv()

app = FastAPI(title="LotusHaven API", version="1.0.0")

# CORS — allow Flutter web & mobile clients / Cho phép Flutter kết nối
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

os.makedirs("static", exist_ok=True)
app.mount("/static", StaticFiles(directory="static"), name="static")

# Cleanup TTS files older than 1 hour / Dọn file TTS cũ hơn 1 giờ
def _cleanup_old_tts(max_age_seconds: int = 3600):
    for f in glob.glob("static/resp_*.mp3"):
        try:
            if time.time() - os.path.getmtime(f) > max_age_seconds:
                os.remove(f)
        except OSError:
            pass

@app.get("/api/health")
def health_check():
    return {"status": "ok", "version": "1.0.0"}

@app.post("/api/assistant")
async def assistant(
    audio: UploadFile | None = File(None),
    text: str | None = Form(None),
):
    """
    Accept audio OR text (or both). If audio is provided, transcribe first.
    Chấp nhận audio HOẶC text. Nếu có audio thì chuyển giọng nói thành chữ trước.
    """
    _cleanup_old_tts()

    transcribed_text = ""
    temp_audio_path = None

    try:
        # Step 1: Get text from audio or form / Bước 1: Lấy text từ audio hoặc form
        if audio and audio.filename:
            temp_audio_path = f"temp_{uuid.uuid4().hex}_{audio.filename}"
            with open(temp_audio_path, "wb") as buffer:
                shutil.copyfileobj(audio.file, buffer)
            transcribed_text = transcribe_audio(temp_audio_path)
        elif text:
            transcribed_text = text
        else:
            return {"intent": "error", "text": "Vui lòng gửi tin nhắn hoặc ghi âm.", "audio_url": None}

        # Step 2: AI response / Bước 2: Trả lời AI
        ai_response_text = get_assistant_response(transcribed_text)

        # Step 3: TTS / Bước 3: Chuyển chữ thành giọng nói
        output_audio_path = f"static/resp_{uuid.uuid4().hex}.mp3"
        await generate_speech(ai_response_text, output_audio_path)

        audio_url = f"/{output_audio_path}"

        return {
            "intent": "chat",
            "text": ai_response_text,
            "audio_url": audio_url,
        }
    except Exception as e:
        return {"intent": "error", "text": f"Xin lỗi bác, cháu gặp sự cố: {str(e)}", "audio_url": None}
    finally:
        if temp_audio_path and os.path.exists(temp_audio_path):
            os.remove(temp_audio_path)

@app.post("/api/assistant/text")
async def assistant_text(text: str = Form(...)):
    """Text-only assistant endpoint / Endpoint trợ lý chỉ nhận text"""
    try:
        ai_response_text = get_assistant_response(text)
        output_audio_path = f"static/resp_{uuid.uuid4().hex}.mp3"
        await generate_speech(ai_response_text, output_audio_path)
        return {
            "intent": "chat",
            "text": ai_response_text,
            "audio_url": f"/{output_audio_path}",
        }
    except Exception as e:
        return {"intent": "error", "text": f"Xin lỗi bác, cháu gặp sự cố: {str(e)}", "audio_url": None}
