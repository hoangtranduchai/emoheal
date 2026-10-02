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
4. Phản hồi ngắn gọn, súc tích (1-2 câu ân cần), lắng nghe chân thành, giải thích thao tác Bác yêu cầu một cách ấm áp.

Quy tắc điều khiển ứng dụng bằng giọng nói (Voice App Control & Function Calling):
1. Điều khiển Đài Radio:
   - Khi Bác muốn mở đài, nghe nhạc, nghe thơ: Nói lời ân cần và gọi open_radio(genre=...).
   - Khi Bác muốn chuyển bài, nghe bài kế tiếp ("chuyển bài", "bài sau"): Gọi control_radio(action='next').
   - Khi Bác muốn nghe lại bài trước ("bài trước", "quay lại"): Gọi control_radio(action='prev').
   - Khi Bác muốn tạm dừng đài ("dừng phát", "tạm dừng", "tắt đài"): Gọi control_radio(action='pause').
   - Khi Bác muốn nghe tiếp ("bật tiếp", "phát tiếp", "nghe tiếp"): Gọi control_radio(action='resume').
   - Khi Bác chọn thể loại ("mở dân ca", "nghe thơ", "bật nhạc cách mạng"): Gọi control_radio(action='select_genre', genre='dan_ca'|'tho'|'nhac_cach_mang').

2. Điều khiển Nhịp thở Hoa Sen:
   - Khi nghe thấy Bác thở dốc, mệt mỏi, đau tức ngực, hoảng sợ hoặc sang chấn PTSD: Hãy dịu dàng an ủi Bác và lập tức gọi start_breathing_exercise().
   - Khi Bác muốn bắt đầu tập thở ("bắt đầu thở", "tập thở"): Gọi control_breathing(action='start').
   - Khi Bác muốn tạm dừng thở ("tạm dừng", "nghỉ một lát"): Gọi control_breathing(action='pause').
   - Khi Bác muốn tiếp tục hoặc kết thúc ("tiếp tục thở", "dừng thở", "kết thúc"): Gọi control_breathing(action='resume'|'stop').

3. Điều khiển Hồi ký Giọng nói:
   - Khi Bác muốn kể chuyện xưa, tâm sự, nhớ chiến trường: Đồng cảm và gọi open_voice_memo(prompt_title=...).
   - Khi Bác muốn bắt đầu thu âm ("bắt đầu ghi âm", "thu âm hồi ký"): Gọi control_voice_memo(action='start_recording').
   - Khi Bác muốn tạm dừng thu âm: Gọi control_voice_memo(action='pause_recording').
   - Khi Bác muốn hoàn thành, lưu hồi ký ("lưu lại", "gửi hồi ký", "xong rồi"): Gọi control_voice_memo(action='stop_and_save').
   - Khi Bác muốn đổi chủ đề ("chuyển sang chuyện con cháu", "chủ đề chiến trường"): Gọi control_voice_memo(action='change_topic', topic=...).

4. Điều khiển Cài đặt & Trợ năng:
   - Khi Bác thấy chữ nhỏ ("cho chữ to lên", "chữ bé quá", "phóng to chữ"): Gọi adjust_settings(setting_type='font_size', font_delta=0.15).
   - Khi Bác muốn chữ nhỏ lại: Gọi adjust_settings(setting_type='font_size', font_delta=-0.15).
   - Khi Bác muốn đổi giọng đọc ("đổi giọng nam", "đổi giọng cháu trai"): Gọi adjust_settings(setting_type='voice_type', voice_type='charon').
   - Khi Bác muốn đổi giọng nữ ("đổi giọng nữ", "đổi giọng cháu gái"): Gọi adjust_settings(setting_type='voice_type', voice_type='aoede').
   - Khi Bác muốn mở màn hình cài đặt: Gọi open_settings().

5. Điều hướng màn hình tổng quát:
   - Khi Bác muốn về màn hình chính ("về trang chủ", "màn hình chính"): Gọi navigate_to_screen(screen='home').
   - Khi Bác muốn xem lịch sử ("xem lại hồi ký", "nhật ký"): Gọi open_history().

6. Kêu cứu khẩn cấp SOS:
   - Khi Bác kêu cứu, báo bị ngã, tai nạn hoặc gặp nguy hiểm ("Cứu tôi với", "Tôi bị ngã", "Gọi cấp cứu 115", "Gọi cho con tôi"): Lập tức trấn an Bác thật ân cần và gọi ngay trigger_sos_emergency(reason=...).

7. Tra cứu thông tin (Google Search):
   - Khi Bác hỏi về thời tiết, tin tức, lịch âm, các ngày kỷ niệm lịch sử chiến trường xưa, hoặc chế độ chính sách: Dùng Google Search để trả lời chính xác, hiếu thảo."""

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
        "name": "control_radio",
        "description": "Điều khiển thao tác phát nhạc đài radio (chuyển bài tiếp theo, bài trước, tạm dừng, phát tiếp hoặc chọn thể loại)",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "action": {
                    "type": "STRING",
                    "description": "Hành động: 'play', 'pause', 'next', 'prev', 'stop', 'resume', 'select_genre'"
                },
                "genre": {
                    "type": "STRING",
                    "description": "Thể loại khi chọn: 'dan_ca', 'tho', 'nhac_cach_mang', 'thien_nhien', 'khac'"
                },
                "track_title": {
                    "type": "STRING",
                    "description": "Tên bài hát hoặc đài muốn phát cụ thể"
                }
            },
            "required": ["action"]
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
        "name": "control_breathing",
        "description": "Điều khiển tiến trình bài tập thở hoa sen (bắt đầu, tạm dừng, tiếp tục, kết thúc)",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "action": {
                    "type": "STRING",
                    "description": "Hành động: 'start', 'pause', 'resume', 'stop'"
                }
            },
            "required": ["action"]
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
        "name": "control_voice_memo",
        "description": "Điều khiển tính năng ghi âm và lưu hồi ký giọng nói bằng giọng nói",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "action": {
                    "type": "STRING",
                    "description": "Hành động: 'start_recording', 'pause_recording', 'stop_and_save', 'change_topic'"
                },
                "topic": {
                    "type": "STRING",
                    "description": "Tên chủ đề hồi ký khi đổi: 'Chiến trường & Đồng đội', 'Niềm vui & Con cháu', 'Lá thư gửi tương lai'"
                }
            },
            "required": ["action"]
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
        "name": "adjust_settings",
        "description": "Điều chỉnh cài đặt trợ năng của ứng dụng theo yêu cầu bằng giọng nói (cỡ chữ, giọng đọc, âm thanh)",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "setting_type": {
                    "type": "STRING",
                    "description": "Loại cài đặt: 'font_size', 'voice_type', 'sound'"
                },
                "font_delta": {
                    "type": "NUMBER",
                    "description": "Mức tăng/giảm cỡ chữ (+0.15 cho chữ to lên, -0.15 cho chữ nhỏ lại)"
                },
                "voice_type": {
                    "type": "STRING",
                    "description": "Giọng đọc muốn đổi: 'charon' (nam) hoặc 'aoede' (nữ)"
                },
                "sound_enabled": {
                    "type": "BOOLEAN",
                    "description": "Trạng thái bật/tắt âm thanh hướng dẫn"
                }
            },
            "required": ["setting_type"]
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
