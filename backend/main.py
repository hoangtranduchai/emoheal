import os
import shutil
import uuid
from fastapi import FastAPI, UploadFile, File
from fastapi.staticfiles import StaticFiles
from dotenv import load_dotenv

from services.stt_service import transcribe_audio
from services.ai_service import get_assistant_response
from services.tts_service import generate_speech

load_dotenv()

app = FastAPI()

os.makedirs("static", exist_ok=True)
app.mount("/static", StaticFiles(directory="static"), name="static")

@app.get("/api/health")
def health_check():
    return {"status": "ok"}

@app.post("/api/assistant")
async def assistant(audio: UploadFile = File(...)):
    temp_audio_path = f"temp_{uuid.uuid4().hex}_{audio.filename}"
    with open(temp_audio_path, "wb") as buffer:
        shutil.copyfileobj(audio.file, buffer)
    
    try:
        # STT
        transcribed_text = transcribe_audio(temp_audio_path)
        
        # AI
        ai_response_text = get_assistant_response(transcribed_text)
        
        # TTS
        output_audio_path = f"static/resp_{uuid.uuid4().hex}.mp3"
        await generate_speech(ai_response_text, output_audio_path)
        
        audio_url = f"/{output_audio_path}"
        
        return {
            "intent": "chat",
            "text": ai_response_text,
            "audio_url": audio_url
        }
    finally:
        if os.path.exists(temp_audio_path):
            os.remove(temp_audio_path)
