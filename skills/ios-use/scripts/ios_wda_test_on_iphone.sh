#!/usr/bin/env bash
# ios_wda_test_on_iphone.sh
# 检查 WDA 状态，验证工具，清理旧 tmux session，启动 xcodebuild 测试，输出状态 JSON
# 使用: bash ios_wda_test_on_iphone.sh [--udid <UDID>] [--host <HOST>] [--port <PORT>] [--project-path <PATH>] [--scheme <SCHEME>]
set -euo pipefail

# 默认值
HOST="127.0.0.1"
PORT=8100
PROJECT_PATH="$HOME/work/WebDriverAgent/WebDriverAgent.xcodeproj"
SCHEME="WebDriverAgentRunner"
UDID=""
CACHE_DIR="./tmp"
LOG_DIR="./tmp"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 [--udid <UDID>] [--host <HOST>] [--port <PORT>] [--project-path <PATH>] [--scheme <SCHEME>]"
    echo "  --udid          设备 UDID（可选，自动检测）"
    echo "  --host          WDA 主机地址（默认: 127.0.0.1）"
    echo "  --port          WDA 端口（默认: 8100）"
    echo "  --project-path  WebDriverAgent.xcodeproj 路径（默认: ~/work/WebDriverAgent/WebDriverAgent.xcodeproj）"
    echo "  --scheme        Xcode scheme（默认: WebDriverAgentRunner）"
    exit 1
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --udid)
            UDID="$2"
            shift 2
            ;;
        --host)
            HOST="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --project-path)
            PROJECT_PATH="$2"
            shift 2
            ;;
        --scheme)
            SCHEME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "未知参数: $1"
            usage
            ;;
    esac
done

# 创建缓存和日志目录
mkdir -p "$CACHE_DIR" "$LOG_DIR"

# 检查 WDA 状态
check_wda_status() {
    local url="http://${HOST}:${PORT}/status"
    local response
    response=$(curl -s -X GET "$url" 2>/dev/null) || true
    if [[ -n "$response" ]]; then
        local ready
        ready=$(echo "$response" | jq -r '.value.ready' 2>/dev/null) || true
        if [[ "$ready" == "true" ]]; then
            echo "$response"
            return 0
        fi
    fi
    return 1
}

# 验证工具可用性
validate_tools() {
    local tools=("iproxy" "idevice_id" "xcrun" "jq")
    local missing=()
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing+=("$tool")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}缺少工具: ${missing[*]}${NC}"
        return 1
    fi
    
    # 检查 Xcode 授权（xcodebuild 是否可用）
    if ! command -v xcodebuild &> /dev/null; then
        echo -e "${RED}xcodebuild 不可用，请检查 Xcode 安装和授权${NC}"
        return 1
    fi
    
    # 检查 xcrun xctrace 是否可用（用于设备列表）
    if ! xcrun xctrace list devices &> /dev/null; then
        echo -e "${YELLOW}xcrun xctrace list devices 失败，可能需要 Xcode 授权${NC}"
        return 1
    fi
    
    return 0
}

# 清理旧的 tmux session
cleanup_old_tmux_sessions() {
    local sessions
    sessions=$(tmux list-sessions 2>/dev/null | grep -E '^wda-|^iproxy-' || true)
    if [[ -n "$sessions" ]]; then
        echo -e "${YELLOW}发现旧的 tmux 会话，正在清理...${NC}"
        echo "$sessions" | while read -r line; do
            local session_name
            session_name=$(echo "$line" | cut -d: -f1)
            tmux kill-session -t "$session_name" 2>/dev/null || true
            echo "已关闭会话: $session_name"
        done
    fi
}

# 获取设备 UDID
get_device_udid() {
    if [[ -n "$UDID" ]]; then
        echo "$UDID"
        return 0
    fi
    
    # 自动检测 iPhone
    local udids
    udids=$(xcrun xctrace list devices 2>/dev/null | awk '/^iPhone / && !/Offline/ && !/Simulator/ {print $NF}' | tr -d '()' | head -1)
    if [[ -n "$udids" ]]; then
        echo "$udids"
        return 0
    fi
    
    return 1
}

