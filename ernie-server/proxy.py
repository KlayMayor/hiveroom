"""
Draw Things CORS Proxy — async job queue (no external dependencies)
Run: python3 proxy.py
Tunnel: ssh -R 80:localhost:8000 nokey@localhost.run

POST /sdapi/v1/txt2img  → returns {"job_id":"..."} immediately, generates in background
GET  /job/<job_id>      → returns {"status":"pending"|"done"|"error", "image":base64, "error":str}
GET  /sdapi/v1/progress → forwarded directly to Draw Things (queue detection)
"""

import json
import threading
import time
import uuid
import urllib.request
import urllib.error
from http.server import HTTPServer, BaseHTTPRequestHandler

DRAW_THINGS = "http://localhost:7860"
JOB_TTL     = 600  # seconds — jobs older than this are purged

_jobs      = {}   # {job_id: {status, image, error, created}}
_jobs_lock = threading.Lock()


def _purge_old_jobs():
    cutoff = time.time() - JOB_TTL
    with _jobs_lock:
        stale = [k for k, v in _jobs.items() if v["created"] < cutoff]
        for k in stale:
            del _jobs[k]


def _run_generation(job_id, body):
    req = urllib.request.Request(
        DRAW_THINGS + "/sdapi/v1/txt2img",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=400) as resp:
            data = resp.read()
        result = json.loads(data)
        image  = (result.get("images") or [None])[0]
        if not image:
            raise ValueError("Draw Things returned no image")
        with _jobs_lock:
            _jobs[job_id].update(status="done", image=image)
        print(f"[job {job_id}] done")
    except Exception as e:
        with _jobs_lock:
            _jobs[job_id].update(status="error", error=str(e))
        print(f"[job {job_id}] error: {e}")


class Proxy(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(fmt % args)

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, ngrok-skip-browser-warning")

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(200)
        self._cors()
        self.end_headers()

    def do_GET(self):
        # Job status endpoint
        if self.path.startswith("/job/"):
            _purge_old_jobs()
            job_id = self.path[5:].strip("/")
            with _jobs_lock:
                job = _jobs.get(job_id)
            if not job:
                self._json(404, {"error": "job not found"})
                return
            self._json(200, {
                "status": job["status"],
                "image":  job.get("image"),
                "error":  job.get("error"),
            })
            return

        # Forward everything else (e.g. /sdapi/v1/progress) to Draw Things
        req = urllib.request.Request(DRAW_THINGS + self.path)
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = resp.read()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self._cors()
            self.end_headers()
            self.wfile.write(data)
        except Exception:
            self._json(200, {"status": "ok"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body   = self.rfile.read(length)

        if self.path == "/sdapi/v1/txt2img":
            # Async: start generation in background, return job_id immediately
            job_id = uuid.uuid4().hex[:10]
            with _jobs_lock:
                _jobs[job_id] = {
                    "status":  "pending",
                    "image":   None,
                    "error":   None,
                    "created": time.time(),
                }
            threading.Thread(
                target=_run_generation, args=(job_id, body), daemon=True
            ).start()
            print(f"[job {job_id}] submitted")
            self._json(200, {"job_id": job_id})
            return

        # Other POSTs: forward directly
        req = urllib.request.Request(
            DRAW_THINGS + self.path,
            data=body,
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=300) as resp:
                data = resp.read()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self._cors()
            self.end_headers()
            self.wfile.write(data)
        except urllib.error.URLError as e:
            self._json(503, {"error": f"Draw Things 연결 실패: {e.reason}"})
        except Exception as e:
            self._json(500, {"error": str(e)})


if __name__ == "__main__":
    server = HTTPServer(("", 8000), Proxy)
    print("Proxy running on http://localhost:8000")
    print(f"Forwarding to {DRAW_THINGS}")
    server.serve_forever()
