import os
import asyncio
import wave
import io
from dotenv import load_dotenv
load_dotenv('backend/.env')
from google import genai
from google.genai import types

async def test_live():
    client = genai.Client(api_key=os.getenv('GEMINI_API_KEY'))
    print("Connecting to Gemini Live API with voice Aoede...")
    config = types.LiveConnectConfig(
        response_modalities=[types.Modality.AUDIO],
        system_instruction=types.Content(
            parts=[types.Part(text="Bạn là trợ lý đọc văn bản tiếng Việt. Hãy đọc chính xác từng câu được yêu cầu bằng chất giọng tiếng Việt ấm áp, chậm rãi, tự nhiên.")]
        ),
        speech_config=types.SpeechConfig(
            voice_config=types.VoiceConfig(
                prebuilt_voice_config=types.PrebuiltVoiceConfig(
                    voice_name="Aoede"
                )
            )
        )
    )
    model = os.getenv("GEMINI_LIVE_MODEL", "gemini-3.1-flash-live-preview")
    async with client.aio.live.connect(model=model, config=config) as session:
        print("Connected! Sending prompt...")
        await session.send(input="Hãy đọc câu sau: Kính chào Bác! Chào mừng Bác đến với I-mô-hêu - Vòng tay thấu cảm.", end_of_turn=True)
        audio_chunks = []
        async for resp in session.receive():
            if resp.server_content and resp.server_content.model_turn:
                for part in resp.server_content.model_turn.parts:
                    if part.inline_data and part.inline_data.data:
                        audio_chunks.append(part.inline_data.data)
                        print(f"Received audio chunk: {len(part.inline_data.data)} bytes (Mime: {part.inline_data.mime_type})")
            if resp.server_content and resp.server_content.turn_complete:
                print(f"Turn complete! Total chunks: {len(audio_chunks)}")
                break

        if audio_chunks:
            raw_pcm = b"".join(audio_chunks)
            print(f"Total PCM bytes: {len(raw_pcm)}")
            # Chuyển PCM 24kHz 16-bit Mono thành WAV file
            with io.BytesIO() as wav_io:
                with wave.open(wav_io, "wb") as wav_file:
                    wav_file.setnchannels(1)
                    wav_file.setsampwidth(2)
                    wav_file.setframerate(24000)
                    wav_file.writeframes(raw_pcm)
                wav_bytes = wav_io.getvalue()
            
            with open("assets/audio/test_aoede_gemini_native.wav", "wb") as f:
                f.write(wav_bytes)
            print("🎉 Saved test_aoede_gemini_native.wav successfully!")

if __name__ == "__main__":
    asyncio.run(test_live())
