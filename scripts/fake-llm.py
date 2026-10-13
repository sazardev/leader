#!/usr/bin/env python3
"""Servidor falso de LLM para las pruebas del agente (scripts/test-agent.sh): habla los protocolos de Ollama y de la API
compatible con OpenAI, con streaming, sin ningún modelo real. Uso: fake-llm.py PUERTO

Ollama:  GET /api/version · GET /api/tags · GET /api/ps · POST /api/chat (NDJSON) · POST /api/pull (NDJSON)
OpenAI:  GET /v1/models · POST /v1/chat/completions (SSE)
Auxiliar: GET /__last devuelve el último cuerpo y las cabeceras recibidas (para comprobar num_ctx, Authorization...).
Modelo "missing" → 404 con el error que da Ollama; modelo "slow" → tarda 3 s.
"""
import json, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LAST = {}

def reply_for(system, prompt):
    text = system + "\n" + prompt
    if "TASK review" in text or "OUTPUT, one finding per line" in text:
        return "L2|warn|magic number: name it\nL3|info|consider an early return"
    if "TASK explain" in text:
        return "It adds two numbers.\n\n- no overflow check"
    return "```go\nfunc Add(a, b int) int {\n\treturn a + b\n}\n```"

class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    def log_message(self, *a): pass

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)

    def _stream_start(self, ctype):
        self.send_response(200); self.send_header("Content-Type", ctype); self.end_headers()

    def _line(self, s):
        self.wfile.write((s + "\n").encode()); self.wfile.flush()

    def do_GET(self):
        p = self.path
        if p == "/api/version": return self._json(200, {"version": "0.5.0-fake"})
        if p == "/api/tags":
            return self._json(200, {"models": [
                {"name": "qwen2.5-coder:7b", "size": 4_700_000_000, "details": {"parameter_size": "7.6B", "quantization_level": "Q4_K_M"}},
                {"name": "qwen2.5-coder:1.5b", "size": 1_000_000_000, "details": {"parameter_size": "1.5B", "quantization_level": "Q4_K_M"}},
                {"name": "hermes3:8b", "size": 4_900_000_000, "details": {"parameter_size": "8.0B", "quantization_level": "Q4_0"}}]})
        if p == "/api/ps": return self._json(200, {"models": [{"name": "qwen2.5-coder:7b", "size": 5_000_000_000, "size_vram": 5_000_000_000}]})
        if p == "/v1/models": return self._json(200, {"object": "list", "data": [{"id": "fake-gguf"}, {"id": "fake-small"}]})
        if p == "/__last": return self._json(200, LAST)
        self._json(404, {"error": "not found"})

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        try: body = json.loads(raw or b"{}")
        except Exception: body = {}
        LAST.clear(); LAST.update({"path": self.path, "body": body, "authorization": self.headers.get("Authorization")})
        msgs = body.get("messages") or [{}, {}]
        system = next((m.get("content", "") for m in msgs if m.get("role") == "system"), "")
        prompt = next((m.get("content", "") for m in msgs if m.get("role") == "user"), "")
        model = body.get("model", "")

        if self.path == "/api/pull":
            self._stream_start("application/x-ndjson")
            for s in ({"status": "pulling manifest"}, {"status": "downloading", "total": 100, "completed": 30},
                      {"status": "downloading", "total": 100, "completed": 100}, {"status": "success"}):
                self._line(json.dumps(s)); time.sleep(0.05)
            return
        if self.path == "/api/chat":
            if model == "missing": return self._json(404, {"error": f'model "{model}" not found, try pulling it first'})
            if model == "slow": time.sleep(3)
            self._stream_start("application/x-ndjson")
            text = reply_for(system, prompt)
            for i in range(0, len(text), 12):
                self._line(json.dumps({"model": model, "message": {"role": "assistant", "content": text[i:i + 12]}, "done": False}))
            self._line(json.dumps({"model": model, "message": {"role": "assistant", "content": ""}, "done": True,
                                   "prompt_eval_count": 321, "eval_count": 45, "total_duration": 1_500_000_000}))
            return
        if self.path == "/v1/chat/completions":
            if body.get("model") == "missing": return self._json(404, {"error": {"message": "model 'missing' not found"}})
            self._stream_start("text/event-stream")
            text = reply_for(system, prompt)
            for i in range(0, len(text), 12):
                self._line("data: " + json.dumps({"choices": [{"delta": {"content": text[i:i + 12]}}]})); self._line("")
            self._line("data: " + json.dumps({"choices": [], "usage": {"prompt_tokens": 210, "completion_tokens": 33}})); self._line("")
            self._line("data: [DONE]")
            return
        self._json(404, {"error": "not found"})

if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
