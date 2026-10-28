import asyncio
import base64
import io
import json
import time
import wave
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi.testclient import TestClient
from google.genai import types

import main
from services import live_ai_service as live
from services import tts_service as tts
from services.ai_service import get_assistant_response


def response(**values):
    fields = dict(session_resumption_update=None, go_away=None,
                  tool_call_cancellation=None, server_content=None, tool_call=None)
    fields.update(values)
    return SimpleNamespace(**fields)


def content(**values):
    fields = dict(interrupted=False, model_turn=None, input_transcription=None,
                  output_transcription=None, generation_complete=False, turn_complete=False)
    fields.update(values)
    return SimpleNamespace(**fields)


def tool(call_id="command-1", name="control_radio", args=None):
    args = dict(args if args is not None else {"action": "next"})
    if name in live._CONSENT_TOOLS:
        args.setdefault("request_kind", "explicit_request")
    return response(tool_call=SimpleNamespace(function_calls=[SimpleNamespace(
        id=call_id, name=name, args=args
    )]))


class FakeSession:
    def __init__(self):
        self.incoming = asyncio.Queue()
        self.tool_responses = asyncio.Queue()
        self.inputs = []
        self.receive_count = 0

    async def receive(self):
        self.receive_count += 1
        while True:
            event = await self.incoming.get()
            if isinstance(event, Exception):
                raise event
            yield event
            if event.server_content and event.server_content.turn_complete:
                return

    async def send_realtime_input(self, **values):
        self.inputs.append(values)

    async def send_tool_response(self, function_responses):
        await self.tool_responses.put(function_responses)


@pytest.mark.anyio
async def test_bridge_keeps_three_turns_and_all_events():
    session, client, events = FakeSession(), asyncio.Queue(), []
    for index in range(3):
        await session.incoming.put(response(server_content=content(
            model_turn=SimpleNamespace(parts=[SimpleNamespace(inline_data=SimpleNamespace(
                data=b"\x01\x00", mime_type="audio/pcm;rate=24000"))]),
            input_transcription=SimpleNamespace(text=f"Lời Bác {index}"),
            output_transcription=SimpleNamespace(text=f"Cháu đáp {index}"),
            generation_complete=True, turn_complete=True,
        )))
    async def send(event):
        events.append(event)
        if sum(item["type"] == "turn_complete" for item in events) == 3:
            await client.put({"type": "close"})
    await asyncio.wait_for(live._bridge_session(session, client.get, send), 1)
    assert session.receive_count >= 3
    for kind in ("audio_chunk", "transcript_input", "transcript_output", "generation_complete", "turn_complete"):
        assert sum(item["type"] == kind for item in events) == 3


@pytest.mark.anyio
async def test_tools_wait_for_actual_result_and_execute_once():
    session, client, events = FakeSession(), asyncio.Queue(), asyncio.Queue()
    await session.incoming.put(tool())
    await session.incoming.put(tool())
    task = asyncio.create_task(live._bridge_session(session, client.get, events.put))
    try:
        first = await asyncio.wait_for(events.get(), 1)
        assert first["id"] == "command-1"
        await asyncio.sleep(0)
        assert events.empty() and session.tool_responses.empty()
        # Wrong id or name cannot acknowledge another action / Không nhận kết quả sai lệnh.
        await client.put({"type": "tool_result", "id": "other", "name": "control_radio", "result": {"status": "executed", "message": "Đã phát."}})
        await client.put({"type": "tool_result", "id": "command-1", "name": "control_radio", "result": {"status": "failed", "message": "Dạ chưa có bài hát."}})
        acknowledged = await asyncio.wait_for(session.tool_responses.get(), 1)
        assert acknowledged[0].response["status"] == "failed"
        assert acknowledged[0].response["message"] == "Dạ chưa có bài hát."
        await session.incoming.put(tool())
        replay = await asyncio.wait_for(session.tool_responses.get(), 1)
        assert replay[0].response == acknowledged[0].response
        assert events.empty()
        await client.put({"type": "close"})
        await asyncio.wait_for(task, 1)
    finally:
        task.cancel()
        await asyncio.gather(task, return_exceptions=True)


