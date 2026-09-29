import pytest
import os
import json
import asyncio
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient
from main import app
from services.tts_service import VOICE_MAP, DEFAULT_VOICE, sanitize_tts_text, generate_speech, _memory_cache
from services.ai_service import _build_prompt_with_history, SYSTEM_PROMPT

client = TestClient(app)

def test_read_health():
    """Test health check endpoint."""
    response = client.get("/api/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ok"
    assert data["version"] == "1.0.0"

def test_tts_voice_mapping():
    """Test that voice shortcuts map to valid Google Gemini Native voices."""
    assert VOICE_MAP["aoede"] == "Aoede"
    assert VOICE_MAP["charon"] == "Charon"
    assert VOICE_MAP["female"] == "Aoede"
    assert VOICE_MAP["male"] == "Charon"
    assert DEFAULT_VOICE == "Aoede"

def test_build_prompt_with_history():
    """Test prompt construction with conversation history."""
    history = [
        {"sender": "user", "content": "Chào cháu"},
        {"sender": "assistant", "content": "Dạ cháu chào bác ạ!"}
    ]
    prompt = _build_prompt_with_history("Bác hơi mệt", history=history)
    assert "Bác: Chào cháu" in prompt

@patch("services.ai_service.genai.Client")
def test_ai_response_parsing(mock_client_cls):
    """Test AI JSON response parsing, SER emotion extraction, and intent classification."""
    from services.ai_service import get_assistant_response
    
    mock_instance = MagicMock()
    mock_client_cls.return_value = mock_instance
    mock_response = MagicMock()
    mock_response.text = json.dumps({
        "emotion": "PANIC_STRESS",
        "emotion_confidence": 0.96,
        "intent": "PANIC",
        "text": "Bác ơi, bác ngồi xuống nghỉ ngơi cùng cháu nhé.",
        "target": "breathing"
    })
    mock_instance.models.generate_content.return_value = mock_response

    result = get_assistant_response("Tôi cảm thấy khó thở và mệt quá")
    assert result["emotion"] == "PANIC_STRESS"
    assert result["emotion_confidence"] >= 0.9
    assert result["intent"] == "PANIC"
    assert result["target"] == "breathing"
    assert "Bác ơi" in result["text"]

def test_report_client_error():
    """Test /api/logs/client-error endpoint for receiving phone logs."""
    payload = {
        "level": "[ERROR]",
        "tag": "PHONE_TEST",
        "message": "Ngoại lệ thử nghiệm từ điện thoại",
        "error": "NullPointerException: mock null value",
        "stack_trace": "package:emoheal/main.dart 42:15\npackage:flutter/src/widgets/framework.dart",
        "breadcrumbs": ["[22:00:01] [INFO] Mở màn hình Home", "[22:00:05] [EVENT] Chạm nút Radio"],
        "timestamp": "2026-08-24 22:00:10",
        "platform": "Web (Safari Mobile)"
    }
    response = client.post("/api/logs/client-error", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "recorded"
    assert "PENDING_AI_FIX.md" in data["ticket"]

@patch("services.ai_service.genai.Client")
def test_ai_response_markdown_json_fence(mock_client_cls):
    """Test parser correctly strips ```json ... ``` markdown code fences."""
    from services.ai_service import get_assistant_response
    
    mock_instance = MagicMock()
    mock_client_cls.return_value = mock_instance
    mock_response = MagicMock()
    mock_response.text = '```json\n{"emotion": "NOSTALGIA", "emotion_confidence": 0.88, "intent": "NAVIGATE", "text": "Dạ cháu mở đài radio cho bác nghe ngay đây ạ.", "target": "radio"}\n```'
    mock_instance.models.generate_content.return_value = mock_response

    result = get_assistant_response("Mở đài cho tôi nghe")
    assert result["emotion"] == "NOSTALGIA"
    assert result["intent"] == "NAVIGATE"
    assert result["target"] == "radio"

@patch("services.ai_service.genai.Client")
def test_ai_response_malformed_fallback(mock_client_cls):
    """Test AI fallback when LLM returns non-JSON or invalid types."""
    from services.ai_service import get_assistant_response
    
    mock_instance = MagicMock()
    mock_client_cls.return_value = mock_instance
    mock_response = MagicMock()
    mock_response.text = 'Tôi là phản hồi plain text không có JSON'
    mock_instance.models.generate_content.return_value = mock_response

    result = get_assistant_response("Chào cháu")
    assert result["intent"] == "CHAT"
    assert result["text"] == "Tôi là phản hồi plain text không có JSON"
    assert result["target"] is None

def test_report_client_error_malformed_payload():
    """Test /api/logs/client-error endpoint with malformed/empty payload."""
    from unittest.mock import mock_open
    with patch("builtins.open", mock_open()):
        response = client.post("/api/logs/client-error", json={"breadcrumbs": 12345, "error": None})
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "recorded"

def test_tts_service_empty_text_sanitization():
    """Test TTS service when given empty or whitespace text."""
    async def fake_save(dst):
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "wb") as f:
            f.write(b"a" * 1024)

    path = asyncio.run(generate_speech("", output_path="static/test_empty.mp3"))
    assert path == "static/test_empty.mp3"

def test_build_prompt_with_malformed_history():
    """Test prompt construction with non-list or invalid history objects."""
    prompt1 = _build_prompt_with_history("Xin chào", history={"invalid": "object"})
    assert "Bác nói: Xin chào" in prompt1

    prompt2 = _build_prompt_with_history("Xin chào", history=["string1", 123, None])
    assert "Bác nói: Xin chào" in prompt2

    prompt3 = _build_prompt_with_history("Tôi khỏe", history=[{"is_user": True, "content": "Khỏe không cháu"}])
    assert "Bác: Khỏe không cháu" in prompt3

def test_text_to_speech_endpoint():
    """Test /api/tts endpoint with Gemini Native Voice."""
    with patch("main.generate_speech") as mock_tts:
        mock_tts.return_value = "static/tts_mock.mp3"
        response = client.post("/api/tts", json={"text": "Kính chào bác ạ", "voice": "aoede"})
        assert response.status_code == 200
        assert "audio_url" in response.json()

def test_auth_send_and_verify_otp():
    """Test 4-digit Phone Auth send-otp and verify-otp flow."""
    send_res = client.post("/api/auth/send-otp", json={"phone": "0912345678"})
    assert send_res.status_code == 200
    send_data = send_res.json()
    assert send_data["success"] is True
    assert send_data["test_otp"] == "8888"

    verify_res = client.post("/api/auth/verify-otp", json={"phone": "0912345678", "otp": "8888"})
    assert verify_res.status_code == 200
    verify_data = verify_res.json()
    assert verify_data["success"] is True
    assert "access_token" in verify_data
    assert verify_data["user"]["phone"] == "+84912345678"

    wrong_res = client.post("/api/auth/verify-otp", json={"phone": "0912345678", "otp": "0000"})
    assert wrong_res.status_code == 400

@patch("services.ai_service.genai.Client")
def test_gemini_multimodal_audio_response(mock_client_cls):
    """Test get_assistant_response_from_audio with mocked Gemini SER."""
    from services.ai_service import get_assistant_response_from_audio
    mock_instance = MagicMock()
    mock_client_cls.return_value = mock_instance
    mock_response = MagicMock()
    mock_response.text = json.dumps({
        "transcription": "Bác muốn mở đài radio",
        "emotion": "NOSTALGIA",
        "emotion_confidence": 0.92,
        "intent": "NAVIGATE",
        "text": "Dạ cháu mở đài radio ngay cho bác đây ạ.",
        "target": "radio"
    })
    mock_instance.models.generate_content.return_value = mock_response

    fake_audio_bytes = b"RIFF....WAVEfmt ...."
    result = get_assistant_response_from_audio(fake_audio_bytes, mime_type="audio/wav")
    assert result["transcription"] == "Bác muốn mở đài radio"
    assert result["emotion"] == "NOSTALGIA"
    assert result["emotion_confidence"] >= 0.9
    assert result["intent"] == "NAVIGATE"
    assert result["target"] == "radio"
    assert "radio" in result["text"]

@patch("services.ai_service.genai.Client")
def test_transcribe_audio_with_gemini(mock_client_cls):
    """Test standalone transcribe_audio_with_gemini helper."""
    from services.ai_service import transcribe_audio_with_gemini
    mock_instance = MagicMock()
    mock_client_cls.return_value = mock_instance
    mock_response = MagicMock()
    mock_response.text = "Kính chào các đồng chí và bà con"
    mock_instance.models.generate_content.return_value = mock_response

    res_text = transcribe_audio_with_gemini(b"audio-bytes-data", mime_type="audio/mp3")
    assert res_text == "Kính chào các đồng chí và bà con"

@patch("services.ai_service.genai.Client")
def test_ser_six_emotion_classes(mock_client_cls):
    """Test all 6 emotion classes correctly parsed in SER engine."""
    from services.ai_service import get_assistant_response
    
    mock_instance = MagicMock()
    mock_client_cls.return_value = mock_instance
    
    emotions = ["PANIC_STRESS", "SADNESS", "NOSTALGIA", "CALM", "HAPPINESS", "NEUTRAL"]
    for emo in emotions:
        mock_response = MagicMock()
        mock_response.text = json.dumps({
            "emotion": emo,
            "emotion_confidence": 0.94,
            "intent": "PANIC" if emo == "PANIC_STRESS" else "CHAT",
            "text": f"Dạ cháu hiểu cảm xúc của Bác ({emo}) ạ.",
            "target": "breathing" if emo == "PANIC_STRESS" else None
        })
        mock_instance.models.generate_content.return_value = mock_response
        res = get_assistant_response("Thử nghiệm cảm xúc")
        assert res["emotion"] == emo
        assert res["emotion_confidence"] == 0.94

@pytest.mark.anyio
async def test_tts_ram_memory_cache():
    """Test 2-tier in-memory RAM cache produces instantaneous cache hit."""
    import hashlib
    test_text = "Thử nghiệm bộ đệm RAM siêu tốc EmoHeal"
    phonetic = sanitize_tts_text(test_text)
    hash_key = hashlib.md5(f"{phonetic}_Aoede".encode("utf-8")).hexdigest()
    _memory_cache[hash_key] = b"fake-audio-bytes-in-ram"
    
    out_file = "static/test_ram_cache.mp3"
    result = await generate_speech(test_text, output_path=out_file, voice="aoede")
    assert result == out_file
    with open(out_file, "rb") as f:
        assert f.read() == b"fake-audio-bytes-in-ram"

@patch("main.handle_live_session")
def test_live_assistant_ws_endpoint(mock_handle_live):
    """Test /ws/live-assistant WebSocket endpoint connection and handshake."""
    async def fake_handle(send_fn, recv_fn, display_name="Bác", voice="aoede", session_handle=None):
        await send_fn({"type": "session_started", "model": "gemini-3.1-flash-live-preview"})
    
    mock_handle_live.side_effect = fake_handle
    with client.websocket_connect("/ws/live-assistant?voice=charon") as ws:
        data = ws.receive_json()
        assert data["type"] == "session_started"
        assert data["model"] == "gemini-3.1-flash-live-preview"

@patch("main.create_live_ephemeral_token")
def test_get_live_ephemeral_token_endpoint(mock_create_token):
    """Test POST /api/live/token returns short-lived ephemeral token."""
    mock_create_token.return_value = "auth_tokens/test-ephemeral-token-12345"
    response = client.post("/api/live/token?expires_minutes=30")
    assert response.status_code == 200
    data = response.json()
    assert data["token"] == "auth_tokens/test-ephemeral-token-12345"
    assert data["expires_in_minutes"] == 30
    assert data["model"] == "gemini-3.1-flash-live-preview"

@patch("main.handle_live_session")
def test_live_assistant_ws_session_resumption(mock_handle_live):
    """Test WebSocket accepts session_handle for resuming conversations."""
    resumed = []
    async def fake_handle(send_fn, recv_fn, display_name="Bác", voice="aoede", session_handle=None):
        resumed.append(session_handle)
        await send_fn({"type": "session_started", "model": "gemini-3.1-flash-live-preview", "resumed": True})
    
    mock_handle_live.side_effect = fake_handle
    with client.websocket_connect("/ws/live-assistant?session_handle=test_resumption_token_abc") as ws:
        data = ws.receive_json()
        assert data["resumed"] is True
    assert resumed == ["test_resumption_token_abc"]

def test_sanitize_tts_text_emoheal_pronunciation():
    """Test that 'EmoHeal' is always phonetically converted to English pronunciation 'I-mô-hêu'."""
    raw = "Chào mừng Bác đến với EmoHeal - Vòng tay thấu cảm. emoheal luôn đồng hành cùng Bác."
    sanitized = sanitize_tts_text(raw)
    assert "I-mô-hêu" in sanitized
    assert "EmoHeal" not in sanitized
    assert "emoheal" not in sanitized

def test_check_registered_auth_flow():
    """Test /api/auth/check-registered and /api/auth/verify-otp registration lifecycle."""
    test_phone = "0987654321"
    
    # 1. Ban đầu chưa đăng ký
    res1 = client.post("/api/auth/check-registered", json={"phone": test_phone})
    assert res1.status_code == 200
    assert res1.json()["already_registered"] is False

    # 2. Đăng ký thành công bằng mã OTP
    res_otp = client.post("/api/auth/verify-otp", json={"phone": test_phone, "otp": "8888"})
    assert res_otp.status_code == 200
    assert "access_token" in res_otp.json()

    # 3. Lần đăng nhập tiếp theo -> Đăng nhập trực tiếp không cần OTP
    res2 = client.post("/api/auth/check-registered", json={"phone": test_phone})
    assert res2.status_code == 200
    data2 = res2.json()
    assert data2["already_registered"] is True
    assert "access_token" in data2
    assert "user" in data2

@patch("main.get_assistant_response")
@patch("main.generate_speech")
def test_assistant_endpoint_text(mock_tts, mock_ai):
    """Test POST /api/assistant with text payload."""
    mock_ai.return_value = {
        "emotion": "NOSTALGIA",
        "emotion_confidence": 0.95,
        "intent": "CHAT",
        "text": "Dạ cháu lắng nghe câu chuyện của Bác ạ.",
        "target": "voice-memo"
    }
    mock_tts.return_value = "static/resp_test.mp3"

    res = client.post("/api/assistant", data={"text": "Kỷ niệm chiến trường"})
    assert res.status_code == 200
    data = res.json()
    assert data["emotion"] == "NOSTALGIA"
    assert "Dạ cháu" in data["text"]
    assert "audio_url" in data

@patch("main.get_assistant_response_from_audio")
@patch("main.generate_speech")
def test_assistant_endpoint_audio(mock_tts, mock_ai):
    """Test POST /api/assistant with audio file upload."""
    mock_ai.return_value = {
        "transcription": "Ngày hòa bình tôi ở chiến khu",
        "emotion": "NOSTALGIA",
        "emotion_confidence": 0.96,
        "intent": "CHAT",
        "text": "Dạ cháu xúc động quá ạ.",
        "target": "voice-memo"
    }
    mock_tts.return_value = "static/resp_test_audio.mp3"

    fake_file = ("memo.m4a", b"audio-binary-data", "audio/m4a")
    res = client.post("/api/assistant", files={"audio": fake_file})
    assert res.status_code == 200
    data = res.json()
    assert data["transcription"] == "Ngày hòa bình tôi ở chiến khu"
    assert data["emotion"] == "NOSTALGIA"
    assert "audio_url" in data

@patch("main.transcribe_audio_with_gemini")
def test_voice_memo_transcribe_endpoint(mock_transcribe):
    """Test POST /api/voice-memos/transcribe endpoint."""
    mock_transcribe.return_value = "Đoạn trích hồi ký ngày 30 tháng 4"

    fake_file = ("memo.m4a", b"audio-binary-data", "audio/m4a")
    res = client.post("/api/voice-memos/transcribe", files={"audio": fake_file})
    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "ok"
    assert data["transcription"] == "Đoạn trích hồi ký ngày 30 tháng 4"

