import logging
import os
import sys

def setup_logger(name: str = "emoheal", log_level: str = "INFO") -> logging.Logger:
    """
    Setup structured, colorized, and timestamped logger for EmoHeal Backend.
    Cấu hình bộ ghi log tập trung có màu sắc, mốc thời gian cho Backend.
    """
    level = getattr(logging, os.getenv("LOG_LEVEL", log_level).upper(), logging.INFO)
    logger = logging.getLogger(name)
    logger.setLevel(level)

    # Avoid adding duplicate handlers if already configured / Tránh gắn trùng lặp handler
    if logger.handlers:
        return logger

    # 1. Console Handler (Màu sắc trong terminal)
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(level)

    formatter = logging.Formatter(
        fmt="[%(asctime)s] [%(levelname)s] [%(name)s]: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)

    # 2. File Handler (Lưu file nhật ký vào thư mục logs/)
    try:
        log_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "logs")
        os.makedirs(log_dir, exist_ok=True)
        file_path = os.path.join(log_dir, "backend.log")
        file_handler = logging.FileHandler(file_path, encoding="utf-8")
        file_handler.setLevel(level)
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)
    except Exception as e:
        logger.warning(f"Không thể khởi tạo file log tại logs/backend.log: {e}")

    # Set root logger level as well / Đồng bộ cấp độ log gốc
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING) # Giảm trùng lặp với custom middleware

    return logger

# Singleton backend logger instance
logger = setup_logger("emoheal")
