"""
Draw Things CORS Proxy
Run: python proxy.py
Tunnel: cloudflared tunnel --url http://localhost:8000
"""

import uvicorn
import httpx
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

DRAW_THINGS = "http://localhost:7860"

@app.get("/")
def health():
    return {"status": "ok"}

@app.post("/sdapi/v1/txt2img")
async def txt2img(request: Request):
    body = await request.json()
    try:
        async with httpx.AsyncClient(timeout=300.0) as client:
            resp = await client.post(f"{DRAW_THINGS}/sdapi/v1/txt2img", json=body)
            return JSONResponse(content=resp.json())
    except httpx.ConnectError:
        return JSONResponse(status_code=503, content={"error": "Draw Things에 연결할 수 없습니다. 앱이 열려 있고 API 서버가 활성화되어 있는지 확인하세요."})
    except Exception as e:
        return JSONResponse(status_code=500, content={"error": str(e)})
