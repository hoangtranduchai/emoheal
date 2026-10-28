import asyncio
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest
import main
from fastapi.testclient import TestClient
from services import live_ai_service as live
from services.companion_policy import normalize_insight
from test_live_voice import FakeSession, content, response, tool


@pytest.mark.parametrize('emotion,recommendation', [
    ('PANIC_STRESS', 'help'), ('SADNESS', 'radio'), ('NOSTALGIA', 'voice_memo'),
    ('CALM', None), ('HAPPINESS', None), ('NEUTRAL', None),
])
def test_six_emotions_are_observations_not_automatic_commands(emotion, recommendation):
    value = normalize_insight({'emotion': emotion, 'confidence': .9, 'context': 'current'})
    assert value['recommendation'] == recommendation
    assert 'action' not in value


@pytest.mark.parametrize('score', [None, True, '0.9', -1, 5, float('nan'), float('inf')])
def test_missing_or_invalid_certainty_is_never_fabricated(score):
    value = normalize_insight({'emotion': 'SADNESS', 'confidence': score, 'context': 'current'})
    assert value['confidence'] is None
    assert value['recommendation'] is None
    assert value['uncertain']


@pytest.mark.parametrize('text,context', [
    ('Ngày xưa bác bị ngã khi ở chiến trường', 'past'),
    ('Bác không bị ngã, bác không đau', 'negated'),
    ('Nếu bác bị ngã thì phải làm sao?', 'hypothetical'),
    ('Hôm qua bác đau nhưng hiện tại bác cần giúp vì lại ngã', 'current'),
])
def test_transcript_guards_against_false_current_emergencies(text, context):
    value = normalize_insight({'emotion': 'PANIC_STRESS', 'confidence': .95,
        'context': 'current', 'safety_signal': 'fall'}, text)
    assert value['context'] == context
    assert (value['recommendation'] == 'help') == (context == 'current')


@pytest.mark.anyio
async def test_live_reports_structured_emotion_once_without_dispatching_an_action():
    session, incoming, sent = FakeSession(), asyncio.Queue(), []
    report = tool('emotion-1', 'report_emotion', {'emotion': 'SADNESS', 'confidence': .9,
        'context': 'current', 'safety_signal': 'none'})
    await session.incoming.put(report)
    await session.incoming.put(report)
    async def send(event):
        sent.append(event)
        if len(sent) == 1:
            # UI attaches the actual choice ID without injecting a new model turn.
            await incoming.put({'type': 'insight_ack', 'id': 'emotion-1', 'context': {'pending_suggestion_id': 'suggestion-1', 'pending_suggestion_type': 'radio', 'phone': 'private'}})
    task = asyncio.create_task(live._bridge_session(session, incoming.get, send))
    try:
        first = await asyncio.wait_for(session.tool_responses.get(), 1)
        await asyncio.wait_for(session.tool_responses.get(), 1)
        assert first[0].response['status'] == 'reported'
        assert first[0].response['insight']['recommendation'] == 'radio'
        assert first[0].response['app_context'] == {'pending_suggestion_id': 'suggestion-1', 'pending_suggestion_type': 'radio'}
        assert session.inputs == []
        assert len(sent) == 1 and sent[0]['type'] == 'companion_insight'
    finally:
        await incoming.put({'type': 'close'})
        await asyncio.wait_for(task, 1)


@pytest.mark.anyio
@pytest.mark.parametrize('name', ['report_emotion', 'control_radio'])
async def test_missing_provider_id_gets_a_client_id_but_is_not_fabricated_in_the_reply(name):
    session, incoming = FakeSession(), asyncio.Queue()
    args = {'emotion': 'CALM', 'confidence': .9, 'context': 'current', 'safety_signal': 'none'} if name == 'report_emotion' else {'action': 'pause'}
    await session.incoming.put(tool(None, name, args))
    async def send(event):
        assert isinstance(event['id'], str) and event['id']
        if event['type'] == 'companion_insight':
            await incoming.put({'type': 'insight_ack', 'id': event['id'], 'context': {'route': '/home'}})
        else:
            await incoming.put({'type': 'tool_result', 'id': event['id'], 'name': name,
                'result': {'status': 'failed', 'message': 'Không thực hiện thao tác trong phiên thử.'}})
    task = asyncio.create_task(live._bridge_session(session, incoming.get, send))
    try:
        answer = (await asyncio.wait_for(session.tool_responses.get(), 1))[0]
        assert answer.id is None
        assert answer.name == name
    finally:
        await incoming.put({'type': 'close'})
        await asyncio.wait_for(task, 1)


@pytest.mark.anyio
@pytest.mark.parametrize('choice', [None, 'existing-choice'])
async def test_live_only_waits_for_a_choice_that_is_actually_visible(choice):
    session, incoming = FakeSession(), asyncio.Queue()
    await session.incoming.put(tool('calm', 'report_emotion', {'emotion': 'CALM', 'confidence': .9,
        'context': 'current', 'safety_signal': 'none'}))
    state = {'route': '/home'}
    if choice:
        state['pending_suggestion_id'] = choice
    async def send(event):
        await incoming.put({'type': 'insight_ack', 'id': event['id'], 'context': state})
    task = asyncio.create_task(live._bridge_session(session, incoming.get, send))
    try:
        answer = (await asyncio.wait_for(session.tool_responses.get(), 1))[0].response
        assert answer['awaiting_user_choice'] == bool(choice)
        assert answer['app_context'] == state
        assert answer['insight']['recommendation'] is None
    finally:
        await incoming.put({'type': 'close'})
        await asyncio.wait_for(task, 1)


@pytest.mark.anyio
async def test_live_accepts_awaiting_confirmation_without_announcing_execution():
    session, incoming, sent = FakeSession(), asyncio.Queue(), []
    await session.incoming.put(tool('radio', 'open_radio', {'request_kind': 'suggestion'}))
    async def send(event):
        sent.append(event)
        if event['type'] == 'tool_call':
            await incoming.put({'type': 'tool_result', 'id': 'radio', 'name': 'open_radio',
                'result': {'status': 'awaiting_confirmation', 'message': 'Bác có muốn nghe Radio không ạ?'}})
    task = asyncio.create_task(live._bridge_session(session, incoming.get, send))
    try:
        answer = await asyncio.wait_for(session.tool_responses.get(), 1)
        assert answer[0].response['status'] == 'awaiting_confirmation'
    finally:
        await incoming.put({'type': 'close'})
        await asyncio.wait_for(task, 1)


def test_rest_context_contains_only_app_state_and_never_private_fields(monkeypatch):
    generate = MagicMock(return_value={'text': 'Cháu lắng nghe Bác.'})
    monkeypatch.setattr(main, 'get_assistant_response', generate)
    result = TestClient(main.app).post('/api/assistant', data={'text': 'Chào cháu',
        'include_audio': 'false', 'app_context': json.dumps({'pending_suggestion_id': 'suggestion-1',
        'pending_suggestion_type': 'help', 'phone': 'private', 'transcript': 'private'})})
    assert result.status_code == 200
    state = generate.call_args.kwargs['app_context']
    assert state == {'pending_suggestion_id': 'suggestion-1', 'pending_suggestion_type': 'help'}
    bad = TestClient(main.app).post('/api/assistant', data={'text': 'Chào', 'app_context': '[]'})
    assert bad.status_code == 400
