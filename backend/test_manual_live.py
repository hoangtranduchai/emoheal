import asyncio
import base64
from types import SimpleNamespace
from unittest.mock import AsyncMock
import pytest
from google.genai import types
from services import manual_companion as manual
from test_live_voice import FakeSession, response, content, tool

class Session(FakeSession):
    def __init__(self):
        super().__init__()
        self.contexts=[]
    async def send_client_content(self, **values):
        self.contexts.append(values)

async def pump():
    await asyncio.sleep(.01)

def test_manual_config_disables_vad_and_pins_requested_31_live_model():
    assert manual.COMPANION_MODEL == 'gemini-3.1-flash-live-preview'
    config=manual.manual_config(manual.COMPANION_MODEL,'charon',[{'role':'user','content':'Bác chào cháu'}])
    assert config.realtime_input_config.automatic_activity_detection.disabled is True
    assert config.input_audio_transcription is not None
    assert config.output_audio_transcription is not None
    assert config.speech_config.voice_config.prebuilt_voice_config.voice_name == 'Charon'
    assert config.tools
    assert 'Bác chào cháu' in config.system_instruction.parts[0].text

@pytest.mark.parametrize('model', ['gemini-3.8-live', 'gemini-2.5-flash-native-audio-preview-12-2025', 'gemini-2.5-flash'])
def test_manual_config_refuses_alternative_models(model):
    with pytest.raises(ValueError, match='fixed'):
        manual.manual_config(model,'aoede')

@pytest.mark.anyio
async def test_failed_31_live_connection_never_attempts_another_model(monkeypatch):
    class RejectedConnection:
        async def __aenter__(self):
            raise RuntimeError('429 RESOURCE_EXHAUSTED quota')
        async def __aexit__(self, *args):
            pass
    attempts=[]
    def connect(**values):
        attempts.append(values['model'])
        return RejectedConnection()
    client=SimpleNamespace(aio=SimpleNamespace(
        live=SimpleNamespace(connect=connect), aclose=AsyncMock()))
    monkeypatch.setattr(manual.genai,'Client',lambda **kwargs:client)
    monkeypatch.setattr(manual.live,'CANDIDATE_LIVE_MODELS',['gemini-3.8-live','gemini-2.5-flash'])
    events=[]
    await manual.handle_manual_session(AsyncMock(return_value={'type':'hello','history':[]}),_sender(events))
    assert attempts == [manual.COMPANION_MODEL]
    assert [event['type'] for event in events] == ['error']
    client.aio.aclose.assert_awaited_once()

@pytest.mark.anyio
async def test_two_manual_turns_keep_all_transcripts_and_only_end_on_tap():
    session, incoming, events = Session(), asyncio.Queue(), []
    task=asyncio.create_task(manual.bridge_manual(session,incoming.get,_sender(events),'test-model'))
    try:
        for index in range(2):
            key=f'turn-{index}'
            await incoming.put({'type':'begin','id':key,'context':{'route':'/radio','phone':'private'}})
            await incoming.put({'type':'audio','id':key,'data':base64.b64encode(b'\x01\x00'*10).decode()})
            await pump()
            assert sum('activity_end' in event for event in session.inputs)==index
            await session.incoming.put(response(server_content=content(input_transcription=SimpleNamespace(text='Chuyển '))))
            await pump()
            assert not any(event['type']=='result' and event['id']==key for event in events)
            await incoming.put({'type':'submit','id':key})
            await incoming.put({'type':'submit','id':key})
            await pump()
            await session.incoming.put(response(server_content=content(
                input_transcription=SimpleNamespace(text='bài'), output_transcription=SimpleNamespace(text='Cháu ghi nhận.'),
                model_turn=SimpleNamespace(parts=[SimpleNamespace(inline_data=SimpleNamespace(data=b'\x01\x00'*30))]), turn_complete=True)))
            await pump()
            result=[e for e in events if e['type']=='result' and e['id']==key][0]
            assert result['transcription']=='Chuyển bài'
            assert base64.b64decode(result['audio_pcm']) == b'\x01\x00'*30
            assert result['model']=='test-model'
            assert sum('activity_end' in event for event in session.inputs)==index+1
        assert all(e['turn_complete'] is False for e in session.contexts)
        assert 'private' not in str(session.contexts)
        await incoming.put({'type':'close'})
        await asyncio.wait_for(task,1)
    finally:
        task.cancel(); await asyncio.gather(task, return_exceptions=True)


def _sender(events):
    async def send(event): events.append(event)
    return send

@pytest.mark.anyio
async def test_native_tools_are_forwarded_not_executed_and_insights_normalized():
    session, incoming, events = Session(), asyncio.Queue(), []
    task=asyncio.create_task(manual.bridge_manual(session,incoming.get,_sender(events),'test'))
    try:
        await incoming.put({'type':'begin','id':'t','context':{}})
        await incoming.put({'type':'submit','id':'t'})
        await pump()
        await session.incoming.put(response(server_content=content(input_transcription=SimpleNamespace(text='Chữ to lên'))))
        await session.incoming.put(tool('emotion','report_emotion',{'emotion':'NEUTRAL','confidence':None,'context':'current','safety_signal':'none'}))
        await session.incoming.put(tool('control','adjust_settings',{'setting_type':'font_size','font_delta':.15,'request_kind':'explicit_request'}))
        emotion=(await asyncio.wait_for(session.tool_responses.get(),1))[0]
        command=(await asyncio.wait_for(session.tool_responses.get(),1))[0]
        assert emotion.response['status']=='reported'
        assert command.response['status']=='forwarded'
        assert not any(e['type']=='result' for e in events)
        await session.incoming.put(response(server_content=content(turn_complete=True)))
        await pump()
        result=[e for e in events if e['type']=='result'][0]
        assert result['insight']['confidence'] is None
        assert result['tool_call']['name']=='adjust_settings'
        assert result['tool_call']['args']['request_kind']=='explicit_request'
        await incoming.put({'type':'result_ack','id':'t','result':{'status':'failed','message':'Chưa thực hiện được.'}})
        await pump()
        assert 'failed' in str(session.contexts[-1])
        assert session.contexts[-1]['turn_complete'] is False
        await incoming.put({'type':'close'}); await asyncio.wait_for(task,1)
    finally:
        task.cancel(); await asyncio.gather(task, return_exceptions=True)

