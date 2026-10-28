FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app/backend

# Install system deps for faster-whisper / Cài đặt thư viện hệ thống
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

COPY requirements-runtime.txt .
RUN pip install --no-cache-dir -r requirements-runtime.txt

COPY . .

# Create static dir for TTS output / Tạo thư mục cho file TTS
RUN useradd --uid 10001 --create-home app \
    && mkdir -p static /app/logs \
    && chown -R app:app /app

USER app

EXPOSE 8000

# Render supplies PORT / Render cấp cổng qua biến môi trường.
CMD ["sh", "-c", "exec uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers"]
