#!/usr/bin/env bash
# common.sh - WDA 脚本公共函数
# 被 scripts/ 下的脚本 source 使用

# 路径计算
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 公共默认值
HOST="127.0.0.1"
PORT="8100"

timestamp() {
    date '+%H:%M:%S'
}

start_timer() {
    date +%s
}

elapsed_seconds() {
    local start_time="${1:-0}"
    echo $(( $(date +%s) - start_time ))
}

file_size_bytes() {
    local file_path="$1"
    [[ -f "$file_path" ]] || {
        echo 0
        return 0
    }
    wc -c < "$file_path" | tr -d ' '
}

log_info() {
    printf '%b\n' "${BLUE}[$(timestamp)] $*${NC}" >&2
}

log_warn() {
    printf '%b\n' "${YELLOW}[$(timestamp)] $*${NC}" >&2
}

log_error() {
    printf '%b\n' "${RED}[$(timestamp)] $*${NC}" >&2
}

log_success() {
    printf '%b\n' "${GREEN}[$(timestamp)] $*${NC}" >&2
}

# 检查 WDA 连接是否可用
# 参数: [HOST] [PORT]
# 返回: 0 可用, 1 不可用
check_wda() {
    local host="${1:-$HOST}"
    local port="${2:-$PORT}"
    local url="http://${host}:${port}/status"

    curl -s --connect-timeout 3 --max-time 10 "$url" >/dev/null 2>&1 || {
        log_error "WDA 不可达: ${host}:${port}。可执行 ios_wda_test_on_iphone.sh 重启，再查看 tmp/wda.log"
        return 1
    }
}

# 确保 WDA 可用：先探测，失败后自动触发启动脚本并轮询恢复
# 参数: [HOST] [PORT]
# 返回: 0 可用, 1 不可用
ensure_wda_ready() {
    local host="${1:-$HOST}"
    local port="${2:-$PORT}"
    local start_script="$SCRIPT_DIR/ios_wda_test_on_iphone.sh"
    local wait_seconds=0
    local max_wait_seconds=30
    local start_time
    start_time=$(start_timer)

    if check_wda "$host" "$port"; then
        log_success "WDA 可用: ${host}:${port}"
        return 0
    fi

    if [[ ! -f "$start_script" ]]; then
        log_error "找不到 WDA 启动脚本: $start_script"
        return 1
    fi

    log_warn "尝试自动启动 WDA: $start_script --port $port"
    if ! bash "$start_script" --port "$port" >&2; then
        log_warn "WDA 启动脚本返回非 0，继续轮询状态"
    fi

    while [[ $wait_seconds -lt $max_wait_seconds ]]; do
        sleep 3
        wait_seconds=$((wait_seconds + 3))

        if check_wda "$host" "$port"; then
            log_success "WDA 已恢复: ${host}:${port}（轮询 ${wait_seconds}s，总耗时 $(elapsed_seconds "$start_time")s）"
            return 0
        fi

        log_warn "等待 WDA 恢复中... (${wait_seconds}/${max_wait_seconds}s)"
    done

    log_error "WDA 自动恢复失败: ${host}:${port}（总耗时 $(elapsed_seconds "$start_time")s）"
    return 1
}