@pytest.mark.anyio
@pytest.mark.parametrize('bad_event', [
    {'type':'audio','id':'other','data':'AQAA'},
    {'type':'audio','id':'t','data':'not base64'},
    {'type':'audio','id':'t','data':base64.b64encode(b'\x01').decode()},
    {'type':'begin','id':'t','context':{}},
])
async def test_invalid_or_duplicate_input_closes_without_results(bad_event):
    session, incoming, events=Session(), asyncio.Queue(), []
    await incoming.put({'type':'begin','id':'t','context':{}})
    await incoming.put(bad_event)
    with pytest.raises(ValueError):
        await asyncio.wait_for(manual.bridge_manual(session,incoming.get,_sender(events),'test'),1)
    assert not any(event['type']=='result' for event in events)

@pytest.mark.anyio
async def test_provider_reply_before_manual_submission_is_rejected():
    session,incoming,events=Session(),asyncio.Queue(),[]
    await incoming.put({'type':'begin','id':'t'})
    task=asyncio.create_task(manual.bridge_manual(session,incoming.get,_sender(events),'test'))
    await pump()
    await session.incoming.put(response(server_content=content(model_turn=SimpleNamespace(parts=[SimpleNamespace(inline_data=SimpleNamespace(data=b'\x01\x00'))]))))
    with pytest.raises(ValueError, match='before manual'):
        await asyncio.wait_for(task,1)
    assert not any(event['type']=='result' for event in events)

@pytest.mark.anyio
async def test_closing_during_recognition_sends_no_turn_end_or_result():
    session,incoming,events=Session(),asyncio.Queue(),[]
    await incoming.put({'type':'begin','id':'t'})
    await incoming.put({'type':'close'})
    await asyncio.wait_for(manual.bridge_manual(session,incoming.get,_sender(events),'test'),1)
    assert not any('activity_end' in event for event in session.inputs)
    assert not any(event['type']=='result' for event in events)
@pytest.mark.anyio
async def test_combined_input_tool_and_audio_defers_speech_before_forwarding_audio():
    session,incoming,events=Session(),asyncio.Queue(),[]
    await incoming.put({'type':'begin','id':'t','context':{}})
    await incoming.put({'type':'submit','id':'t'})
    task=asyncio.create_task(manual.bridge_manual(session,incoming.get,_sender(events),'test'))
    await pump()
    event=tool('control','control_radio',{'action':'next','request_kind':'explicit_request'})
    event.server_content=content(input_transcription=SimpleNamespace(text='Chuyển bài'),
        model_turn=SimpleNamespace(parts=[SimpleNamespace(inline_data=SimpleNamespace(data=b'\x01\x00'))]), turn_complete=True)
    await session.incoming.put(event); await pump()
    kinds=[e['type'] for e in events]
    assert kinds.index('hold_speech') < kinds.index('audio') < kinds.index('result')
    assert [e for e in events if e['type']=='result'][0]['tool_call']['name']=='control_radio'
    await incoming.put({'type':'close'}); await asyncio.wait_for(task,1)

@pytest.mark.anyio
async def test_cancelled_provider_plan_cannot_become_an_app_command():
    session,incoming,events=Session(),asyncio.Queue(),[]
    await incoming.put({'type':'begin','id':'t','context':{}})
    await incoming.put({'type':'submit','id':'t'})
    task=asyncio.create_task(manual.bridge_manual(session,incoming.get,_sender(events),'test'))
    await pump()
    await session.incoming.put(tool('old','control_radio',{'action':'next','request_kind':'explicit_request'}))
    await asyncio.wait_for(session.tool_responses.get(),1)
    await session.incoming.put(response(tool_call_cancellation=SimpleNamespace(ids=['old'])))
    await session.incoming.put(response(server_content=content(turn_complete=True)))
    await pump()
    assert 'tool_call' not in [e for e in events if e['type']=='result'][0]
    await incoming.put({'type':'close'}); await asyncio.wait_for(task,1)

@pytest.mark.anyio
async def test_invalid_tool_is_reported_failed_consistently_without_losing_conversation():
    session,incoming,events=Session(),asyncio.Queue(),[]
    await incoming.put({'type':'begin','id':'t','context':{}})
    await incoming.put({'type':'submit','id':'t'})
    task=asyncio.create_task(manual.bridge_manual(session,incoming.get,_sender(events),'test'))
    await pump()
    invalid=tool('invalid','control_radio',{'action':'delete','request_kind':'explicit_request'})
    for _ in range(2):
        await session.incoming.put(invalid)
        result=(await asyncio.wait_for(session.tool_responses.get(),1))[0]
        assert result.response['status']=='failed'
    await session.incoming.put(response(server_content=content(turn_complete=True))); await pump()
    assert 'tool_call' not in [e for e in events if e['type']=='result'][0]
    await incoming.put({'type':'close'}); await asyncio.wait_for(task,1)
