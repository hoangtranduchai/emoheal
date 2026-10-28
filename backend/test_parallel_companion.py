import asyncio
import base64
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest
from services import live_ai_service as live
from services.parallel_companion import CompletedInput, ParallelTurnAnalyzer, command_from_analysis
from test_live_voice import FakeSession, content, response


def spoken_turn(text='Bác đang buồn'):
    return response(server_content=content(
        input_transcription=SimpleNamespace(text=text),
        model_turn=SimpleNamespace(parts=[SimpleNamespace(inline_data=SimpleNamespace(
            data=b'\x01\x00', mime_type='audio/pcm;rate=24000'))])))


def insight():
    return {'emotion':'SADNESS', 'confidence':.9, 'context':'current', 'safety_signal':'none'}


@pytest.mark.anyio
async def test_basic_command_uses_complete_speech_and_never_calls_the_emotion_provider():
    session, incoming, sent = FakeSession(), asyncio.Queue(), asyncio.Queue()
    analyze = AsyncMock(side_effect=RuntimeError('Provider quota exhausted'))
    await incoming.put({'type':'app_context','context':{'local_commands':True}})
    async def send(event):
        await sent.put(event)
        if event['type'] == 'input_turn':
            await incoming.put({'type':'input_turn_ack','id':event['id'],'handled':True})
    task = asyncio.create_task(live._bridge_session(session,incoming.get,send,analyzer=analyze))
    try:
        await asyncio.sleep(.01)
        await session.incoming.put(response(server_content=content(
            input_transcription=SimpleNamespace(text='Mở ',finished=False))))
        await session.incoming.put(response(server_content=content(
            input_transcription=SimpleNamespace(text='Cài đặt',finished=True))))
        while (event := await asyncio.wait_for(sent.get(),1))['type'] != 'input_turn':
            pass
        assert event['text'] == 'Mở Cài đặt'
        await session.incoming.put(response(server_content=content(turn_complete=True)))
        await asyncio.sleep(.15)
        analyze.assert_not_awaited()
        assert session.tool_responses.empty()
    finally:
        await incoming.put({'type':'close'})
        await asyncio.wait_for(task,1)


@pytest.mark.anyio
async def test_missing_transcription_finish_uses_the_complete_turn_without_dispatching_a_prefix():
    output, context = asyncio.Queue(), {'local_commands':True,'pending_suggestion_id':'shown-at-start'}
    analyze = AsyncMock(return_value={'intent':'CHAT'})
    analyzer = ParallelTurnAnalyzer(analyze,output,lambda:context)
    analyzer.transcript('Mở Radio')
    analyzer.reply()
    await asyncio.sleep(.1)
    assert output.empty()
    analyze.assert_not_awaited()
    context['pending_suggestion_id'] = 'new-choice'
    analyzer.transcript(', à thôi không mở nữa.')
    analyzer.end()
    event = await asyncio.wait_for(output.get(),1)
    assert isinstance(event,CompletedInput)
    assert event.utterance == 'Mở Radio, à thôi không mở nữa.'
    assert event.proposal_id == 'shown-at-start'
    analyzer.acknowledge('unrelated',True)
    analyzer.acknowledge(event.id,False)
    await asyncio.wait_for(output.get(),1)
    assert analyze.await_args.args[1] == event.utterance
    await analyzer.close()


@pytest.mark.anyio
async def test_repeated_phrases_have_different_turn_ids_and_do_not_reuse_an_old_ack():
    output, analyze = asyncio.Queue(), AsyncMock()
    analyzer = ParallelTurnAnalyzer(analyze,output,lambda:{'local_commands':True})
    ids = []
    for _ in range(2):
        analyzer.text('Chữ to lên')
        event = await asyncio.wait_for(output.get(),1)
        ids.append(event.id)
        analyzer.acknowledge(event.id,True)
        await asyncio.sleep(.1)
        analyzer.end()
    assert ids[0] != ids[1]
    analyze.assert_not_awaited()
    await analyzer.close()


@pytest.mark.anyio
async def test_a_truncated_transcript_never_becomes_an_executable_tail_command():
    output, analyze = asyncio.Queue(), AsyncMock()
    analyzer = ParallelTurnAnalyzer(analyze,output,lambda:{'local_commands':True})
    analyzer.transcript('Bác kể chuyện ' * 1000 + 'mở Radio',finished=True)
    analyzer.reply()
    result = await asyncio.wait_for(output.get(),1)
    assert not isinstance(result,CompletedInput)
    assert result.unavailable
    analyze.assert_not_awaited()
    await analyzer.close()


