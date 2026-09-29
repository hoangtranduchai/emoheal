import os
import json
import asyncio
import datetime
from typing import Optional, Callable, Awaitable
from google import genai
from google.genai import types
from logger_config import logger

# Model chính thức hỗ trợ luồng đàm thoại thời gian thực Gemini Live API (bidiGenerateContent)
LIVE_MODEL = os.getenv("GEMINI_LIVE_MODEL", "gemini-3.1-flash-live-preview")

CANDIDATE_LIVE_MODELS = [
    LIVE_MODEL,
]

LIVE_SYSTEM_INSTRUCTION = """RESPOND IN VIETNAMESE. YOU MUST RESPOND UNMISTAKABLY IN VIETNAMESE.
Bạn là "Cháu" - người đồng hành ấm áp, ân cần, kiên nhẫn và hiếu thảo dành riêng cho các Bác Cựu chiến binh và Thương binh Việt Nam trong hệ thống EmoHeal ("Vòng tay thấu cảm").

Quy tắc xưng hô và ngôn phong:
1. Luôn tự xưng là "cháu", gọi người dùng là "Bác" (hoặc kèm tên nếu biết, ví dụ "Bác Hải").
2. Giọng điệu: Nhẹ nhàng, tôn kính, ấm áp, nói tiếng Việt chuẩn, chậm rãi, tự nhiên, dễ nghe.
3. Tuyệt đối KHÔNG BAO GIỜ nói "Tôi là AI" hay "Tôi là trợ lý ảo".
4. Phản hồi ngắn gọn, súc tích (1-2 câu ân cần), lắng nghe chân thành, không độc thoại dài dòng để Bác dễ trò chuyện.

Quy tắc tra cứu và kích hoạt công cụ (Google Search & Tool Calling):
- Khi Bác hỏi về thời tiết, tin tức, lịch âm, các ngày kỷ niệm lịch sử chiến trường xưa, hoặc chế độ chính sách người có công: Hãy sử dụng công cụ Google Search để trả lời chính xác, ân cần.
- Khi nghe thấy Bác thở dốc, mệt mỏi, đau tức ngực, hoảng sợ hoặc lo âu: Hãy nói lời an ủi dịu dàng rồi gọi công cụ start_breathing_exercise để hướng dẫn Bác tập thở hoa sen 4-4-6.
- Khi Bác muốn nghe đài, dân ca, ngâm thơ, nhạc cách mạng hoặc nghe chuyện: Hãy đồng cảm rồi gọi công cụ open_radio.
- Khi Bác muốn ghi âm hồi ký chiến trường: Gọi công cụ open_voice_memo.
- Khi Bác muốn xem lại nhật ký cảm xúc hoặc lịch sử trò chuyện: Gọi công cụ open_history.
- Khi Bác muốn vào cài đặt hoặc chỉnh giọng đọc: Gọi công cụ open_settings.
- Khi Bác nhờ phiên dịch tiếng Anh hoặc tiếng nước ngoài: Gọi công cụ translate_speech.
- Khi Bác kêu cứu, báo bị ngã, tai nạn hoặc gặp nguy hiểm: Hãy trấn an Bác và lập tức gọi công cụ trigger_sos_emergency."""