@pytest.mark.anyio
async def test_provider_cancellation_forwards_ids_and_ignores_late_result():
    session, client, events = FakeSession(), asyncio.Queue(), asyncio.Queue()
    await session.incoming.put(tool())
    task = asyncio.create_task(live._bridge_session(session, client.get, events.put))
    try:
        await asyncio.wait_for(events.get(), 1)
        await session.incoming.put(response(tool_call_cancellation=SimpleNamespace(ids=["command-1"])))
        cancellation = await asyncio.wait_for(events.get(), 1)
        assert cancellation == {"type": "tool_call_cancellation", "ids": ["command-1"]}
        await client.put({"type": "tool_result", "id": "command-1", "name": "control_radio", "result": {"status": "executed", "message": "Đã phát."}})
        await asyncio.sleep(0.01)
        assert session.tool_responses.empty()
        await client.put({"type": "close"})
        await asyncio.wait_for(task, 1)
    finally:
        task.cancel()
        await asyncio.gather(task, return_exceptions=True)


@pytest.mark.anyio
async def test_tool_timeout_cancels_client_and_returns_failure(monkeypatch):
    monkeypatch.setattr(live, "TOOL_RESULT_TIMEOUT_SECONDS", 0.01)
    session, client, events = FakeSession(), asyncio.Queue(), asyncio.Queue()
    await session.incoming.put(tool())
    task = asyncio.create_task(live._bridge_session(session, client.get, events.put))
    try:
        await asyncio.wait_for(events.get(), 1)
        cancellation = await asyncio.wait_for(events.get(), 1)
        assert cancellation["ids"] == ["command-1"]
        result = await asyncio.wait_for(session.tool_responses.get(), 1)
        assert result[0].response["status"] == "failed"
        await client.put({"type": "close"})
        await asyncio.wait_for(task, 1)
    finally:
        task.cancel()
        await asyncio.gather(task, return_exceptions=True)


@pytest.mark.anyio
async def test_tool_response_transport_failure_propagates():
    session, client, events = FakeSession(), asyncio.Queue(), asyncio.Queue()
    session.send_tool_response = AsyncMock(side_effect=ConnectionError("closed"))
    await session.incoming.put(tool())
    task = asyncio.create_task(live._bridge_session(session, client.get, events.put))
    await asyncio.wait_for(events.get(), 1)
    await client.put({"type": "tool_result", "id": "command-1", "name": "control_radio", "result": {"status": "executed", "message": "Đã phát."}})
    with pytest.raises(ConnectionError):
        await asyncio.wait_for(task, 1)


@pytest.mark.anyio
@pytest.mark.parametrize("payload", [
    [], {"type": "audio", "data": "!!"},
    {"type": "audio", "data": base64.b64encode(b"odd").decode()},
    {"type": "audio", "data": ""}, {"type": "text", "text": 3},
    {"type": "app_context", "context": []}, {"type": "unknown"},
])
async def test_bridge_rejects_malformed_payload(payload):
    session, client = FakeSession(), asyncio.Queue()
    await client.put(payload)
    with pytest.raises(ValueError):
        await asyncio.wait_for(live._bridge_session(session, client.get, AsyncMock()), 1)


@pytest.mark.anyio
async def test_context_is_sanitized_and_pcm_preserved():
    session, client = FakeSession(), asyncio.Queue()
    await client.put({"type": "app_context", "context": {"route": "/radio", "radio_playing": True, "phone": "private", "transcript": "private"}})
    pcm = b"\x01\x00" * 160
    await client.put({"type": "audio", "data": base64.b64encode(pcm).decode()})
    await client.put({"type": "close"})
    await asyncio.wait_for(live._bridge_session(session, client.get, AsyncMock()), 1)
    # A state update must not become a user turn or interrupt speech.
    assert len(session.inputs) == 1
    assert session.inputs[0]["audio"].data == pcm
    assert session.inputs[0]["audio"].mime_type == "audio/pcm;rate=16000"


