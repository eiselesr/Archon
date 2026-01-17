#!/usr/bin/env bash
# MCP Patch Verification - Check if all required patches are applied
# Use this after upstream updates to verify fixes are still in place

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  MCP Patch Verification${NC}"
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

section() {
    echo ""
    echo -e "${BLUE}▶ $1${NC}"
}

# Check if files exist
check_file() {
    if [ ! -f "$1" ]; then
        fail "File not found: $1"
        return 1
    fi
    return 0
}

# Patch 1: Hypercorn ALPN configuration
section "Patch 1: HTTP/2 ALPN Support (run_hypercorn.py)"

FILE="python/src/mcp_server/run_hypercorn.py"
if check_file "$FILE"; then
    if grep -q 'config.alpn_protocols = \["h2", "http/1.1"\]' "$FILE"; then
        pass "ALPN protocols configured: ['h2', 'http/1.1']"
    else
        fail "ALPN protocols not configured or incorrect"
        echo "  Expected: config.alpn_protocols = [\"h2\", \"http/1.1\"]"
        echo "  Location: $FILE"
    fi
fi

# Patch 2: Backend health check timeout
section "Patch 2: Backend Health Check Timeout (docker-compose.yml)"

FILE="docker-compose.yml"
if check_file "$FILE"; then
    if grep -q 'MCP_HEALTH_CHECK_TIMEOUT' "$FILE"; then
        TIMEOUT=$(grep "MCP_HEALTH_CHECK_TIMEOUT" "$FILE" | head -1)
        pass "Health check timeout configured: $TIMEOUT"
    else
        fail "MCP_HEALTH_CHECK_TIMEOUT not configured"
        echo "  Expected: - MCP_HEALTH_CHECK_TIMEOUT=\${MCP_HEALTH_CHECK_TIMEOUT:-10}"
        echo "  Location: $FILE (archon-server service, environment section)"
    fi
fi

# Patch 3: MCP health endpoint optimization
section "Patch 3: Health Endpoint Optimization (mcp_server.py)"

FILE="python/src/mcp_server/mcp_server.py"
if check_file "$FILE"; then
    if grep -q 'await asyncio.wait_for(perform_health_checks' "$FILE"; then
        pass "Health endpoint has timeout wrapper"
    else
        fail "Health endpoint timeout wrapper not found"
        echo "  Expected: await asyncio.wait_for(perform_health_checks(_shared_context), timeout=2.0)"
        echo "  Location: $FILE (in http_health_endpoint function)"
    fi
fi

# Check supporting configuration
section "Supporting Configuration"

FILE="python/src/mcp_server/run_hypercorn.py"
if check_file "$FILE"; then
    if grep -q 'from hypercorn.asyncio import serve' "$FILE"; then
        pass "Hypercorn imported (not Uvicorn)"
    else
        fail "Hypercorn not imported or replaced with Uvicorn"
    fi
fi

# Check Dockerfile uses run_hypercorn
FILE="python/Dockerfile.mcp"
if check_file "$FILE"; then
    if grep -q 'src.mcp_server.run_hypercorn' "$FILE"; then
        pass "Dockerfile.mcp runs run_hypercorn (not mcp_server.py directly)"
    else
        fail "Dockerfile.mcp not using run_hypercorn"
        echo "  Expected: CMD [\"python\", \"-m\", \"src.mcp_server.run_hypercorn\"]"
    fi
fi

# Check pyproject.toml has hypercorn dependency
FILE="python/pyproject.toml"
if check_file "$FILE"; then
    if grep -q 'hypercorn\[h2\]' "$FILE"; then
        pass "hypercorn[h2] in dependencies"
    else
        fail "hypercorn[h2] not found in dependencies"
        echo "  Expected: \"hypercorn[h2]>=0.16.0\" in mcp dependencies"
    fi
fi

# Summary
section "Summary"

echo ""
echo -e "Passed:  ${GREEN}$PASSED${NC}"
echo -e "Failed:  ${RED}$FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All patches are applied!${NC}"
    echo ""
    echo "Next steps:"
    echo "  • Run: bash scripts/check_mcp_health.sh"
    echo "  • Review: ROOCODE_SETUP.md for configuration details"
    exit 0
else
    echo -e "${RED}✗ Some patches are missing or incorrect${NC}"
    echo ""
    echo "To reapply patches manually:"
    echo "  1. Review ROOCODE_SETUP.md for what each patch does"
    echo "  2. Apply changes to the listed files"
    echo "  3. Run: docker compose build archon-mcp --no-cache"
    echo "  4. Run: docker compose up -d"
    echo "  5. Verify: bash scripts/check_mcp_health.sh"
    exit 1
fi
