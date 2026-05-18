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
CMD_ARGS=""
SESSION_ID=""

cleanup() {
    if [[ -n "${SESSION_ID:-}" ]] && [[ "$SESSION_ID" != "None" ]]; then
        curl -s --connect-timeout 2 -X DELETE "http://${HOST}:${PORT}/session/${SESSION_ID}" > /dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

usage() {
    cat <<'EOF'
Usage: wda_session.sh <command> [options] -- [command...]

Commands:
  create              创建 session，输出 sessionId 到 stdout
  run                 创建 session 并执行后续命令
  clean               清理现有 session (新 session 会自动 kill 旧 session，此命令可选)

Run options (only for 'run'):
  --timeout <sec>     命令超时，默认 30 (0=不限制)
  --bundle-id <id>    指定 bundle ID
  --caps <json>       自定义 capabilities JSON
  --no-cleanup        不自动清理 session
  --clean-first       先清理旧 session

Example (只需传路径，脚本自动补全前缀和 SESSION_ID):
  wda_session.sh run -- curl -s '/orientation'
  wda_session.sh run --bundle-id com.apple.mobilesafari -- curl -s '/screenshot'
  wda_session.sh run -- curl -s '/source'
  wda_session.sh run -- curl -s '/wda/alert/text'
EOF
    exit 1
}

make_capabilities() {
    if [[ -n "$CAPS" ]]; then
        printf '%s' "$CAPS"
        return
    fi
    # WDA 要求顶层必须有 capabilities 包裹
    local caps='{"capabilities":{"alwaysMatch":{"platformName":"iOS","automationName":"XCUITest","deviceName":"iPhone"},"firstMatch":[{}]}}'
    if [[ -n "$BUNDLE_ID" ]]; then
        caps=$(echo "$caps" | python3 -c "
import sys,json
d=json.load(sys.stdin)
d['capabilities']['alwaysMatch']['bundleId']='$BUNDLE_ID'
print(json.dumps(d))
")
    fi
    printf '%s' "$caps"
}

create_session() {
    local caps
    caps=$(make_capabilities)

    local resp sid
    for attempt in 1 2 3; do
        resp=$(curl -s --connect-timeout 5 --max-time 20 -X POST \
            "http://${HOST}:${PORT}/session" \
            -H "Content-Type: application/json" \
            -d "$caps")
        # WDA: 如果已有 session 占用，重试 kill 后创建
        if echo "$resp" | grep -q '"session not created"'; then
            if [[ "$attempt" -lt 3 ]]; then
                sleep 1
                continue
            fi
        fi
        sid=$(echo "$resp" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    s=d.get('sessionId','')
    if s and s != 'None':
        print(s)
except:
    pass
" 2>/dev/null)
        if [[ -n "$sid" && "$sid" != "None" ]]; then
            printf '%s' "$sid"
            return 0
        fi
    done
    echo "ERROR: Session creation failed: $resp" >&2
    return 1
}

clean_sessions() {
    # WDA 新建 session 会自动 kill 旧 session，clean 操作实质不需要
    true
}

# 从 WDA 响应中去除 sessionId 字段 (脚本已单独显示，输出无需重复)
strip_session_id() {
    # 检查是否是合法 JSON 且包含 sessionId
    if python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if 'sessionId' in d:
        # 输出不含 sessionId 的 JSON
        d.pop('sessionId')
        # 如果 value 里还有 sessionId，也去掉
        if isinstance(d.get('value'), dict) and 'sessionId' in d['value']:
            d['value'].pop('sessionId', None)
        print(json.dumps(d, indent=2, ensure_ascii=False))
    else:
        sys.exit(0)
except:
    sys.exit(0)
" 2>/dev/null; then
        :
    else
        # 不是合法 JSON 或无 sessionId，原样输出
        cat
    fi
}

# 自动补全 curl URL: 以 / 开头或包含 $SESSION_ID 但没有域名的，自动加前缀
auto_prefix_url() {
    local cmd="$1"
    # 匹配 curl 参数中的 URL，自动补全
    if echo "$cmd" | grep -qE 'curl.*(\/session\/|\/status|\/source|\/screenshot|\/alert|\/orientation|\/url|\/wda\/|\/appium\/|\/element\/)'; then
        # 替换裸 WDA 路径为完整路径，$SESSION_ID 保留给运行时展开
        cmd=$(echo "$cmd" | sed \
            -e "s|curl -s /status|curl -s http://${HOST}:${PORT}/session/\$SESSION_ID/status|g" \
            -e "s|curl -s /source|curl -s http://${HOST}:${PORT}/session/\$SESSION_ID/source|g" \
            -e "s|curl -s /screenshot|curl -s http://${HOST}:${PORT}/session/\$SESSION_ID/screenshot|g" \
            -e "s|curl -s /alert|curl -s http://${HOST}:${PORT}/session/\$SESSION_ID/alert|g" \
            -e "s|curl -s /orientation|curl -s http://${HOST}:${PORT}/session/\$SESSION_ID/orientation|g" \
            -e "s|curl -s /url|curl -s http://${HOST}:${PORT}/session/\$SESSION_ID/url|g" \
            -e "s|curl -s /wda/|curl -s http://${HOST}:${PORT}/session/\$SESSION_ID/wda/|g" \
            -e "s|curl -s /appium/|curl -s http://${HOST}:${PORT}/session/\$SESSION_ID/appium/|g" \
            -e "s|curl -s /element/|curl -s http://${HOST}:${PORT}/session/\$SESSION_ID/element/|g" \
            -e "s|curl -s /session/\$SESSION_ID/|curl -s http://${HOST}:${PORT}/session/\$SESSION_ID/|g" \
            )
    fi
    echo "$cmd"
}
# --- Parse args ---
if [[ $# -lt 1 ]]; then
    usage
fi

COMMAND="$1"
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)   TIMEOUT="$2"; shift 2 ;;
        --bundle-id) BUNDLE_ID="$2"; shift 2 ;;
        --caps)      CAPS="$2"; shift 2 ;;
        --no-cleanup) CLEANUP_DONE=true; shift ;;
        --clean-first) clean_sessions; shift ;;
        --)          shift; CMD_ARGS="$*"; break ;;
        -h|--help)   usage ;;
        *)           echo "未知参数: $1" >&2; usage ;;
    esac
