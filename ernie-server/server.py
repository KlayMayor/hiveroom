"""
ERNIE-Image-Turbo 로컬 API 서버
실행: python server.py
접속: http://127.0.0.1:8000
"""

import io
import base64
import torch
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# ── 앱 초기화 ──────────────────────────────────────────
app = FastAPI(title="ERNIE-Image-Turbo Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

# ── 모델 로드 (서버 시작 시 1회) ───────────────────────
print("=" * 50)
print("모델 로드 중... 처음 실행 시 약 16GB 다운로드")
print("=" * 50)

try:
    from diffusers import ERNIEImagePipeline

    pipe = ERNIEImagePipeline.from_pretrained(
        "baidu/ERNIE-Image-Turbo",
        torch_dtype=torch.bfloat16,
    )

    if torch.backends.mps.is_available():
        pipe = pipe.to("mps")
        device_name = "MPS (Apple Silicon GPU)"
    else:
        # MPS 불가 시 CPU 오프로드로 메모리 절약
        pipe.enable_sequential_cpu_offload()
        device_name = "CPU (offload mode)"

    print(f"✅ 모델 로드 완료 — {device_name}")

except Exception as e:
    print(f"❌ 모델 로드 실패: {e}")
    raise

# ── 요청 스키마 ─────────────────────────────────────────
class GenerateRequest(BaseModel):
    prompt: str
    steps: int = 8          # Turbo = 8스텝으로 충분
    width: int = 1024
    height: int = 1024

# ── 엔드포인트 ──────────────────────────────────────────
@app.get("/")
def health():
    return {"status": "ok", "model": "ERNIE-Image-Turbo"}

@app.post("/generate")
async def generate(req: GenerateRequest):
    if not req.prompt.strip():
        raise HTTPException(status_code=400, detail="prompt가 비어 있어요.")
    try:
        result = pipe(
            req.prompt,
            num_inference_steps=req.steps,
            width=req.width,
            height=req.height,
        )
        image = result.images[0]

        buf = io.BytesIO()
        image.save(buf, format="PNG")
        b64 = base64.b64encode(buf.getvalue()).decode()

        return {"image": b64, "mimeType": "image/png"}

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ── 실행 ────────────────────────────────────────────────
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
