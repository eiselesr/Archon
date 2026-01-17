# Roocode MCP Integration - Validated Facts

## What We Know For Sure

### The Problem
- **Roocode connection times out**: MCP error -32001: Request timed out
- **Server blocks when Roocode connects**: New StreamableHTTP sessions created, then server hangs
- **Root cause**: Hypercorn with asyncio.serve() runs single-threaded - any `/mcp` connection blocks all other requests
- **User saw green indicator once**: Connection appeared to work initially, but never tested actual tool execution

### What We've Tried (That Didn't Work)
1. **Multi-worker config in Hypercorn** - Config ignored because asyncio.serve() doesn't support workers
2. **Connection timeouts in run_hypercorn.py** - Doesn't help because the blocking happens at event loop level
3. **Health check optimizations** - Only helped with cosmetic "unhealthy" status, not the blocking issue

### Current Configuration
- **Transport**: `streamable-http` (line 619 in mcp_server.py)
- **Server**: Hypercorn with HTTP/2 ALPN support via `config.alpn_protocols = ["h2", "http/1.1"]`
- **Roocode config**: Using `mcp-remote` proxy to `http://localhost:8051/mcp --allow-http`
- **Config file**: `~/.config/Code/User/globalStorage/rooveterinaryinc.roo-cline/settings/mcp_settings.json`

### Key Files
- `python/src/mcp_server/run_hypercorn.py` - Hypercorn server config with ALPN
- `python/src/mcp_server/mcp_server.py` - MCP server implementation (line 619: transport="streamable-http")
- `docker-compose.yml` - archon-mcp service config
- `.env` - Has `MCP_HEALTH_CHECK_TIMEOUT=10`

### Architectural Facts (from README.md)
- **MCP Server supports TWO transports**: SSE or stdio (not just streamable-http)
- Server is at Port 8051 by default
- MCP is "Lightweight HTTP wrapper" for the protocol
- No direct imports between services - HTTP-based communication only

## Validated Solution
- **mcp-remote DOES support SSE transport!**
- **Default behavior**: Tries HTTP (streamable-http) first, falls back to SSE
- **Strategy flag**: `--transport sse-only` forces SSE-only (prevents streamable-http attempts)
- **Transport selection fix**: `run_hypercorn.py` now reads `TRANSPORT` env and selects `mcp.sse_app()` vs `mcp.streamable_http_app()`
- **SSE runtime change**: SSE runs under Uvicorn (HTTP/1.1) to avoid Hypercorn ASGI state errors on `/sse`
- **Instrumentation**: Added standalone ASGI wrapper `src/mcp_server/utils/asgi_debug.py`, enabled with `MCP_DEBUG=true` to log POST `/messages/` request types and SSE tool counts
- **VERIFIED**: `/sse` returns 200 text/event-stream; Roocode connects (green indicator); tools now list correctly; server remains responsive; tools are callable and execute properly
- **Notes**: Occasional `SseError: other side closed` in Roocode logs indicates reconnect behavior; not impacting tool calls

The blocking problem is SOLVED and SSE transport is stable with Uvicorn. Roocode can now run MCP tools successfully via SSE transport.

## Running Tools in Roocode
- Open Roocode chat (Cmd/Ctrl+L or "New Chat")
- Ask to perform an action (e.g., "Check the MCP server health" or "Find all projects")
- Roocode will automatically invoke the appropriate MCP tool
- Tool execution logs visible with `MCP_DEBUG=true` enabled

## References to Check When Investigating
- **README.md** - Architecture section mentions "MCP Protocol: AI clients connect via SSE or stdio"
- **mcp_server.py line 619** - Where transport is configured
- **run_hypercorn.py** - HTTP/2 ALPN setup
- **docker-compose.yml archon-mcp service** - Container environment and healthcheck

## Important Reminder
**ALWAYS update this facts file when we discover and validate new facts.** Only add facts that have been proven through investigation or testing - not speculation. This file is your memory for the Roocode integration.