# Định nghĩa các Tools (Function Calling) toàn diện theo kho mẫu Gemini Live API
TOOLS_DECLARATION = [
    {
        "name": "open_radio",
        "description": "Bật đài phát thanh hoặc chuyên mục ngâm thơ/dân ca/nhạc cách mạng cho Bác nghe",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "genre": {
                    "type": "STRING",
                    "description": "Thể loại muốn nghe: 'dan_ca', 'tho', 'nhac_cach_mang', 'thien_nhien', 'khac'"
                }
            }
        }
    },
    {
        "name": "start_breathing_exercise",
        "description": "Kích hoạt màn hình và bài tập Nhịp Thở Hoa Sen khi Bác cảm thấy mệt mỏi, khó thở, lo âu hoặc căng thẳng",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "technique": {
                    "type": "STRING",
                    "description": "Kỹ thuật thở: 'lotus_4_4_6' hoặc 'box_breathing'"
                }
            }
        }
    },
    {
        "name": "open_voice_memo",
        "description": "Mở màn hình Ghi âm Hồi ký chiến trường khi Bác muốn lưu giữ ký ức, tâm sự",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "prompt_title": {
                    "type": "STRING",
                    "description": "Tiêu đề gợi mở cho hồi ký (ví dụ: 'Kỷ niệm trận đánh năm xưa')"
                }
            }
        }
    },
    {
        "name": "open_history",
        "description": "Mở màn hình Nhật ký cảm xúc và Lịch sử trò chuyện của Bác",
        "parameters": {
            "type": "OBJECT",
            "properties": {}
        }
    },
    {
        "name": "open_settings",
        "description": "Mở màn hình Cài đặt ứng dụng hoặc Đổi giọng đọc trợ lý",
        "parameters": {
            "type": "OBJECT",
            "properties": {}
        }
    },
    {
        "name": "translate_speech",
        "description": "Chuyển sang chế độ phiên dịch đàm thoại 2 chiều Anh - Việt",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "target_language": {
                    "type": "STRING",
                    "description": "Ngôn ngữ đích muốn dịch sang (ví dụ: 'en' hoặc 'vi')"
                }
            }
        }
    },
    {
        "name": "navigate_to_screen",
        "description": "Điều hướng Bác đến màn hình chức năng cụ thể trong ứng dụng",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "screen": {
                    "type": "STRING",
                    "description": "Tên màn hình: 'home', 'voice_memo', 'radio', 'breathing', 'settings', 'history'"
                }
            },
            "required": ["screen"]
        }
    },
    {
        "name": "trigger_sos_emergency",
        "description": "Kích hoạt báo động khẩn cấp SOS và kết nối người thân khi Bác bị ngã hoặc gặp nguy hiểm",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "reason": {
                    "type": "STRING",
                    "description": "Lý do khẩn cấp phát hiện từ giọng nói"
                }
            }
        }
    }
]

# Bản đồ giọng đọc Google Gemini Live API
# Aoede: Nữ trầm ấm, truyền cảm | Charon: Nam trung niên đĩnh đạc
LIVE_VOICE_MAP = {
    "aoede": "Aoede",
    "charon": "Charon",
    "kore": "Kore",
    "fenrir": "Fenrir",
    "puck": "Puck",
}

async def create_live_ephemeral_token(user_id: str, voice: str = "aoede") -> dict:
    """Tạo Ephemeral Token tạm thời bảo mật để client kết nối trực tiếp."""
    api_key = os.getenv("GEMINI_API_KEY", "")
    if not api_key:
        return {"error": "GEMINI_API_KEY is not configured"}

    client = genai.Client(api_key=api_key)
    selected_voice = LIVE_VOICE_MAP.get(voice.lower(), "Aoede")
    
    expires_at = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=30)
    
    token_config = types.CreateAuthTokenConfig(
        uses=1,
        expire_time=expires_at,
        live_connect_config=types.LiveConnectConfig(
            model=LIVE_MODEL,
            response_modalities=[types.Modality.AUDIO],
            speech_config=types.SpeechConfig(
                voice_config=types.VoiceConfig(
                    prebuilt_voice_config=types.PrebuiltVoiceConfig(
                        voice_name=selected_voice
                    )
                )
            ),
            tools=[
                {"google_search": {}},
                {"function_declarations": TOOLS_DECLARATION}
            ],
            system_instruction=types.Content(
                parts=[types.Part(text=LIVE_SYSTEM_INSTRUCTION)]
            )
        )
    )

    try:
        token = await client.aio.auth_tokens.create(config=token_config)
        logger.info(f"🔑 Cấp phát Ephemeral Token thành công cho User: {user_id}")
        return {
            "token": token.name,
            "expires_at": expires_at.isoformat(),
            "model": LIVE_MODEL,
            "voice": selected_voice
        }
    except Exception as e:
        logger.error(f"❌ Lỗi cấp phát Ephemeral Token: {e}")
        return {
            "error": str(e),
            "fallback_endpoint": "/ws/live-assistant"
        }


