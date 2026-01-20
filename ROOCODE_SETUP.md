# Roocode / Remote MCP Client Setup

This document describes the setup for connecting Roocode and other remote MCP clients to Archon using SSE transport.

## Status

✅ **Working:** Roocode and other remote MCP clients can connect to Archon MCP server via SSE transport.

## Issue Background

**GitHub Issue:** [#920 - MCP Server Connection Timeout with mcp-remote Clients](https://github.com/coleam00/Archon/issues/920)

### Original Problem
The original Archon MCP server used FastMCP's `streamable-http` transport with Hypercorn, which caused event-loop blocking and timeouts when remote clients connected. The connection would appear to work initially but block all other requests.

### Root Cause Discovered (January 2026)
**MCP library version 1.12.2 had a broken SSE implementation:**
- SSE connections would hang indefinitely without sending response headers
- Threading lock (`threading.Lock()`) in async lifespan caused potential deadlocks
- FastMCP API changes made old initialization parameters incompatible

### Solution
1. **Upgrade to MCP 1.25.0** - Fixed SSE implementation
2. **Update FastMCP initialization** - Remove deprecated `description`, `host`, `port` parameters
3. **Replace threading.Lock with asyncio.Lock** - Prevent async deadlocks
4. **Use Uvicorn for SSE transport** - Non-blocking I/O for long-lived connections

## Applied Configuration

### 1. SSE Transport Selection (`python/src/mcp_server/run_hypercorn.py`)

**Configuration:**
```python
if transport == "sse":
    # SSE via Uvicorn (non-blocking, handles long-lived connections)
    app = mcp.sse_app()
    uvicorn_config = uvicorn.Config(
        app,
        host="0.0.0.0",
        port=port,
        log_level=log_level_lower,
    )
    server = uvicorn.Server(uvicorn_config)
else:
    # Streamable-HTTP via Hypercorn (for HTTP/2 support)
    app = mcp.streamable_http_app()
```

**Why:** SSE eliminates event-loop blocking issues because it doesn't require streaming binary protocols. Uvicorn handles SSE connections properly without hanging. FastMCP provides both `sse_app()` and `streamable_http_app()` for flexibility.

**Status:** ✅ Applied - reads `TRANSPORT` env variable from docker-compose.yml

### 2. Docker Compose Environment (`docker-compose.yml`)

**archon-mcp service:**
```yaml
environment:
  - TRANSPORT=sse
  - MCP_DEBUG=true
```

**Why:** `TRANSPORT=sse` selects SSE transport; `MCP_DEBUG=true` enables ASGI instrumentation logging.

**Status:** ✅ Applied in archon-mcp service environment

### 3. Health Check Timeout (`docker-compose.yml` and `.env`)

**docker-compose.yml:**
```yaml
- MCP_HEALTH_CHECK_TIMEOUT=${MCP_HEALTH_CHECK_TIMEOUT:-10}
```

**.env:**
```
MCP_HEALTH_CHECK_TIMEOUT=10
```

**Why:** Backend health checks can timeout if the MCP service is slow to respond. 10s timeout reduces false "UNHEALTHY" status.

**Status:** ✅ Applied in both files

## Roocode Configuration

**File:** `~/.config/Code/User/globalStorage/rooveterinaryinc.roo-cline/settings/mcp_settings.json`

```json
{
  "mcpServers": {
    "archon": {
      "command": "npx",
      "args": [
        "mcp-remote",
        "http://localhost:8051/sse",
        "--allow-http",
        "--transport",
        "sse-only"
      ]
    }
  }
}
```

**Key points:**
- `--transport sse-only` forces SSE transport (avoids fallback to streamable-http)
- Endpoint is `/sse` (not `/mcp`)
- `--allow-http` permits non-HTTPS connections for local development

## Testing Tools

### Running a Tool in Roocode

1. **Open a new Roocode chat** (Cmd/Ctrl + L or click "New Chat")
2. **Ask Roocode to use a tool**, for example:
   - `Check the health of the MCP server`
   - `Find all projects`
   - `Search the knowledge base for "authentication"`
3. **Roocode will automatically invoke the appropriate MCP tool** and display the result

### Monitor Tool Execution

In a terminal, watch the MCP logs while running a tool:

```bash
docker compose logs -f archon-mcp 2>&1 | grep --line-buffered -E "DEBUG|tool|SSE|POST|session"
```

With `MCP_DEBUG=true` enabled, you'll see:
- `[MCP DEBUG] SSE tools count=16` - Shows tool list was sent
- `[MCP DEBUG] POST /messages/ type=...` - Shows MCP requests coming in
- Tool execution logs from the service handlers

### Available Tools

Access these tools through Roocode chat or the MCP settings panel:

- `health_check` - Server health and uptime
- `archon:find_projects` - List and search projects
- `archon:find_tasks` - List and search tasks
- `archon:find_documents` - List and search documents
- `archon:rag_search_knowledge_base` - Search knowledge base
- `archon:rag_search_code_examples` - Find code snippets
- `archon:rag_get_available_sources` - List knowledge sources

## Health Checks (No IDE Required)

Run the included script to verify all systems are working:

```bash
bash ./scripts/check_mcp_health.sh
```

This checks:
- MCP server responds to `/health`
- Backend can reach MCP (with timeout)
- `mcp-remote` can establish a proxy
- Backend reports "running" status
- Tools are accessible

## Verifying After Upstream Updates

If the repo is updated and things break:

1. **Check if patches are still applied:**
   ```bash
   bash ./scripts/check_mcp_patches.sh
   ```
   This verifies all three patches are in place.

2. **Run health checks:**
   ```bash
   bash ./scripts/check_mcp_health.sh
   ```

3. **If patches are missing:**
   - Reapply manually (see sections above), OR
   - Cherry-pick patches from git history (if committed)

4. **Restart services:**
   ```bash
   docker compose down
   docker compose build archon-mcp --no-cache
   docker compose up -d
   ```

## Quick Reference: Manual Verification

### Check MCP is running
```bash
curl -s http://localhost:8051/health | jq .success
```
Expected: `true`

### Check backend sees MCP as healthy
```bash
curl -s http://localhost:8181/api/mcp/status | jq -r .status
```
Expected: `running` (not "unhealthy")

### Test remote client connectivity
```bash
timeout 10 mcp-remote http://localhost:8051/sse --allow-http --transport sse-only
```
Expected output includes:
- "Connected to remote server using SSEClientTransport"
- "Proxy established successfully"

### Check SSE endpoint is available
```bash
curl -i http://localhost:8051/sse 2>&1 | grep -i "text/event-stream"
```
Expected: `content-type: text/event-stream`

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| SSE connections hang, no response | MCP library version too old (< 1.25.0) | Update `python/pyproject.toml` to `mcp==1.25.0`, rebuild: `docker compose build --no-cache archon-mcp` |
| FastMCP initialization error about 'description' | Using old FastMCP API with new library | Remove `description`, `host`, `port` from `FastMCP()` constructor |
| Roocode timeout on connection | SSE transport not selected | Verify `TRANSPORT=sse` in `docker-compose.yml` and `--transport sse-only` in Roocode config |
| Server deadlocks on concurrent connections | Using threading.Lock in async code | Replace `threading.Lock()` with `asyncio.Lock()`, use `async with lock` |
| Backend shows "unhealthy" but MCP is responding | Health check timeout too short or endpoint slow | Update both `docker-compose.yml` AND `.env` to `MCP_HEALTH_CHECK_TIMEOUT=10` |
| Backend shows "unhealthy" after restart | Changes to docker-compose.yml ignored | Check `.env` file for conflicting value of `MCP_HEALTH_CHECK_TIMEOUT` |
| `/sse` returns 503 or hangs | Uvicorn not running for SSE transport | Check `run_hypercorn.py` reads TRANSPORT env and uses `mcp.sse_app()` |
| Roocode can't connect | `mcp_settings.json` path wrong or endpoint incorrect | Verify file and use `/sse` endpoint with `--allow-http` flag |
| Tools not appearing in Roocode | Tools not registered or ListToolsRequest fails | Run `docker compose logs archon-mcp` with `MCP_DEBUG=true` to see request/response logs |

## Implementation Notes

- **MCP Library Version:** 1.25.0 (critical - earlier versions have broken SSE)
- **Transport selection:** Controlled via `TRANSPORT` environment variable (default: `sse`)
- **Uvicorn for SSE:** Non-blocking I/O suitable for long-lived connections
- **Hypercorn for streamable-http:** Available if needed, but SSE is preferred for remote clients
- **Async lock usage:** Uses `asyncio.Lock()` in lifespan to prevent deadlocks with concurrent connections
- **FastMCP initialization:** Only passes `name`, `instructions`, `lifespan` (no `description`, `host`, `port`)
- **Instrumentation:** `MCP_DEBUG=true` enables ASGI wrapper logging of MCP requests and tool counts
- **Health endpoint:** `/health` returns JSON with server status, service dependencies, and uptime

## Version Requirements

**Critical:** MCP library must be >= 1.25.0 for SSE to work properly.

In `python/pyproject.toml`:
```toml
mcp = [
    "mcp==1.25.0",  # Earlier versions (e.g., 1.12.2) have broken SSE
    ...
]
```

