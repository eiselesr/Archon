#!/usr/bin/env bash
# MCP Health Check - Verify Archon MCP server and remote client connectivity
# No IDE or Roocode required - runs standalone health checks

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNINGS=0

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  MCP Server Health Check${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Helper functions
pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

section() {
    echo ""
    echo -e "${BLUE}▶ $1${NC}"
}

# 1. Check if Docker containers are running
section "Docker Container Status"

if docker compose ps archon-mcp | grep -q "Up"; then
    pass "MCP container is running"
else
    fail "MCP container is not running"
    echo "  Run: docker compose up -d archon-mcp"
    exit 1
fi

if docker compose ps archon-server | grep -q "Up"; then
    pass "Server container is running"
else
    fail "Server container is not running"
    echo "  Run: docker compose up -d archon-server"
    exit 1
fi

# 2. Check MCP /health endpoint
section "MCP Server Health Endpoint"

if HEALTH=$(curl -s http://localhost:8051/health 2>/dev/null); then
    if echo "$HEALTH" | grep -q '"success":true'; then
        pass "MCP /health endpoint responds with success=true"
        UPTIME=$(echo "$HEALTH" | grep -o '"uptime_seconds":[0-9.]*' | cut -d: -f2)
        if [ -n "$UPTIME" ]; then
            pass "MCP uptime: ${UPTIME}s"
        fi
    else
        fail "MCP /health returned success=false"
        echo "  Response: $HEALTH"
    fi
else
    fail "MCP /health endpoint unreachable"
    echo "  Check: curl http://localhost:8051/health"
fi

# 3. Check backend can reach MCP
section "Backend → MCP Connectivity"

STATUS=$(curl -s http://localhost:8181/api/mcp/status 2>/dev/null)
STATUS_VALUE=$(echo "$STATUS" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

if [ "$STATUS_VALUE" = "running" ]; then
    pass "Backend reports MCP status: $STATUS_VALUE"
elif [ "$STATUS_VALUE" = "unhealthy" ]; then
    warn "Backend reports MCP status: $STATUS_VALUE (may indicate health check timeout)"
    echo "  Try: Restart services and check again"
elif [ -z "$STATUS_VALUE" ]; then
    fail "Backend /api/mcp/status returned no status field"
    echo "  Response: $STATUS"
else
    warn "Backend reports MCP status: $STATUS_VALUE (unexpected)"
fi

# 4. Check mcp-remote availability
section "Remote Client Support (mcp-remote)"

if ! command -v mcp-remote &> /dev/null; then
    warn "mcp-remote not found in PATH"
    echo "  Install: npm install -g mcp-remote"
else
    pass "mcp-remote is installed"
    
    # Test connection with timeout (SSE transport)
    echo "  Testing connection..."
    timeout 5 mcp-remote http://localhost:8051/sse --allow-http --transport sse-only > /tmp/mcp_remote_test.log 2>&1 &
    MCP_REMOTE_PID=$!
    sleep 3
    
    # Check if process is still running (should be alive and waiting)
    if kill -0 $MCP_REMOTE_PID 2>/dev/null; then
        # Process is running, check if proxy was established
        if grep -q "Proxy established successfully" /tmp/mcp_remote_test.log; then
            pass "mcp-remote proxy established successfully"
        else
            warn "mcp-remote connected but proxy status unclear"
        fi
        kill $MCP_REMOTE_PID 2>/dev/null || true
        wait $MCP_REMOTE_PID 2>/dev/null || true
    else
        # Process ended - check if it was successful
        if grep -q "Proxy established successfully" /tmp/mcp_remote_test.log 2>/dev/null; then
            pass "mcp-remote proxy established successfully"
        else
            fail "mcp-remote failed to establish proxy"
            echo "  Log: $(head -3 /tmp/mcp_remote_test.log 2>/dev/null)"
        fi
    fi
    rm -f /tmp/mcp_remote_test.log
fi

# 5. Check backend config
section "Backend MCP Configuration"

CONFIG=$(curl -s http://localhost:8181/api/mcp/config 2>/dev/null)
TRANSPORT=$(echo "$CONFIG" | grep -o '"transport":"[^"]*"' | cut -d'"' -f4)
PORT=$(echo "$CONFIG" | grep -o '"port":[0-9]*' | cut -d: -f2)

if [ -n "$TRANSPORT" ]; then
    pass "MCP transport: $TRANSPORT"
else
    warn "Could not determine transport from config"
fi

if [ "$PORT" = "8051" ]; then
    pass "MCP port: 8051"
else
    warn "MCP port is $PORT (expected 8051)"
fi

# 6. Check ASGI server is running (Uvicorn for SSE, Hypercorn for streamable-http)
section "Server Process Check"

if docker compose logs archon-mcp | grep -q "Uvicorn running on"; then
    pass "Uvicorn is running (SSE transport enabled)"
elif docker compose logs archon-mcp | grep -q "Starting MCP server with Hypercorn"; then
    warn "Hypercorn is running (streamable-http transport - SSE transport not configured)"
    echo "  For SSE transport: ensure TRANSPORT=sse in docker-compose.yml"
else
    warn "Could not determine which ASGI server is running"
fi

# 7. Summary
section "Summary"

echo ""
echo -e "Passed:  ${GREEN}$PASSED${NC}"
echo -e "Failed:  ${RED}$FAILED${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All critical checks passed!${NC}"
    if [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}Note: $WARNINGS warning(s) - see above${NC}"
    fi
    echo ""
    echo -e "MCP is ready for remote clients:"
    echo "  • Roocode: Use mcp_settings.json config with SSE endpoint (see ROOCODE_SETUP.md)"
    echo "  • Claude Desktop: Add to config with mcp-remote transport (SSE)"
    echo "  • CLI test: mcp-remote http://localhost:8051/sse --allow-http --transport sse-only"
    exit 0
else
    echo -e "${RED}✗ Some checks failed - see above for details${NC}"
    echo ""
    echo "Troubleshooting steps:"
    echo "  1. Check docker compose is running: docker compose ps"
    echo "  2. Restart services: docker compose down && docker compose up -d"
    echo "  3. View logs: docker compose logs archon-mcp -f"
    echo "  4. See ROOCODE_SETUP.md for patch details"
    exit 1
fi