@pytest.mark.anyio
async def test_first_speech_is_forwarded_while_analysis_is_still_waiting():
    session, incoming, sent = FakeSession(), asyncio.Queue(), asyncio.Queue()
    gate = asyncio.get_running_loop().create_future()
    async def analyze(*args):
        return await gate
    async def send(event):
        await sent.put(event)
        if event['type'] == 'companion_insight':
            await incoming.put({'type':'insight_ack','id':event['id'],'context':{'route':'/home'}})
    await incoming.put({'type':'audio','data':base64.b64encode(b'\x01\x00'*160).decode()})
    await session.incoming.put(spoken_turn())
    task = asyncio.create_task(live._bridge_session(session, incoming.get, send, analyzer=analyze))
    try:
        first = await asyncio.wait_for(sent.get(), .5)
        assert first['type'] == 'audio_chunk'
        assert not gate.done()
        gate.set_result({'insight':insight(),'transcription':'Bác đang buồn','intent':'CHAT'})
        while (event := await asyncio.wait_for(sent.get(), 1))['type'] != 'companion_insight':
            pass
        assert event['insight']['recommendation'] == 'radio'
        await asyncio.sleep(.01)
        assert session.tool_responses.empty()
    finally:
        await incoming.put({'type':'close'})
        await asyncio.wait_for(task, 1)


@pytest.mark.anyio
async def test_parallel_action_waits_for_phone_and_only_reads_the_actual_outcome():
    session, incoming, sent = FakeSession(), asyncio.Queue(), asyncio.Queue()
    analyze = AsyncMock(return_value={'insight':insight(), 'transcription':'Tạm dừng Radio',
        'intent':'CONTROL','target':'radio','action':'pause','request_kind':'explicit_request'})
    async def send(event):
        await sent.put(event)
        if event['type'] == 'companion_insight':
            await incoming.put({'type':'insight_ack','id':event['id'],'context':{'route':'/radio'}})
    await session.incoming.put(spoken_turn('Tạm dừng Radio'))
    task = asyncio.create_task(live._bridge_session(session, incoming.get, send, analyzer=analyze))
    try:
        while (event := await asyncio.wait_for(sent.get(), 1))['type'] != 'tool_call':
            pass
        assert event['name'] == 'control_radio'
        assert event['utterance'] == 'Tạm dừng Radio'
        assert session.inputs == [] and session.tool_responses.empty()
        await incoming.put({'type':'tool_result','id':event['id'],'name':event['name'],
            'result':{'status':'failed','message':'Chưa dừng được Radio.'}})
        await asyncio.sleep(.02)
        assert session.inputs == []  # No extra user turn interrupts the current speech.
        await session.incoming.put(response(server_content=content(turn_complete=True)))
        for _ in range(20):
            if session.inputs:
                break
            await asyncio.sleep(.01)
        assert 'Chưa dừng được Radio.' in session.inputs[-1]['text']
        assert '"status": "failed"' in session.inputs[-1]['text']
        assert session.tool_responses.empty()
    finally:
        await incoming.put({'type':'close'})
        await asyncio.wait_for(task, 1)


@pytest.mark.anyio
async def test_reply_end_keeps_analysis_but_a_new_utterance_discards_the_old_result():
    output, gates = asyncio.Queue(), [asyncio.get_running_loop().create_future() for _ in range(2)]
    calls = []
    async def analyze(pcm, text, context):
        index = len(calls)
        calls.append(text)
        return await asyncio.shield(gates[index])
    analyzer = ParallelTurnAnalyzer(analyze, output, lambda:{'route':'/home'})
    analyzer.text('Lượt một')
    await asyncio.sleep(.1)
    analyzer.end()
    analyzer.text('Lượt hai')
    await asyncio.sleep(.1)
    gates[0].set_result({'intent':'SOS'})
    gates[1].set_result({'intent':'CHAT'})
    outcome = await asyncio.wait_for(output.get(), 1)
    assert outcome.utterance == 'Lượt hai'
    assert outcome.result['intent'] == 'CHAT'
    await asyncio.sleep(.01)
    assert output.empty()
    await analyzer.close()


