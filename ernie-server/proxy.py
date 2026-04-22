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
    async with httpx.AsyncClient(timeout=300.0) as client:
        resp = await client.post(f"{DRAW_THINGS}/sdapi/v1/txt2img", json=body)
        return JSONResponse(content=resp.json())
