import os
import jwt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

security = HTTPBearer()

def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)):
    token = credentials.credentials
    secret = os.getenv("SUPABASE_JWT_SECRET")
    
    if not secret:
        # Without a secret, we only decode to extract information without signature validation
        try:
            return jwt.decode(token, options={"verify_signature": False})
        except jwt.DecodeError:
            raise HTTPException(status_code=401, detail="Token không hợp lệ")

    try:
        # Supabase default algorithm is HS256
        payload = jwt.decode(token, secret, algorithms=["HS256"], audience="authenticated")
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token đã hết hạn")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Token không hợp lệ")