@pytest.mark.anyio
async def test_long_audio_is_not_silently_truncated_into_a_command():
    output = asyncio.Queue()
    analyze = AsyncMock()
    analyzer = ParallelTurnAnalyzer(analyze, output, lambda:{})
    analyzer.audio(bytes(32000))
    analyzer.transcript('Bác đang kể chuyện')
    for _ in range(31):
        analyzer.audio(bytes(32000))
    analyzer.reply()
    result = await asyncio.wait_for(output.get(), 1)
    assert result.unavailable
    analyze.assert_not_awaited()
    await analyzer.close()


@pytest.mark.parametrize('target,action,name,args', [
    ('radio','pause','control_radio',{'action':'pause'}),
    ('radio','next','control_radio',{'action':'next'}),
    ('radio',None,'open_radio',{}),
    ('breathing','start_breathing','control_breathing',{'action':'start'}),
    ('breathing','pause_breathing','control_breathing',{'action':'pause'}),
    ('voice-memo',None,'open_voice_memo',{}),
    ('voice-memo','save_recording','control_voice_memo',{'action':'stop_and_save'}),
    ('settings','font_increase','adjust_settings',{'setting_type':'font_size','font_delta':.15}),
    ('settings','voice_male','adjust_settings',{'setting_type':'voice_type','voice_type':'charon'}),
    ('settings','sound_off','adjust_settings',{'setting_type':'sound','sound_enabled':False}),
    ('home',None,'navigate_to_screen',{'screen':'home'}),
    ('history',None,'open_history',{}),
])
def test_analysis_keeps_the_existing_app_command_contract(target, action, name, args):
    actual = command_from_analysis({'intent':'CONTROL','target':target,'action':action,'request_kind':'explicit_request'})
    assert actual == (name, {**args,'request_kind':'explicit_request'})


def test_analysis_only_suggests_for_emotion_and_scopes_consent_to_a_real_id():
    assert command_from_analysis({'intent':'CHAT','target':'radio'}) is None
    assert command_from_analysis({'intent':'SOS','destination':'ambulance'}) == ('trigger_sos_emergency',{'destination':'ambulance'})
    assert command_from_analysis({'intent':'SOS'}) == ('trigger_sos_emergency',{})
    assert command_from_analysis({'action':'sos_cancel'}) == ('cancel_sos_emergency',{})
    assert command_from_analysis({'proposal_id':'existing','suggestion_reply':'decline'}) == ('respond_to_suggestion',{'proposal_id':'existing','decision':'decline'})


@pytest.mark.parametrize('audio', [False, True])
@pytest.mark.parametrize('target,action,details,tool', [
    ('radio', 'select_genre', {'genre':'Dân ca'}, 'control_radio'),
    ('radio', 'play', {'track_title':'Làng tôi'}, 'control_radio'),
    ('voice-memo', 'change_topic', {'topic':'Tuổi thơ'}, 'control_voice_memo'),
    ('sos', 'sos_trigger', {}, 'trigger_sos_emergency'),
])
def test_real_analysis_contract_preserves_command_arguments_and_requires_a_recipient(monkeypatch, audio, target, action, details, tool):
    from services import ai_service as ai
    client = MagicMock()
    monkeypatch.setattr(ai, '_get_client', lambda:client)
    client.models.generate_content.return_value.text = json.dumps({
        'emotion':'NEUTRAL', 'emotion_context':'current', 'safety_signal':'none',
        'intent':'SOS' if target == 'sos' else 'CONTROL', 'target':target, 'action':action,
        'request_kind':'explicit_request', 'text':'Dạ cháu ghi nhận yêu cầu.',
        'transcription':'Bác muốn đổi tính năng', **details})
    result = ai.get_assistant_response_from_audio(b'test', 'audio/wav') if audio else ai.get_assistant_response('Bác muốn đổi tính năng')
    assert result['destination'] is None
    expected = {**details, **({'genre':'dan_ca'} if 'genre' in details else {})}
    assert all(result[key] == value for key,value in expected.items())
    name, args = command_from_analysis(result)
    assert name == tool
    assert all(args[key] == value for key,value in expected.items())
    live._validate_tool(name, args)
