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
- **ISSUE FOUND**: Setting transport="sse" in mcp_server.py doesn't work because:
  - FastMCP instance created at module import time (no transport parameter)
  - run_hypercorn.py calls `mcp.streamable_http_app()` which is hardcoded
  - TRANSPORT env var set in docker-compose.yml but not being used
  - Need to update run_hypercorn.py to read TRANSPORT env var and call correct app method
- **FIX APPLIED**: Updated run_hypercorn.py to read TRANSPORT env var and call `mcp.sse_app()` when transport=sse
- **VERIFIED**: /sse endpoint now returns HTTP 200 with content-type: text/event-stream
- **Roocode Config**: Updated to use http://localhost:8051/sse with --transport sse-only flag
- **TESTED WITH ROOCODE**: 
  - ✅ Connection established successfully (NO TIMEOUT!)
  - ✅ Green indicator in Roocode
  - ✅ SSE messages flowing back and forth
  - ✅ Server stays responsive (dashboard still healthy)
  - ⚠️ Some response formatting issues to debug (tools response malformed)

The blocking problem is SOLVED! SSE transport works reliably without event loop hangs.

## References to Check When Investigating
- **README.md** - Architecture section mentions "MCP Protocol: AI clients connect via SSE or stdio"
- **mcp_server.py line 619** - Where transport is configured
- **run_hypercorn.py** - HTTP/2 ALPN setup
- **docker-compose.yml archon-mcp service** - Container environment and healthcheck

## Important Reminder
**ALWAYS update this facts file when we discover and validate new facts.** Only add facts that have been proven through investigation or testing - not speculation. This file is your memory for the Roocode integration.