def test_live_config_matches_model_and_initial_resumption():
    current = live._live_config("gemini-3.8-live", "charon")
    preview = live._live_config("gemini-3.1-flash-live-preview", "aoede")
    fallback = live._live_config("gemini-2.5-flash-native-audio-preview-12-2025", "aoede")
    assert current.thinking_config is None
    assert current.session_resumption is not None
    assert current.realtime_input_config.automatic_activity_detection.silence_duration_ms == 700
    assert current.realtime_input_config.automatic_activity_detection.start_of_speech_sensitivity == types.StartSensitivity.START_SENSITIVITY_LOW
    assert current.realtime_input_config.automatic_activity_detection.prefix_padding_ms == 200
    assert preview.thinking_config.thinking_level == types.ThinkingLevel.MINIMAL
    assert fallback.thinking_config.thinking_budget == 0
    assert fallback.realtime_input_config == current.realtime_input_config
    assert any(tool.google_search is not None for tool in current.tools)
    assert all(tool.google_search is None for tool in fallback.tools)
    assert fallback.tools == []
    modern_names = {call.name for tool in current.tools for call in tool.function_declarations or []}
    assert modern_names == set(live._TOOLS_BY_NAME)
    assert live.VOICE_INSTRUCTION in fallback.system_instruction.parts[0].text
    assert live.LIVE_SEARCH_RULE not in fallback.system_instruction.parts[0].text
    assert current.speech_config.voice_config.prebuilt_voice_config.voice_name == "Charon"


def test_schema_constrains_commands_and_sos_destinations():
    assert live._validate_tool("trigger_sos_emergency", {"destination": "ambulance"})["destination"] == "ambulance"
    assert "destination" not in live._validate_tool("trigger_sos_emergency", {})
    assert live._validate_tool("cancel_sos_emergency", {}) == {}
    for name, args in (("control_radio", {"action": "delete"}), ("adjust_settings", {"setting_type": "font_size", "font_delta": float("nan")}), ("navigate_to_screen", {"screen": "arbitrary"}), ("control_voice_memo", {"action": "change_topic"})):
        with pytest.raises(ValueError):
            live._validate_tool(name, args)


@pytest.mark.anyio
async def test_model_fallback_only_before_start_and_client_cleanup(monkeypatch):
    monkeypatch.setenv("GEMINI_API_KEY", "unit-test-only")
    monkeypatch.setattr(live, "CANDIDATE_LIVE_MODELS", ["configured", "gemini-3.8-live"])
    attempts, events, client_messages = [], [], asyncio.Queue()
    session = FakeSession()
    class Connection:
        def __init__(self, model):
            self.model = model
        async def __aenter__(self):
            attempts.append(self.model)
            if self.model == "configured":
                raise RuntimeError("404 model not found")
            return session
        async def __aexit__(self, *args):
            return False
    close = AsyncMock()
    client = SimpleNamespace(aio=SimpleNamespace(live=SimpleNamespace(connect=lambda model, config: Connection(model)), aclose=close))
    monkeypatch.setattr(live.genai, "Client", lambda **kwargs: client)
    await client_messages.put({"type": "close"})
    async def send(event):
        events.append(event)
    await live.handle_live_session(client_messages.get, send)
    assert attempts == ["configured", "gemini-3.8-live"]
    assert events == [{"type": "session_started", "model": "gemini-3.8-live", "analysis_mode": "tools"}]
    close.assert_awaited_once()


