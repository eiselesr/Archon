# Quick Reference: Archon MCP Setup & Troubleshooting

## One-Command Health Checks

**Check if everything is working:**
```bash
bash scripts/check_mcp_health.sh
```

**Verify patches are applied (after upstream update):**
```bash
bash scripts/check_mcp_patches.sh
```

## Roocode Setup (One-Time)

1. Create/edit `~/.config/Code/User/globalStorage/rooveterinaryinc.roo-cline/settings/mcp_settings.json`:

```json
{
  "mcpServers": {
    "archon": {
      "command": "npx",
      "args": ["mcp-remote", "http://localhost:8051/mcp", "--allow-http"]
    }
  }
}
```

2. Restart VS Code
3. Run: `bash scripts/check_mcp_health.sh` to verify

## Common Issues & Fixes

| Issue | Check | Fix |
|-------|-------|-----|
| Roocode can't connect | `bash scripts/check_mcp_health.sh` | See "mcp-remote" section in output |
| UI shows "UNHEALTHY" | `curl http://localhost:8051/health` | Update both `.env` AND `docker-compose.yml` to `MCP_HEALTH_CHECK_TIMEOUT=10`, then restart |
| Changes to docker-compose.yml don't apply | `docker compose exec archon-server env \| grep MCP_HEALTH` | Check `.env` file - it overrides docker-compose defaults |
| Timeouts in logs | `docker compose logs archon-server \| grep timeout` | Run patch verification: `bash scripts/check_mcp_patches.sh` |
| `mcp-remote` hangs | `timeout 10 mcp-remote http://localhost:8051/mcp --allow-http` | Check ALPN patch: `grep alpn python/src/mcp_server/run_hypercorn.py` |

## Full Documentation

See **[ROOCODE_SETUP.md](ROOCODE_SETUP.md)** for:
- Detailed patch explanations
- What was changed and why
- How to reapply patches after upstream updates
- Troubleshooting guide
- Manual verification commands

## File Locations

- **Patch 1 (HTTP/2):** `python/src/mcp_server/run_hypercorn.py` (line ~25)
- **Patch 2 (Timeout):** `docker-compose.yml` (archon-server environment) AND `.env` (line ~104)
- **Patch 3 (Health):** `python/src/mcp_server/mcp_server.py` (line ~558)
- **Roocode Config:** `~/.config/Code/User/globalStorage/rooveterinaryinc.roo-cline/settings/mcp_settings.json`

## If Repo Updates & Things Break

1. Run: `bash scripts/check_mcp_patches.sh`
2. See which patches are missing
3. Review corresponding section in [ROOCODE_SETUP.md](ROOCODE_SETUP.md)
4. Reapply manually
5. Rebuild & restart:
   ```bash
   docker compose build archon-mcp --no-cache
   docker compose up -d
   bash scripts/check_mcp_health.sh
   ```

## Key Commands

```bash
# View MCP status via API
curl http://localhost:8181/api/mcp/status | jq

# Direct MCP health
curl http://localhost:8051/health | jq

# Test mcp-remote (CLI version of what Roocode uses)
timeout 10 mcp-remote http://localhost:8051/mcp --allow-http

# View MCP logs
docker compose logs archon-mcp -f

# View server logs (for health check issues)
docker compose logs archon-server -f

# Restart all services
docker compose down && docker compose up -d
```