done

# --- Execute ---
case "$COMMAND" in
    create)
        SESSION_ID=$(create_session)
        echo "$SESSION_ID"
        ;;
    run)
        if [[ -z "$CMD_ARGS" ]]; then
            echo "ERROR: 需要指定要执行的命令 (在 -- 之后)" >&2
            usage
        fi

        check_wda "$HOST" "$PORT"

        echo -e "${BLUE}创建 session...${NC}"
        SESSION_ID=$(create_session)
        echo -e "${GREEN}Session: ${SESSION_ID}${NC}"

        # 在 SESSION_ID 已知的上下文中执行命令 (bash -c 展开 $SESSION_ID)
        # 自动补全 curl URL 前缀
        CMD_ARGS=$(auto_prefix_url "$CMD_ARGS")
        export SESSION_ID
        if [[ "$TIMEOUT" -gt 0 ]]; then
            echo -e "${YELLOW}执行命令 (限制 ${TIMEOUT}s 超时)...${NC}"
            timeout "$TIMEOUT" bash -c "SESSION_ID=$SESSION_ID; $CMD_ARGS" | strip_session_id
        else
            echo -e "${YELLOW}执行命令...${NC}"
            bash -c "SESSION_ID=$SESSION_ID; $CMD_ARGS" | strip_session_id
        fi
        ;;
    clean)
        clean_sessions
        echo "Sessions cleaned."
        ;;
    *)
        echo "未知命令: $COMMAND" >&2
        usage
        ;;
esac