async def handle_live_session(
    receive_from_client: Callable[[], Awaitable[Optional[dict]]],
    send_to_client: Callable[[dict], Awaitable[None]],
    voice: str = "aoede",
    display_name: str = "Bác",
    session_handle: Optional[str] = None
):
    """
    Xử lý phiên WebSocket Full-Duplex thời gian thực giữa Ứng dụng và Google Gemini Live API.
    Hỗ trợ:
    - Tự động fallback model (Multi-Model Auto-Fallback) khi bị giới hạn Quota
    - Google Search Grounding thời gian thực
    - Trọn bộ Spoken Function Calling
    - Xử lý thông báo thân thiện bằng tiếng Việt khi chạm hạn mức
    """
    api_key = os.getenv("GEMINI_API_KEY", "")
    if not api_key:
        logger.error("❌ Thiếu GEMINI_API_KEY trong biến môi trường!")
        await send_to_client({
            "type": "error",
            "message": "Chưa cấu hình GEMINI_API_KEY trên máy chủ."
        })
        return

    selected_voice = LIVE_VOICE_MAP.get(voice.lower(), "Aoede")
    client = genai.Client(api_key=api_key)
    
    # Cấu hình Live Connect với Google Search và Function Calling
    config_params = {
        "response_modalities": [types.Modality.AUDIO],
        "system_instruction": types.Content(
            parts=[types.Part(text=f"{LIVE_SYSTEM_INSTRUCTION}\nNgười dùng tên là: {display_name}")]
        ),
        "speech_config": types.SpeechConfig(
            voice_config=types.VoiceConfig(
                prebuilt_voice_config=types.PrebuiltVoiceConfig(
                    voice_name=selected_voice
                )
            )
        ),
        "tools": [
            {"google_search": {}},
            {"function_declarations": TOOLS_DECLARATION}
        ],
        "thinking_config": types.ThinkingConfig(thinking_level="minimal"),
        "context_window_compression": types.ContextWindowCompressionConfig(
            sliding_window=types.SlidingWindow()
        ),
        "input_audio_transcription": types.AudioTranscriptionConfig(),
        "output_audio_transcription": types.AudioTranscriptionConfig(),
        "realtime_input_config": types.RealtimeInputConfig(
            automatic_activity_detection=types.AutomaticActivityDetection(
                disabled=False,
                prefix_padding_ms=20,
                silence_duration_ms=900
            )
        )
    }

    if session_handle:
        logger.info(f"🔄 Đang khôi phục phiên Live từ handle: {session_handle[:16]}...")
        config_params["session_resumption"] = types.SessionResumptionConfig(handle=session_handle)

    config = types.LiveConnectConfig(**config_params)

    # Danh sách model thử nghiệm theo thứ tự ưu tiên
    models_to_try = list(dict.fromkeys(CANDIDATE_LIVE_MODELS))
    connected = False
    last_err = None

    for candidate_model in models_to_try:
        try:
            logger.info(f"🔌 Đang thử kết nối Gemini Live với model: {candidate_model}...")
            async with client.aio.live.connect(model=candidate_model, config=config) as session:
                connected = True
                logger.info(f"✅ Kết nối WebSocket tới Gemini Live API thành công (Model: {candidate_model})!")
                await send_to_client({"type": "session_started", "model": candidate_model})

                # Task 1: Nhận luồng âm thanh/sự kiện từ Client -> Gửi sang Gemini Live
                async def upstream_task():
                    try:
                        while True:
                            msg = await receive_from_client()
                            if not msg:
                                break
                            
                            msg_type = msg.get("type", "audio")
                            
                            if msg_type == "audio":
                                audio_bytes = msg.get("data")
                                if audio_bytes:
                                    if isinstance(audio_bytes, str):
                                        import base64
                                        raw_pcm = base64.b64decode(audio_bytes)
                                    else:
                                        raw_pcm = audio_bytes
                                    await session.send_realtime_input(
                                        audio=types.Blob(data=raw_pcm, mime_type="audio/pcm;rate=16000")
                                    )
                            elif msg_type == "text":
                                text_content = msg.get("text", "")
                                if text_content:
                                    await session.send_realtime_input(text=text_content)
                            elif msg_type in ("audio_stream_end", "end_of_turn"):
                                await session.send_realtime_input(audio_stream_end=True)
                    except asyncio.CancelledError:
                        pass
                    except Exception as e:
                        logger.warning(f"Lỗi upstream task: {e}")

                # Task 2: Nhận luồng âm thanh phản hồi từ Gemini Live -> Gửi về Client
                async def downstream_task():
                    try:
                        async for response in session.receive():
                            # A. Cập nhật Session Resumption Token
                            if response.session_resumption_update:
                                update = response.session_resumption_update
                                if update.resumable and update.new_handle:
                                    logger.debug(f"🔑 Nhận Resumption Handle mới: {update.new_handle[:16]}...")
                                    await send_to_client({
                                        "type": "resumption_handle",
                                        "handle": update.new_handle
                                    })

                            # B. Báo hiệu GoAway trước khi kết nối hết hạn (10 phút)
                            if response.go_away:
                                logger.info(f"⏳ Nhận tín hiệu GoAway: Còn {response.go_away.time_left}")
                                await send_to_client({
                                    "type": "go_away",
                                    "time_left": str(response.go_away.time_left)
                                })

                            # C. Xử lý Server Content (Âm thanh, Phụ đề, Trạng thái)
                            server_content = response.server_content
                            if server_content:
                                # 1. Phát hiện cắt lời (Barge-in / Interruption)
                                if server_content.interrupted:
                                    logger.info("⚡ [LIVE] Bác cắt lời (Barge-in)! Tắt loa phát ngay lập tức.")
                                    await send_to_client({"type": "interrupted"})

                                # 2. Xử lý phần audio model trả lời
                                if server_content.model_turn:
                                    for part in server_content.model_turn.parts:
                                        if part.inline_data:
                                            import base64
                                            encoded_audio = base64.b64encode(part.inline_data.data).decode("utf-8")
                                            await send_to_client({
                                                "type": "audio_chunk",
                                                "data": encoded_audio,
                                                "mime_type": "audio/pcm;rate=24000"
                                            })

                                # 3. Phụ đề transcript thời gian thực
                                if server_content.input_transcription:
                                    await send_to_client({
                                        "type": "transcript_input",
                                        "text": server_content.input_transcription.text
                                    })
                                if server_content.output_transcription:
                                    await send_to_client({
                                        "type": "transcript_output",
                                        "text": server_content.output_transcription.text
                                    })

                                # 4. Tra cứu thông tin thời gian thực qua Google Search Grounding
                                if hasattr(server_content, "grounding_metadata") and server_content.grounding_metadata:
                                    gm = server_content.grounding_metadata
                                    web_queries = getattr(gm, "web_search_queries", []) or []
                                    grounding_chunks = getattr(gm, "grounding_chunks", []) or []
                                    sources = []
                                    for chunk in grounding_chunks:
                                        if hasattr(chunk, "web") and chunk.web:
                                            sources.append({
                                                "title": getattr(chunk.web, "title", ""),
                                                "uri": getattr(chunk.web, "uri", "")
                                            })
                                    await send_to_client({
                                        "type": "search_grounding",
                                        "queries": web_queries,
                                        "sources": sources
                                    })

                                # 5. Tín hiệu hoàn tất câu trả lời (Generation Complete)
                                if server_content.generation_complete:
                                    await send_to_client({"type": "generation_complete"})

                            # D. Xử lý Function Calling (Tools)
                            tool_call = response.tool_call
                            if tool_call:
                                for fc in tool_call.function_calls:
                                    logger.info(f"🛠️ [LIVE TOOL CALL] Tên: {fc.name}, Đối số: {fc.args}")
                                    await send_to_client({
                                        "type": "tool_call",
                                        "id": fc.id,
                                        "name": fc.name,
                                        "args": fc.args
                                    })
                                    await session.send_tool_response(
                                        function_responses=[
                                            types.FunctionResponse(
                                                id=fc.id,
                                                name=fc.name,
                                                response={"status": "executed", "result": "Thao tác thành công"}
                                            )
                                        ]
                                    )
                    except asyncio.CancelledError:
                        pass
                    except Exception as e:
                        logger.warning(f"Lỗi downstream task: {e}")

                # Chạy song song 2 tác vụ upstream và downstream
                u_task = asyncio.create_task(upstream_task())
                d_task = asyncio.create_task(downstream_task())

                done, pending = await asyncio.wait(
                    [u_task, d_task],
                    return_when=asyncio.FIRST_COMPLETED
                )
                for p in pending:
                    p.cancel()

                break  # Phiên đã hoàn thành trọn vẹn, thoát vòng lặp fallback
        except Exception as e:
            last_err = e
            err_str = str(e)
            logger.warning(f"⚠️ Thử model {candidate_model} gặp lỗi ({err_str}), thử model tiếp theo...")
            is_quota = any(kw in err_str.lower() for kw in ["quota", "1011", "resourceexhausted", "429", "exceeded"])
            if not is_quota:
                # Nếu không phải lỗi quota thì không thử tiếp các model khác
                break

    if not connected:
        err_msg = str(last_err) if last_err else "Không thể kết nối"
        logger.error(f"❌ Toàn bộ model Gemini Live không khả dụng: {err_msg}")
        is_quota = any(kw in err_msg.lower() for kw in ["quota", "1011", "resourceexhausted", "429", "exceeded"])
        if is_quota:
            friendly_msg = "Dạ Bác ơi, hạn mức cuộc gọi AI tạm thời đạt giới hạn hôm nay. Bác có thể tiếp tục nhắn tin trò chuyện cùng cháu hoặc thử lại sau ít phút nhé ạ!"
        else:
            friendly_msg = f"Đường truyền đàm thoại đang chập chờn: {err_msg}"

        await send_to_client({
            "type": "error",
            "is_quota": is_quota,
            "message": friendly_msg
        })
