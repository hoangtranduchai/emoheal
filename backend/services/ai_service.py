import os
from google import genai

def get_assistant_response(text: str) -> str:
    client = genai.Client()
    
    prompt = f"Bạn là trợ lý AI hữu ích. Trả lời câu hỏi sau bằng tiếng Việt ngắn gọn, tự nhiên và thân thiện: {text}"
    
    response = client.models.generate_content(
        model='gemini-2.5-flash',
        contents=prompt,
    )
    return response.text
