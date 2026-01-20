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

### Root Cause Discovered
- **MCP library version 1.12.2 had broken SSE implementation** - SSE connections would hang indefinitely, never sending response headers
- **Threading lock in async context** - Used `threading.Lock()` instead of `asyncio.Lock()` causing potential deadlocks in lifespan context manager
- **FastMCP API changed** - Newer versions no longer accept `description`, `host`, `port` parameters in constructor

### Solution Applied
1. **Upgraded MCP library from 1.12.2 to 1.25.0** (`python/pyproject.toml`)
   - Fixed SSE implementation that was causing connection hangs
   - SSE connections now properly establish and maintain streaming responses
   
2. **Updated FastMCP initialization** (`python/src/mcp_server/mcp_server.py` line ~329)
   - Removed deprecated parameters: `description`, `host`, `port`
   - Now only passes: `name`, `instructions`, `lifespan`
   
3. **Fixed async lock usage** (`python/src/mcp_server/mcp_server.py` line ~67)
   - Replaced `threading.Lock()` with `asyncio.Lock()` via `get_init_lock()` helper
   - Changed `with _initialization_lock:` to `async with lock:` in lifespan
   - Prevents deadlocks when multiple SSE connections initialize concurrently

4. **Transport configuration** (`run_hypercorn.py`)
   - SSE runs under Uvicorn (HTTP/1.1) - non-blocking I/O for long-lived connections
   - Streamable-HTTP available via Hypercorn with HTTP/2 support (not recommended for remote clients)
   - Transport selected via `TRANSPORT` env variable in docker-compose.yml

5. **Instrumentation**: ASGI wrapper `src/mcp_server/utils/asgi_debug.py` enabled with `MCP_DEBUG=true`

### Verification Results
- ✅ `/sse` endpoint responds properly with streaming connection
- ✅ mcp-remote establishes proxy successfully
- ✅ Roocode connects with green indicator
- ✅ Tools list correctly and execute without blocking
- ✅ Server remains responsive to concurrent connections
- ✅ Health checks pass consistently

The blocking problem is SOLVED. SSE transport works reliably with MCP 1.25.0 + Uvicorn. Roocode can now run MCP tools successfully.

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
