#!/usr/bin/env bash
# ios_wda_test_on_iphone.sh
set -euo pipefail

# 加载公共函数
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# 脚本专属默认值
PROJECT_PATH="$HOME/work/WebDriverAgent/WebDriverAgent.xcodeproj"
SCHEME="WebDriverAgentRunner"
UDID=""
LOG_DIR="$PROJECT_ROOT/tmp"

usage() {
    echo "Usage: $0 [--udid <UDID>] [--port <PORT>] [--project-path <PATH>] [--scheme <SCHEME>]"
    echo "   --udid          设备 UDID（可选，自动检测）"
    echo "   --port          WDA 端口（默认: 8100）"
    echo "   --project-path  WebDriverAgent.xcodeproj 路径"
    echo "   --scheme        Xcode scheme（默认: WebDriverAgentRunner）"
    exit 1
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
         --udid)
            UDID="$2"
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

# 创建日志目录
mkdir -p "$LOG_DIR"

# 验证工具可用性
validate_tools() {
    local tools=("idevice_id" "xcrun" "jq" "tmux" "iproxy")
    local missing=()

    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing+=("$tool")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}缺少工具: ${missing[*]}${NC}"
        if [[ " ${missing[*]} " =~ " iproxy " ]]; then
            echo "安装 iproxy: brew install libimobiledevice"
        fi
        return 1
    fi

    if ! command -v xcodebuild &> /dev/null; then
        echo -e "${RED}xcodebuild 不可用，请检查 Xcode 安装和授权${NC}"
        return 1
    fi

    return 0
}

# 清理旧的 tmux session
cleanup_old_tmux_sessions() {
    local sessions
    sessions=$(tmux list-sessions 2>/dev/null | grep -E '^(wda|iproxy)[^a-zA-Z]' || true)
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

    if command -v idevice_id &> /dev/null; then
        local udids
        udids=$(idevice_id -l 2>/dev/null | head -1)
        if [[ -n "$udids" ]]; then
            echo "$udids"
            return 0
        fi
    fi

    if command -v xcrun &> /dev/null; then
        local udids
        udids=$(xcrun xctrace list devices 2>/dev/null | awk '/^iPhone / && !/Offline/ && !/Simulator/ {print $NF}' | tr -d '()' | head -1)
        if [[ -n "$udids" ]]; then
            echo "$udids"
            return 0
        fi
    fi

    return 1
}

# 启动 iproxy 端口转发
start_iproxy() {
    local udid="$1"
    local local_port="$2"
    local remote_port="$3"

    # 检查端口是否已被占用
    if lsof -ti:"$local_port" &> /dev/null; then
        echo -e "${YELLOW}端口 $local_port 已被占用，尝试释放...${NC}"
        lsof -ti:"$local_port" | xargs kill -9 2>/dev/null || true
        sleep 1
    fi

    # 启动 iproxy
    local session_name="iproxy-${udid}-${local_port}"
    tmux new-session -d -s "$session_name" \
         "iproxy $local_port $remote_port -u $udid 2>&1 | tee ${LOG_DIR}/iproxy.log"

    echo -e "${GREEN}已启动 iproxy tmux 会话: $session_name${NC}"

    # 等待 iproxy 就绪并验证
    echo "等待 iproxy 就绪..."
    local max_wait=10
    local wait_time=0
    while [[ $wait_time -lt $max_wait ]]; do
        sleep 1
        wait_time=$((wait_time + 1))

        # 检查 tmux 会话是否还存在
        if ! tmux has-session -t "$session_name" 2>/dev/null; then
            echo -e "${RED}iproxy tmux 会话已退出${NC}"
            echo "iproxy 日志:"
            cat "${LOG_DIR}/iproxy.log" 2>/dev/null || echo "无日志"
            return 1
        fi

        # 检查端口是否在监听
        if lsof -ti:"$local_port" &> /dev/null; then
            echo -e "${GREEN}iproxy 端口 $local_port 已就绪（${wait_time}s）${NC}"
            return 0
        fi

        echo "等待中... ($wait_time/$max_wait)"
    done

    echo -e "${RED}iproxy 启动超时${NC}"
    return 1
}

# 主流程
main() {
    echo -e "${GREEN}=== WDA 测试启动 ===${NC}"

    # 1. 获取设备 UDID
    echo "1. 获取设备 UDID..."
    local udid
    if ! udid=$(get_device_udid); then
        echo -e "${RED}未找到连接的 iPhone 设备${NC}"
        exit 1
    fi
    echo -e "${GREEN}设备 UDID: $udid${NC}"

    # 2. 验证工具可用性
    echo "2. 验证工具可用性..."
    if ! validate_tools; then
        exit 1
    fi
    echo -e "${GREEN}工具验证通过${NC}"

    # 3. 清理旧的 tmux session
    echo "3. 清理旧的 tmux session..."
    cleanup_old_tmux_sessions

    # 4. 启动 iproxy
    echo "4. 启动 iproxy..."
    if ! start_iproxy "$udid" "$PORT" "$PORT"; then
        echo -e "${RED}iproxy 启动失败${NC}"
        exit 1
    fi

    # 5. 启动 xcodebuild
    echo "5. 启动 xcodebuild..."
    local log_file="${LOG_DIR}/wda.log"
    local session_name="wda-${udid}"

    tmux new-session -d -s "$session_name" \
         "USE_PORT=$PORT xcodebuild -project \"$PROJECT_PATH\" -scheme \"$SCHEME\" -destination \"id=$udid\" test 2>&1 | tee \"$log_file\"; echo '测试完成，按任意键退出...'; read -n 1 -s"

    echo -e "${GREEN}已在 tmux 会话 '$session_name' 中启动 xcodebuild${NC}"
    echo "查看日志: tmux attach -t $session_name"
    echo ""
    echo -e "${GREEN}=== 启动完成 ===${NC}"
    echo "iproxy: localhost:$PORT -> device:$PORT"
    echo "WDA 端点: http://127.0.0.1:$PORT"
}

# 执行主流程
main "$@"
