#!/usr/bin/env python3
"""
Draw Things WebSocket Proxy (no CORS preflight)
Install: pip3 install websockets
Run:     python3 ws_proxy.py
Tunnel:  ssh -R 80:localhost:8765 nokey@localhost.run
"""

import asyncio
import json
import urllib.request
import urllib.error
import websockets

DRAW_THINGS = "http://localhost:7860"
PORT = 8765


async def handle(websocket):
    async for message in websocket:
        try:
            data = json.loads(message)
            body = json.dumps({
                "prompt":    data.get("prompt", ""),
                "steps":     data.get("steps", 9),
                "width":     data.get("width", 640),
                "height":    data.get("height", 640),
                "cfg_scale": data.get("cfg_scale", 1),
            }).encode()

            req = urllib.request.Request(
                f"{DRAW_THINGS}/sdapi/v1/txt2img",
                data=body,
                headers={"Content-Type": "application/json"},
            )
            with urllib.request.urlopen(req, timeout=300) as resp:
                result = json.loads(resp.read())

            await websocket.send(json.dumps({"success": True, "data": result}))

        except urllib.error.URLError as e:
            await websocket.send(json.dumps({
                "success": False,
                "error": f"Draw Things 연결 실패: {e.reason}. API 서버가 활성화되어 있는지 확인하세요."
            }))
        except Exception as e:
            await websocket.send(json.dumps({"success": False, "error": str(e)}))


async def main():
    print(f"WebSocket proxy  →  ws://localhost:{PORT}")
    print(f"Forwarding to      {DRAW_THINGS}")
    async with websockets.serve(handle, "0.0.0.0", PORT):
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
