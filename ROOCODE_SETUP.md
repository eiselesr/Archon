# Roocode / Remote MCP Client Setup

This document describes the setup for connecting Roocode and other remote MCP clients to Archon, including patches applied for HTTP/2 compatibility.

## Status

✅ **Working:** Roocode, mcp-remote, and other remote MCP clients can connect to Archon MCP server.

## Issue Background

**GitHub Issue:** [#920 - MCP Server Connection Timeout with mcp-remote Clients](https://github.com/coleam00/Archon/issues/920)

The Archon MCP server uses FastMCP's `streamable-http` transport, which requires HTTP/2 negotiation via ALPN protocols. The original implementation used Uvicorn (HTTP/1.1 only), causing remote clients like `mcp-remote` and Roocode to timeout.

**Solution:** Use Hypercorn instead of Uvicorn, which provides native HTTP/2 support.

## Applied Patches

### 1. Enable HTTP/2 in Hypercorn (`python/src/mcp_server/run_hypercorn.py`)

```python
# Enable HTTP/2 with ALPN negotiation
config.alpn_protocols = ["h2", "http/1.1"]
```

**Why:** ALPN allows clients to negotiate HTTP/2 during the TLS handshake (or cleartext h2c). Without this, remote MCP clients cannot establish proper streaming connections.

**Status:** ✅ Applied in `run_hypercorn.py` (lines ~24-26)

### 2. Increase Backend Health Check Timeout (`docker-compose.yml` and `.env`)

**docker-compose.yml:**
```yaml
- MCP_HEALTH_CHECK_TIMEOUT=${MCP_HEALTH_CHECK_TIMEOUT:-10}
```

**.env:**
```
MCP_HEALTH_CHECK_TIMEOUT=10
```

**Why:** The backend (`archon-server`) periodically checks MCP health via HTTP. If the check times out after 5s, the UI shows "UNHEALTHY" even when MCP is fine. Increasing to 10s reduces false negatives.

**Important:** The `.env` file must also be updated, as it overrides the docker-compose default. If only docker-compose.yml is changed but .env still has the old value, the old value will be used.

**Status:** ✅ Applied in both `docker-compose.yml` (archon-server service, environment section) and `.env` (line ~104)

### 3. Optimize MCP Health Endpoint (`python/src/mcp_server/mcp_server.py`)

```python
# Perform dependency health checks with a short timeout
try:
    await asyncio.wait_for(perform_health_checks(_shared_context), timeout=2.0)
except Exception as e:
    logger.warning(f"Health sub-check timeout or error: {e}")
```

**Why:** The MCP `/health` endpoint can be slow if it waits on dependent services. Bounding checks to 2s keeps the endpoint responsive, preventing the backend from timing out.

**Status:** ✅ Applied in `mcp_server.py` (lines ~558-563)

## Roocode Configuration

**File:** `~/.config/Code/User/globalStorage/rooveterinaryinc.roo-cline/settings/mcp_settings.json`

```json
{
  "mcpServers": {
    "archon": {
      "command": "npx",
      "args": [
        "mcp-remote",
        "http://localhost:8051/mcp",
        "--allow-http"
      ]
    }
  }
}
```

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
timeout 10 mcp-remote http://localhost:8051/mcp --allow-http
```
Expected output includes:
- "Connected to remote server using StreamableHTTPClientTransport"
- "Proxy established successfully"

### Check HTTP/2 is negotiated
```bash
curl -i http://localhost:8051/mcp --http2 2>&1 | grep -i "HTTP/2"
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| `mcp-remote` timeouts after 60s | ALPN not enabled or HTTP/2 not negotiated | Check `run_hypercorn.py` has `alpn_protocols` set |
| Backend shows "unhealthy" but MCP is responding | Health check timeout too short | Update both `docker-compose.yml` AND `.env` to `MCP_HEALTH_CHECK_TIMEOUT=10` |
| Backend shows "unhealthy" after restart | Changes to docker-compose.yml ignored | Check `.env` file for conflicting value of `MCP_HEALTH_CHECK_TIMEOUT` |
| `/health` endpoint is slow | Dependency checks taking too long | Check `mcp_server.py` has 2s timeout on sub-checks |
| Roocode can't connect | `mcp_settings.json` path wrong or `mcp-remote` not installed | Verify file location and run `npm install -g mcp-remote` |

## Future: Proposed PR Changes

When the upstream issue is resolved, consider requesting a PR to include:
1. Default ALPN protocols in `run_hypercorn.py`
2. Environment variable for health check timeout in `docker-compose.yml`
3. Faster `/health` endpoint with bounded dependency checks

