import os
import jwt
from typing import Optional
from fastapi import Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from logger_config import logger

security = HTTPBearer(auto_error=False)

def get_current_user(credentials: Optional[HTTPAuthorizationCredentials] = Depends(security)) -> dict:
    """
    Xác thực người dùng tùy chọn (Optional Auth).
    - Nếu có Token: Giải mã và xác thực phiên đăng nhập Supabase.
    - Nếu không có Token (Khách trải nghiệm trước): Cấp quyền Guest an toàn, không ném lỗi 401.
    """
    if not credentials:
        logger.debug("👤 Người dùng truy cập ở chế độ Trải nghiệm trước (Guest / Anonymous)")
        return {
            "sub": "anonymous",
            "id": "anonymous",
            "role": "guest",
            "display_name": "Bác",
            "is_guest": True
        }

    token = credentials.credentials
    secret = os.getenv("SUPABASE_JWT_SECRET")
    
    if not secret:
        # Khi không có secret, giải mã payload không verify chữ ký (phục vụ môi trường dev)
        try:
            payload = jwt.decode(token, options={"verify_signature": False})
            user_id = payload.get("sub") or payload.get("id") or "anonymous"
            logger.debug(f"🔑 Xác thực người dùng (Chế độ Unverified Dev): user_id={user_id}")
            payload["is_guest"] = False
            return payload
        except Exception as e:
            logger.warning(f"❌ Giải mã Token thất bại: {e}")
            raise HTTPException(status_code=401, detail="Token không hợp lệ")

    try:
        # Supabase default algorithm is HS256
        payload = jwt.decode(token, secret, algorithms=["HS256"], audience="authenticated")
        user_id = payload.get("sub") or payload.get("id")
        logger.info(f"✅ Xác thực người dùng thành công: user_id={user_id}")
        payload["is_guest"] = False
        return payload
    except jwt.ExpiredSignatureError:
        logger.warning("❌ Token xác thực đã hết hạn")
        raise HTTPException(status_code=401, detail="Token đã hết hạn")
    except jwt.InvalidTokenError as e:
        logger.warning(f"❌ Token xác thực không hợp lệ: {e}")
        raise HTTPException(status_code=401, detail="Token không hợp lệ")