@pytest.mark.anyio
async def test_resume_uses_the_fallback_model_that_issued_the_handle(monkeypatch):
    monkeypatch.setenv("GEMINI_API_KEY", "unit-test-only")
    model = "gemini-2.5-flash-native-audio-preview-12-2025"
    attempts, incoming, events = [], asyncio.Queue(), []
    session = FakeSession()
    class Connection:
        async def __aenter__(self):
            return session
        async def __aexit__(self, *args):
            return False
    def connect(model, config):
        attempts.append((model, config.session_resumption.handle))
        return Connection()
    monkeypatch.setattr(live.genai, "Client", lambda **kwargs: SimpleNamespace(aio=SimpleNamespace(
        live=SimpleNamespace(connect=connect), aclose=AsyncMock())))
    await incoming.put({"type": "close"})
    await live.handle_live_session(incoming.get, AsyncMock(), session_handle=live._encode_resumption(model, "fallback-handle"))
    assert attempts == [(model, "fallback-handle")]
    # The next handle retains the same model too / Mã mới vẫn giữ mô hình.
    await session.incoming.put(response(session_resumption_update=SimpleNamespace(
        resumable=True, new_handle="next-handle")))
    async def send(event):
        events.append(event)
        await incoming.put({"type": "close"})
    await live._bridge_session(session, incoming.get, send, model=model)
    assert live._decode_resumption(events[0]["handle"]) == (model, "next-handle")


@pytest.mark.parametrize("handle", ["eh1.!", "eh1.W10", live._encode_resumption("unknown-model", "handle"), "eh1." + "a" * 12001])
def test_invalid_model_bound_resumption_is_rejected(handle):
    with pytest.raises(ValueError):
        live._decode_resumption(handle)


@pytest.mark.anyio
async def test_started_session_failure_is_visible_without_replay(monkeypatch):
    monkeypatch.setenv("GEMINI_API_KEY", "unit-test-only")
    monkeypatch.setattr(live, "CANDIDATE_LIVE_MODELS", ["gemini-3.8-live", "gemini-3.1-flash-live-preview"])
    attempts, events, client_messages = [], [], asyncio.Queue()
    session = FakeSession()
    await session.incoming.put(ConnectionError("private payload 1011 connection ended"))
    class Connection:
        async def __aenter__(self):
            return session
        async def __aexit__(self, *args):
            return False
    def connect(model, config):
        attempts.append(model)
        return Connection()
    close = AsyncMock()
    monkeypatch.setattr(live.genai, "Client", lambda **kwargs: SimpleNamespace(aio=SimpleNamespace(live=SimpleNamespace(connect=connect), aclose=close)))
    async def send(event):
        events.append(event)
    await asyncio.wait_for(live.handle_live_session(client_messages.get, send), 1)
    assert attempts == ["gemini-3.8-live"]
    assert events[-1]["type"] == "error" and events[-1]["is_quota"] is False
    assert "private payload" not in events[-1]["message"]
    close.assert_awaited_once()


@pytest.mark.anyio
async def test_ephemeral_token_locks_model_config_and_expiry(monkeypatch):
    monkeypatch.setenv("GEMINI_API_KEY", "unit-test-only")
    create = AsyncMock(return_value=SimpleNamespace(name="auth_tokens/unit"))
    close = AsyncMock()
    client = SimpleNamespace(aio=SimpleNamespace(auth_tokens=SimpleNamespace(create=create), aclose=close))
    monkeypatch.setattr(live.genai, "Client", lambda **kwargs: client)
    result = await live.create_live_ephemeral_token("guest", voice="charon", expires_minutes=5)
    config = create.call_args.kwargs["config"]
    assert config.uses == 1
    assert config.live_connect_constraints.model == live.LIVE_MODEL
    assert config.live_connect_constraints.config.session_resumption is not None
    assert result["expires_in_minutes"] == 5
    assert result["voice"] == "Charon"
    close.assert_awaited_once()


def test_token_failure_is_503_and_expiry_validation(monkeypatch):
    monkeypatch.setattr(main, "create_live_ephemeral_token", AsyncMock(return_value={"error": "secret detail"}))
    client = TestClient(main.app)
    failed = client.post("/api/live/token")
    invalid = client.post("/api/live/token?expires_minutes=100")
    assert failed.status_code == 503
    assert "secret detail" not in failed.text
    assert invalid.status_code == 422


def wav_audio():
    with io.BytesIO() as buffer:
        with wave.open(buffer, "wb") as recording:
            recording.setnchannels(1)
            recording.setsampwidth(2)
            recording.setframerate(24000)
            recording.writeframes(b"\x01\x00" * 100)
        return buffer.getvalue()


