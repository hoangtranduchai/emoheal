import asyncio
import io
import json
import wave
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi.testclient import TestClient
import main
from services import ai_service as ai, tts_service as tts


def wav_bytes():
    with io.BytesIO() as output:
        with wave.open(output, 'wb') as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(24000)
            wav.writeframes(b'\x01\x00' * 100)
        return output.getvalue()


@pytest.mark.parametrize('words', [
    'Tạm biệt cháu nhé', 'Hẹn gặp lại sau', 'Hẹn cháu hôm khác',
    'Kết thúc cuộc trò chuyện', 'Bác đi nghỉ đây', 'Mình nói chuyện sau nhé',
])
def test_current_farewell_ends_without_an_ai_claim(words):
    assert ai._ends_conversation({}, words)


@pytest.mark.parametrize('words', [
    'Không tạm biệt đâu', 'Đừng kết thúc cuộc trò chuyện',
    'Ngày xưa bác hẹn gặp lại đồng đội', 'Nếu nói tạm biệt thì sao',
    'Câu nói tạm biệt nghĩa là gì', 'Chào cháu', 'Tạm dừng Radio',
    'Kết thúc tập thở', 'Nghe bài Tạm biệt', 'Cháu hát Hẹn gặp lại',
    'Bác chưa muốn tạm biệt', 'Cháu kể về lời chào tạm biệt',
])
def test_ai_cannot_close_for_negation_story_greeting_or_app_controls(words):
    assert not ai._ends_conversation({'end_conversation': True}, words)


@pytest.mark.parametrize('audio', [False, True])
def test_farewell_flag_uses_actual_input_not_history_or_ai_reply(monkeypatch, audio):
    provider = MagicMock()
    monkeypatch.setattr(ai, '_get_client', lambda: provider)
    data = {'emotion':'NEUTRAL', 'emotion_context':'current', 'emotion_confidence':.8,
            'safety_signal':'none', 'intent':'CHAT', 'request_kind':'suggestion',
            'text':'Tạm biệt Bác nhé', 'end_conversation':True,
            'transcription':'Bác đang kể một chuyện'}
    provider.models.generate_content.return_value = SimpleNamespace(text=json.dumps(data))
    history = [{'role':'user', 'content':'Hẹn gặp lại'}]
    result = (ai.get_assistant_response_from_audio(wav_bytes(), 'audio/wav', history)
              if audio else ai.get_assistant_response('Bác đang kể một chuyện', history))
    assert result['end_conversation'] is False
    data['transcription'] = 'Tạm biệt cháu nhé'
    provider.models.generate_content.return_value = SimpleNamespace(text=json.dumps(data))
    result = (ai.get_assistant_response_from_audio(wav_bytes(), 'audio/wav')
              if audio else ai.get_assistant_response('Tạm biệt cháu nhé'))
    assert result['end_conversation'] is True
    provider.close.assert_called()


def test_both_prompts_and_schema_express_manual_conversation_closure():
    for prompt in (ai.SYSTEM_PROMPT, ai.AUDIO_SYSTEM_PROMPT):
        assert 'end_conversation' in prompt
        assert 'không gợi ý tính năng lúc đó' in prompt
    assert ai.RESPONSE_SCHEMA['properties']['end_conversation']['type'] == 'BOOLEAN'


@pytest.mark.anyio
async def test_private_speech_returns_real_audio_without_files_or_cache(monkeypatch):
    audio = wav_bytes()
    synthesize = AsyncMock(return_value=audio)
    monkeypatch.setattr(tts, '_synthesize', synthesize)
    monkeypatch.setattr(tts, '_write_audio', lambda *_: pytest.fail('private speech wrote a file'))
    before = dict(tts._memory_cache)
    result, media = await tts.generate_private_speech('EmoHeal chào Bác', 'charon')
    assert result == audio and media == 'audio/wav'
    synthesize.assert_awaited_once_with('I-mô-hêu chào Bác', 'Charon')
    assert dict(tts._memory_cache) == before


@pytest.mark.anyio
async def test_private_speech_rejects_invalid_audio(monkeypatch):
    monkeypatch.setattr(tts, '_synthesize', AsyncMock(return_value=b'not audio'))
    with pytest.raises(RuntimeError):
        await tts.generate_private_speech('Cháu chào Bác')


def test_private_speech_http_response_is_not_publicly_cacheable(monkeypatch):
    audio = wav_bytes()
    synthesize = AsyncMock(return_value=(audio, 'audio/wav'))
    monkeypatch.setattr(main, 'generate_private_speech', synthesize)
    response = TestClient(main.app).post('/api/companion/speech', json={'text':'Cháu chào Bác', 'voice':'aoede'})
    assert response.status_code == 200 and response.content == audio
    assert response.headers['cache-control'] == 'no-store'
    assert response.headers['content-type'] == 'audio/wav'
    assert 'audio_url' not in response.text


@pytest.mark.parametrize('payload', [{}, {'text':''}, {'text':' '*3}, {'text':123},
    {'text':'x'*2001}, {'text':'Chào Bác', 'voice':'unknown'}, {'text':'Chào Bác', 'voice':[]}])
def test_private_speech_invalid_requests_do_not_call_provider(monkeypatch, payload):
    synthesize = AsyncMock()
    monkeypatch.setattr(main, 'generate_private_speech', synthesize)
    response = TestClient(main.app).post('/api/companion/speech', json=payload)
    assert response.status_code == 400
    synthesize.assert_not_called()


def test_private_speech_failure_is_visible_without_provider_details(monkeypatch):
    monkeypatch.setattr(main, 'generate_private_speech', AsyncMock(side_effect=RuntimeError('private provider detail')))
    response = TestClient(main.app).post('/api/companion/speech', json={'text':'Chào Bác'})
    assert response.status_code == 503
    assert 'private provider detail' not in response.text
