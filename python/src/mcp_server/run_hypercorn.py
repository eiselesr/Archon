"""
ASGI runner for MCP server.

- Streamable HTTP transport: Use Hypercorn with HTTP/2 (ALPN) for Roocode/mcp-remote.
- SSE transport: Use Uvicorn to avoid Hypercorn SSE response state errors.
"""
import asyncio
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from hypercorn.asyncio import serve as hypercorn_serve
from hypercorn.config import Config as HypercornConfig
import uvicorn
from src.mcp_server.mcp_server import mcp
from src.mcp_server.utils.asgi_debug import ASGIDebugWrapper


def main():
    """Run the MCP server with Hypercorn and HTTP/2 support."""
    host = "0.0.0.0"
    port = int(os.getenv("ARCHON_MCP_PORT", "8051"))

    # Get transport from environment variable
    transport = os.getenv("TRANSPORT", "streamable-http")
    print(f"🚀 Starting MCP server")
    print(f"   Host: {host}")
    print(f"   Port: {port}")
    print(f"   Transport: {transport}")

    if transport == "sse":
        # SSE transport works reliably with Uvicorn; Hypercorn has ASGI state errors for SSE
        print(f"   Using SSE transport with Uvicorn - endpoint: /sse")
        app = mcp.sse_app()
        # Optional instrumentation via env flag
        if os.getenv("MCP_DEBUG", "false").lower() in ("true", "1", "yes", "on"):
            print("   MCP_DEBUG enabled: wrapping SSE app with ASGIDebugWrapper")
            app = ASGIDebugWrapper(app)
        # Uvicorn run (HTTP/1.1 is fine for SSE)
        uvicorn.run(app, host=host, port=port, log_level="info")
    else:
        # Streamable HTTP transport with Hypercorn + HTTP/2
        print(f"   Using Streamable HTTP transport with Hypercorn - endpoint: /mcp")
        # Create Hypercorn config
        config = HypercornConfig()
        config.bind = [f"{host}:{port}"]

        # Enable HTTP/2 with ALPN negotiation
        config.alpn_protocols = ["h2", "http/1.1"]

        # Logging
        config.accesslog = "-"
        config.errorlog = "-"
        config.loglevel = "INFO"

        # Run Hypercorn
        asyncio.run(hypercorn_serve(app := mcp.streamable_http_app(), config))


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("👋 MCP server stopped by user")
    except Exception as e:
        print(f"💥 Fatal error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)