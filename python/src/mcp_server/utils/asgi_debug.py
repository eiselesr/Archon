import json
from typing import Callable, Awaitable, Dict, Any

class ASGIDebugWrapper:
    """
    Lightweight ASGI wrapper for instrumentation.

    - Logs POST /messages/ request bodies (to inspect MCP request types)
    - Parses SSE (/sse) response chunks and logs tool counts when present
    """

    def __init__(self, inner_app: Callable):
        self.inner_app = inner_app

    async def __call__(self, scope: Dict[str, Any], receive: Callable[[], Awaitable[Dict[str, Any]]], send: Callable[[Dict[str, Any]], Awaitable[None]]):
        if scope.get("type") == "http":
            path = scope.get("path", "")
            method = scope.get("method", "")

            # Instrument POST /messages/ (MCP requests)
            if path == "/messages/" and method == "POST":
                body_accumulator = b""

                async def recv_wrapper():
                    nonlocal body_accumulator
                    msg = await receive()
                    if msg.get("type") == "http.request":
                        body_accumulator += msg.get("body", b"")
                    return msg

                async def send_passthrough(message: Dict[str, Any]):
                    await send(message)

                try:
                    await self.inner_app(scope, recv_wrapper, send_passthrough)
                finally:
                    try:
                        payload_text = (body_accumulator or b"{}" ).decode("utf-8", errors="ignore")
                        payload = json.loads(payload_text)
                        req_type = None
                        if isinstance(payload, dict):
                            # FastMCP lowlevel uses request objects; log keys for quick inspection
                            req_type = payload.get("type") or payload.get("method") or payload.get("id")
                            print(f"[MCP DEBUG] POST /messages/ type={req_type} keys={list(payload.keys())}")
                    except Exception:
                        pass
                return

            # Instrument SSE GET /sse response stream
            if path == "/sse" and method == "GET":
                async def send_wrapper(message: Dict[str, Any]):
                    if message.get("type") == "http.response.body":
                        chunk = message.get("body", b"")
                        try:
                            text = chunk.decode("utf-8", errors="ignore")
                            for line in text.splitlines():
                                if line.startswith("data:"):
                                    data_str = line[len("data:"):].strip()
                                    try:
                                        obj = json.loads(data_str)
                                        if isinstance(obj, dict):
                                            # Look for tools arrays either directly or within result
                                            if "result" in obj and isinstance(obj["result"], dict):
                                                res = obj["result"]
                                                if "tools" in res and isinstance(res["tools"], list):
                                                    print(f"[MCP DEBUG] SSE tools count={len(res['tools'])}")
                                            elif "tools" in obj and isinstance(obj["tools"], list):
                                                print(f"[MCP DEBUG] SSE tools (direct) count={len(obj['tools'])}")
                                    except Exception:
                                        pass
                        except Exception:
                            pass
                    await send(message)

                await self.inner_app(scope, receive, send_wrapper)
                return

        # Default passthrough
        await self.inner_app(scope, receive, send)