# 启动 WDA 测试
start_wda_test() {
    local udid="$1"
    local log_file="${LOG_DIR}/wda-${udid}.log"
    local cache_file="${CACHE_DIR}/wda-${udid}.json"
    
    echo -e "${GREEN}启动 WDA 测试，设备 UDID: $udid${NC}"
    echo "日志文件: $log_file"
    echo "缓存文件: $cache_file"
    
    # 启动 tmux 会话运行 xcodebuild，设置 USE_PORT 环境变量
    tmux new-session -d -s "wda-test" \
        "USE_PORT=$PORT xcodebuild -project \"$PROJECT_PATH\" -scheme \"$SCHEME\" -destination \"id=$udid\" test 2>&1 | tee \"$log_file\"; echo '测试完成，按任意键退出...'; read -n 1 -s"
    
    echo -e "${GREEN}已在 tmux 会话 'wda-test' 中启动 xcodebuild${NC}"
    echo "查看日志: tmux attach -t wda-test"
    
    # 等待一段时间，检查 WDA 是否启动
    echo "等待 WDA 启动..."
    local max_wait=60
    local wait_time=0
    while [[ $wait_time -lt $max_wait ]]; do
        sleep 5
        wait_time=$((wait_time + 5))
        if check_wda_status > /dev/null 2>&1; then
            echo -e "${GREEN}WDA 已启动${NC}"
            break
        fi
        echo "等待中... ($wait_time/$max_wait)"
    done
    
    # 获取最终状态
    local status_response
    status_response=$(check_wda_status) || true
    
    if [[ -n "$status_response" ]]; then
        # 提取 PID（从 status 响应中）
        local pid
        pid=$(echo "$status_response" | jq -r '.value.os.pid // "unknown"' 2>/dev/null) || pid="unknown"
        
        # 构建输出 JSON
        local output_json
        output_json=$(jq -n \
            --arg status "ready" \
            --arg udid "$udid" \
            --arg wda_endpoint "http://${HOST}:${PORT}" \
            --arg pid "$pid" \
            '{status: $status, udid: $udid, wda_endpoint: $wda_endpoint, pid: $pid}')
        
        # 缓存到文件
        echo "$output_json" > "$cache_file"
        
        # 输出到 stdout
        echo "$output_json"
        return 0
    else
        echo -e "${RED}WDA 未成功启动${NC}"
        local error_json
        error_json=$(jq -n \
            --arg status "error" \
            --arg udid "$udid" \
            --arg wda_endpoint "http://${HOST}:${PORT}" \
            --arg pid "unknown" \
            '{status: $status, udid: $udid, wda_endpoint: $wda_endpoint, pid: $pid}')
        echo "$error_json"
        return 1
    fi
}

# 主流程
main() {
    echo -e "${GREEN}=== WDA 测试启动检查 ===${NC}"
    
    # 1. 检查 WDA 是否已启动
    echo "1. 检查 WDA 状态..."
    if status_response=$(check_wda_status); then
        echo -e "${GREEN}WDA 已启动，直接返回状态${NC}"
        echo "$status_response"
        exit 0
    fi
    echo "WDA 未启动，继续检查..."
    
    # 2. 验证工具可用性
    echo "2. 验证工具可用性..."
    if ! validate_tools; then
        exit 1
    fi
    echo -e "${GREEN}工具验证通过${NC}"
    
    # 3. 清理旧的 tmux session
    echo "3. 清理旧的 tmux session..."
    cleanup_old_tmux_sessions
    
    # 4. 获取设备 UDID
    echo "4. 获取设备 UDID..."
    local udid
    if ! udid=$(get_device_udid); then
        echo -e "${RED}未找到连接的 iPhone 设备${NC}"
        exit 1
    fi
    echo -e "${GREEN}设备 UDID: $udid${NC}"
    
    # 5. 启动 WDA 测试
    echo "5. 启动 WDA 测试..."
    if start_wda_test "$udid"; then
        echo -e "${GREEN}WDA 测试启动成功${NC}"
    else
        echo -e "${RED}WDA 测试启动失败${NC}"
        exit 1
    fi
}

# 执行主流程
main "$@"