@pytest.mark.anyio
async def test_tts_pcm_becomes_valid_wav_and_does_not_block(monkeypatch, tmp_path):
    monkeypatch.setenv("GEMINI_API_KEY", "unit-test-only")
    generate = AsyncMock(return_value=SimpleNamespace(candidates=[SimpleNamespace(content=SimpleNamespace(parts=[SimpleNamespace(inline_data=SimpleNamespace(data=b"\x01\x00" * 100, mime_type="audio/pcm;rate=24000"))]))]))
    close = AsyncMock()
    monkeypatch.setattr(tts.genai, "Client", lambda **kwargs: SimpleNamespace(aio=SimpleNamespace(models=SimpleNamespace(generate_content=generate), aclose=close)))
    result = await tts.generate_speech("Dạ cháu đây ạ.", str(tmp_path / "voice.mp3"), cache=False)
    assert result.endswith(".wav")
    with wave.open(result, "rb") as recording:
        assert recording.getframerate() == 24000
        assert recording.getnframes() == 100
    generate.assert_awaited_once()
    close.assert_awaited_once()
    assert not tts._memory_cache


@pytest.mark.anyio
async def test_tts_never_caches_fake_audio(monkeypatch, tmp_path):
    monkeypatch.setattr(tts, "_synthesize", AsyncMock(return_value=b"ID3\x03\x00\x00\x00\x00\x00\x00" + bytes(1024)))
    with pytest.raises(RuntimeError):
        await tts.generate_speech("Dạ cháu đây ạ.", str(tmp_path / "voice.mp3"))
    assert not tts._memory_cache
    assert not (tmp_path / "voice.mp3").exists()


@pytest.mark.anyio
async def test_tts_fallback_respects_actual_container_of_bundled_audio(monkeypatch, tmp_path):
    # Use the existing bundled audio, not a fake successful payload / Dùng audio có sẵn.
    audio = (Path(__file__).parents[1] / "assets/audio/charon_sos.mp3").read_bytes()
    class EdgeStream:
        async def stream(self):
            yield {"type": "audio", "data": audio}
    monkeypatch.setattr("edge_tts.Communicate", lambda *args: EdgeStream())
    result = await tts.generate_speech("Bác chờ cháu nhé.", str(tmp_path / "edge.mp3"), voice="charon", cache=False)
    assert result.endswith(tts._audio_extension(audio))
    assert Path(result).read_bytes() == audio


@pytest.mark.anyio
async def test_rest_thread_keeps_event_loop_responsive_and_audio_url_correct(monkeypatch):
    ticks = []
    def slow_response(**kwargs):
        time.sleep(0.08)
        return {"intent": "CHAT", "text": "Dạ cháu đây ạ."}
    async def heartbeat():
        await asyncio.sleep(0.01)
        ticks.append("responsive")
    monkeypatch.setattr(main, "get_assistant_response", slow_response)
    monkeypatch.setattr(main, "generate_speech", AsyncMock(return_value="static/actual.wav"))
    result, _ = await asyncio.gather(main.assistant_text_endpoint(SimpleNamespace(headers={}), "Bác chào cháu", None, None), heartbeat())
    assert ticks == ["responsive"]
    assert result["audio_url"] == "/static/actual.wav"
    assert main.generate_speech.call_args.kwargs["cache"] is False


def test_rest_normalizes_untrusted_model_commands_without_transcript_logs(monkeypatch, caplog):
    client = MagicMock()
    client.models.generate_content.return_value.text = json.dumps({"intent": "DELETE", "target": "database", "action": "delete", "emotion_confidence": 5, "text": "Dạ cháu đây ạ."})
    monkeypatch.setattr("services.ai_service._get_client", lambda: client)
    secret_text = "Nội dung riêng tư duy nhất của Bác"
    with caplog.at_level("INFO", logger="emoheal"):
        result = get_assistant_response(secret_text)
    assert result["intent"] == "CHAT"
    assert result["target"] is None and result["action"] is None
    assert result["emotion_confidence"] is None
    assert secret_text not in caplog.text
