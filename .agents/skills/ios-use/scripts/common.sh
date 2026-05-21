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

# 检查 WDA 连接是否可用
# 参数: [HOST] [PORT]
# 返回: 0 可用, 1 不可用
check_wda() {
    local host="${1:-$HOST}"
    local port="${2:-$PORT}"
    local url="http://${host}:${port}/status"

    curl -s --connect-timeout 3 --max-time 10 "$url" >/dev/null 2>&1 || {
        printf '%b\n' "${RED}WDA 不可达: ${host}:${port}${NC}, 执行 ios_wda_test_on_iphone.sh 重启WDA, 然后等待10~30秒后在wda.log中查看状态" >&2
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

    if check_wda "$host" "$port"; then
        return 0
    fi

    if [[ ! -f "$start_script" ]]; then
        printf '%b\n' "${RED}找不到 WDA 启动脚本: $start_script${NC}" >&2
        return 1
    fi

    printf '%b\n' "${YELLOW}尝试自动启动 WDA: $start_script --port $port${NC}" >&2
    if ! bash "$start_script" --port "$port" >&2; then
        printf '%b\n' "${YELLOW}WDA 启动脚本返回非 0，继续轮询状态...${NC}" >&2
    fi

    while [[ $wait_seconds -lt $max_wait_seconds ]]; do
        sleep 3
        wait_seconds=$((wait_seconds + 3))

        if check_wda "$host" "$port"; then
            printf '%b\n' "${GREEN}WDA 已恢复: ${host}:${port}（${wait_seconds}s）${NC}" >&2
            return 0
        fi

        printf '%b\n' "${YELLOW}等待 WDA 恢复中... (${wait_seconds}/${max_wait_seconds}s)${NC}" >&2
    done

    printf '%b\n' "${RED}WDA 自动恢复失败: ${host}:${port}${NC}" >&2
    return 1
}
