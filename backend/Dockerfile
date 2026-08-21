FROM python:3.11-slim

WORKDIR /app

# Install system deps for faster-whisper / Cài đặt thư viện hệ thống
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Create static dir for TTS output / Tạo thư mục cho file TTS
RUN mkdir -p static

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
