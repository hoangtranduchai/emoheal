import edge_tts
import os
import uuid

VOICE = "vi-VN-HoaiMyNeural"

async def generate_speech(text: str, output_path: str = None) -> str:
    if not output_path:
        output_path = f"static/audio_{uuid.uuid4().hex}.mp3"
    
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    
    communicate = edge_tts.Communicate(text, VOICE)
    await communicate.save(output_path)
    return output_path
