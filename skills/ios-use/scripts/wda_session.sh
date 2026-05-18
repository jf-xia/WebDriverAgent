#!/usr/bin/env bash
# wda_session.sh - WDA Session 管理
#
# 用法:
#   ./wda_session.sh create                          # 创建 session，输出 sessionId
#   ./wda_session.sh run -- curl ...                # 创建 session 并执行命令
#   ./wda_session.sh clean                          # 清理旧 session
#
# 环境变量:
#   WDA_HOST  WDA 地址 (默认 127.0.0.1)
#   WDA_PORT  WDA 端口 (默认 8100)
#   WDA_CAPS  Session capabilities JSON (覆盖默认)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

HOST="${WDA_HOST:-$HOST}"
PORT="${WDA_PORT:-$PORT}"
TIMEOUT=10
BUNDLE_ID=""
CAPS="${WDA_CAPS:-}"
BASE_URL="http://${HOST}:${PORT}"

# --- 获取当前 session ID ---
get_current_session() {
    curl -s --connect-timeout 3 --max-time 3 "${BASE_URL}/status" 2>/dev/null \
        | jq -r '.sessionId // empty'
}

# --- 删除 session ---
delete_session() {
    local sid="$1"
    [[ -z "$sid" || "$sid" == "None" ]] && return
    curl -s --connect-timeout 2 -X DELETE "${BASE_URL}/session/${sid}" > /dev/null 2>&1 || true
}

# --- 创建 session ---
create_session() {
    local caps
    if [[ -n "$CAPS" ]]; then
        caps="$CAPS"
    else
        caps='{"capabilities":{"alwaysMatch":{"platformName":"iOS","automationName":"XCUITest","deviceName":"iPhone"},"firstMatch":[{}]}}'
        if [[ -n "$BUNDLE_ID" ]]; then
            caps=$(echo "$caps" | jq -c --arg bid "$BUNDLE_ID" '.capabilities.alwaysMatch.bundleId = $bid')
        fi
    fi

    local sid
    sid=$(curl -s --connect-timeout 5 --max-time 3 -X POST \
        "${BASE_URL}/session" \
        -H "Content-Type: application/json" \
        -d "$caps" 2>/dev/null \
        | jq -r '.sessionId // empty')

    if [[ -z "$sid" ]]; then
        echo "ERROR: 创建 session 失败" >&2
        return 1
    fi
    echo "$sid"
}

# --- 主逻辑：确保有可用 session ---
ensure_session() {
    local existing_sid
    existing_sid=$(get_current_session)

    if [[ -n "$existing_sid" ]]; then
        echo "$existing_sid"
        return 0
    fi

    create_session
}

# --- 如果是直接执行（非 source）---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SESSION_ID=$(ensure_session) || exit 1
    export SESSION_ID

    if [[ "${1:-}" == "--" ]]; then
        shift
        exec "$@"
    else
        echo "$SESSION_ID"
    fi
fi