"""Memoir regression coverage / Hồi quy phụ đề, thời hạn và giọng đọc."""
import asyncio
import io
import json
import threading
import wave
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

import main
from services import ai_service, tts_service

client = TestClient(main.app)


def audio_result():
    return {"transcription": "Bác nhớ đồng đội.", "text": "Cháu lắng nghe Bác ạ.",
            "emotion": "NOSTALGIA", "intent": "CHAT"}


def test_captions_do_not_wait_for_tts(monkeypatch):
    monkeypatch.setattr(main, "get_assistant_response_from_audio", lambda *a, **k: audio_result())
    speech = AsyncMock(side_effect=AssertionError("Captions must not invoke TTS"))
    monkeypatch.setattr(main, "generate_speech", speech)
    response = client.post("/api/assistant", data={"include_audio": "false"},
                           files={"audio": ("memo.wav", b"audio", "audio/wav")})
    assert response.status_code == 200
    assert response.json()["transcription"] == "Bác nhớ đồng đội."
    assert response.json()["audio_url"] is None
    speech.assert_not_awaited()


def test_provider_failure_is_retryable_not_success(monkeypatch):
    def unavailable(*args, **kwargs):
        raise ai_service.AudioProcessingError()
    monkeypatch.setattr(main, "get_assistant_response_from_audio", unavailable)
    response = client.post("/api/assistant", data={"include_audio": "false"},
                           files={"audio": ("memo.wav", b"audio", "audio/wav")})
    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "provider_unavailable"
    assert "transcription" not in response.json()


@pytest.mark.anyio
async def test_slow_model_times_out_while_event_loop_stays_responsive(monkeypatch):
    monkeypatch.setattr(main, "AI_RESPONSE_TIMEOUT", 0.02)
    finished = threading.Event()
    def slow():
        finished.wait(1)
        return audio_result()
    ticks = []
    async def tick():
        await asyncio.sleep(0.005)
        ticks.append(True)
    try:
        with pytest.raises(HTTPException) as failure:
            await asyncio.gather(main._audio_result(slow), tick())
        assert failure.value.status_code == 504
        assert ticks == [True]
    finally:
        finished.set()


def test_model_timeout_falls_back_once_and_preserves_user_role(monkeypatch):
    provider = MagicMock()
    provider.models.generate_content.side_effect = [TimeoutError(),
        SimpleNamespace(text=json.dumps(audio_result(), ensure_ascii=False))]
    monkeypatch.setattr(ai_service, "_get_client", lambda: provider)
    result = ai_service.get_assistant_response_from_audio(b"audio", "audio/wav",
        history=[{"role": "user", "content": "Bác chào cháu"}])
    assert result["transcription"] == "Bác nhớ đồng đội."
    calls = provider.models.generate_content.call_args_list
    assert [call.kwargs["model"] for call in calls] == [ai_service.AUDIO_PRIMARY_MODEL, ai_service.AUDIO_FALLBACK_MODEL]
    assert "Bác: Bác chào cháu" in calls[1].kwargs["contents"][1]
    assert calls[1].kwargs["config"].thinking_config.thinking_level == "LOW"
    assert calls[1].kwargs["config"].temperature is None
    provider.close.assert_called_once()


def test_approved_lite_model_keeps_full_memo_schema(monkeypatch):
    provider = MagicMock()
    provider.models.generate_content.return_value.text = json.dumps(audio_result(), ensure_ascii=False)
    monkeypatch.setattr(ai_service, "_get_client", lambda: provider)
    monkeypatch.setattr(ai_service, "AUDIO_PRIMARY_MODEL", "gemini-3.5-flash-lite")
    result = ai_service.get_assistant_response_from_audio(b"audio", "audio/wav")
    assert result["transcription"] == "Bác nhớ đồng đội."
    config = provider.models.generate_content.call_args.kwargs["config"]
    assert config.thinking_config.thinking_level == "MINIMAL"
    assert config.thinking_config.thinking_budget is None
    assert config.temperature is None
    assert set(config.response_schema["required"]) == {
        *ai_service.RESPONSE_SCHEMA["required"], "transcription"}


@pytest.mark.parametrize("result", ["invalid json", '{}', '{"transcription":42}'])
def test_bad_or_missing_transcript_never_becomes_success(monkeypatch, result):
    provider = MagicMock()
    provider.models.generate_content.return_value.text = result
    monkeypatch.setattr(ai_service, "_get_client", lambda: provider)
    with pytest.raises(ai_service.AudioProcessingError):
        ai_service.get_assistant_response_from_audio(b"audio")


def test_sdk_deadline_and_hidden_retries_are_bounded():
    with patch.object(ai_service.genai, "Client") as create:
        ai_service._get_client()
    options = create.call_args.kwargs["http_options"]
    assert options.timeout == 20000
    assert options.retry_options.attempts == 1


def test_transcription_outage_is_not_an_empty_success(monkeypatch):
    def fail(*args, **kwargs):
        raise ai_service.AudioProcessingError("no_transcription")
    monkeypatch.setattr(main, "transcribe_audio_with_gemini", fail)
    response = client.post("/api/voice-memos/transcribe",
                           files={"audio": ("memo.wav", b"audio", "audio/wav")})
    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "no_transcription"


@pytest.mark.anyio
async def test_startup_warmup_never_calls_provider(monkeypatch):
    synthesis = AsyncMock(side_effect=AssertionError("No startup quota consumption"))
    monkeypatch.setattr(tts_service, "_synthesize", synthesis)
    await tts_service.warmup_common_prompts()
    synthesis.assert_not_awaited()


def test_tts_failure_does_not_expose_provider_tokens(monkeypatch, caplog):
    monkeypatch.setattr(main, "generate_speech", AsyncMock(side_effect=RuntimeError("secret-token")))
    response = client.post("/api/tts", json={"text": "Cháu chào Bác ạ."})
    assert response.status_code == 503
    assert "secret-token" not in response.text
    assert "secret-token" not in caplog.text


@pytest.mark.anyio
@pytest.mark.parametrize("mime,rate", [
    ("audio/l16; rate=24000; channels=1", 24000),
    ("Audio/L16;rate=16000", 16000),
    ("audio/pcm;rate=24000", 24000),
])
async def test_native_tts_accepts_provider_pcm_mime_casing(monkeypatch, mime, rate):
    # Real provider casing must produce a playable WAV / Giữ đúng PCM, không gọi dự phòng.
    pcm = b"\x00\x00\x10\x00" * 40
    response = SimpleNamespace(candidates=[SimpleNamespace(content=SimpleNamespace(parts=[
        SimpleNamespace(inline_data=SimpleNamespace(data=pcm, mime_type=mime))]))])
    provider = SimpleNamespace(aio=SimpleNamespace(
        models=SimpleNamespace(generate_content=AsyncMock(return_value=response)),
        aclose=AsyncMock()))
    monkeypatch.setenv("GEMINI_API_KEY", "synthetic-test-key")
    monkeypatch.setattr(tts_service.genai, "Client", lambda **kwargs: provider)
    monkeypatch.setattr("edge_tts.Communicate", MagicMock(side_effect=AssertionError("Native speech was valid")))
    audio = await tts_service._synthesize("Dạ cháu đang nghe Bác kể.", "Aoede")
    with wave.open(io.BytesIO(audio), "rb") as recording:
        assert recording.getframerate() == rate
        assert recording.getnchannels() == 1
        assert recording.getsampwidth() == 2
        assert recording.readframes(recording.getnframes()) == pcm
    provider.aio.aclose.assert_awaited_once()
