"""Isolate tests from credentials, cloud services and app logs / Cô lập kiểm thử."""
import logging
import os
import tempfile
from pathlib import Path
from unittest.mock import patch

import pytest

_original_directory = Path.cwd()
_test_directory = tempfile.TemporaryDirectory(prefix="emoheal-backend-tests-")
os.chdir(_test_directory.name)
os.makedirs("static", exist_ok=True)

# Import-time logger setup must not open the real project log / Không ghi log dự án.
with patch("logging.FileHandler", lambda *args, **kwargs: logging.NullHandler()), patch("os.makedirs"):
    import logger_config

# Tests must not load production .env values / Không nạp khóa và DB thật.
with patch("dotenv.load_dotenv"):
    import main


@pytest.fixture(autouse=True)
def isolate_cloud_and_files(monkeypatch):
    for key in ("GEMINI_API_KEY", "GOOGLE_API_KEY", "SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_JWT_SECRET"):
        monkeypatch.delenv(key, raising=False)
    main._registered_phones.clear()
    from services import tts_service
    tts_service._memory_cache.clear()
    monkeypatch.setattr(tts_service, "CACHE_DIR", str(Path(_test_directory.name) / "cache"))
    monkeypatch.setattr(main, "_cleanup_old_tts", lambda *args, **kwargs: None)
    async def forbid_network(*args, **kwargs):
        raise AssertionError("Unit tests must not access external services")
    monkeypatch.setattr("httpx.AsyncClient.request", forbid_network)
    yield


@pytest.fixture
def anyio_backend():
    return "asyncio"


def pytest_unconfigure(config):
    os.chdir(_original_directory)
    _test_directory.cleanup()
