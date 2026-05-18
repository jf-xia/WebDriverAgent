#!/usr/bin/env bash
# common.sh - WDA 脚本公共函数
# 被 scripts/ 下的脚本 source 使用

# 路径计算
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

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
        echo -e "${RED}WDA 不可达: ${host}:${port}${NC}, 执行 ios_wda_test_on_iphone.sh 重启WDA, 然后等待10~30秒后在wda.log中查看状态" >&2
        return 1
    }
}
