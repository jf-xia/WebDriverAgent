#!/usr/bin/env bash
# ios_wda_test_on_iphone.sh
set -euo pipefail

# 默认值
HOST=""
PORT=8100
PROJECT_PATH="$HOME/work/WebDriverAgent/WebDriverAgent.xcodeproj"
SCHEME="WebDriverAgentRunner"
UDID=""
CACHE_DIR="./tmp"
LOG_DIR="./tmp"
# 改为空字符串，表示自动检测
USE_IPROXY=""

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    echo "Usage: $0 [--udid <UDID>] [--host <HOST>] [--port <PORT>] [--project-path <PATH>] [--scheme <SCHEME>] [--iproxy|--no-iproxy]"
    echo "  --udid          设备 UDID（可选，自动检测）"
    echo "  --host          WDA 主机地址（可选，自动检测）"
    echo "  --port          WDA 端口（默认: 8100）"
    echo "  --project-path  WebDriverAgent.xcodeproj 路径"
    echo "  --scheme        Xcode scheme（默认: WebDriverAgentRunner）"
    echo "  --iproxy        强制使用 iproxy 端口转发"
    echo "  --no-iproxy     强制不使用 iproxy，直接连接设备 IP"
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
        --iproxy)
            USE_IPROXY="true"
            shift
            ;;
        --wifi)
            USE_IPROXY="false"
            shift
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

# 获取设备 IP 地址
get_device_ip() {
    local udid="$1"
    local device_ip=""
    
    # 1. 从当前日志文件中提取 IP
    local log_file="${LOG_DIR}/wda.log"
    if [[ -f "$log_file" ]]; then
        # 提取 IP 地址（去掉 http:// 前缀）
        device_ip=$(grep -oE 'ServerURLHere->http://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$log_file" 2>/dev/null | sed 's/ServerURLHere->http:\/\///' | head -1 || true)
        if [[ -n "$device_ip" ]]; then
            echo "$device_ip"
            return 0
        fi
    fi
    
    # 2. 从之前的日志中提取 IP（按时间排序，取最新的）
    local previous_ip
    previous_ip=$(find "$LOG_DIR" -name "wda.log" -type f 2>/dev/null | \
        xargs grep -l "ServerURLHere" 2>/dev/null | \
        xargs grep -oE 'ServerURLHere->http://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' 2>/dev/null | \
        sed 's/ServerURLHere->http:\/\///' | \
        sort -u | tail -1 || true)
    if [[ -n "$previous_ip" ]]; then
        echo "$previous_ip"
        return 0
    fi
    
    # 3. 尝试从 ideviceinfo 获取 IP
    if command -v ideviceinfo &> /dev/null; then
        local wifi_ip
        wifi_ip=$(ideviceinfo -u "$udid" -k WiFiAddress 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true)
        if [[ -n "$wifi_ip" ]]; then
            echo "$wifi_ip"
            return 0
        fi
    fi
    
    echo ""
}

# 检查网络连通性
check_network_reachability() {
    local ip="$1"
    local port="$2"
    
    # 移除可能的 http:// 前缀
    ip=$(echo "$ip" | sed 's|^http://||')
    
    # 优先 HTTP 检测（最可靠，直接验证目标服务可达性）
    if curl -s --connect-timeout 3 "http://${ip}:${port}/status" > /dev/null 2>&1; then
        return 0
    fi
    # 回退到 ping + nc
    if ping -c 1 -W 2 "$ip" &> /dev/null; then
        if nc -z -w 2 "$ip" "$port" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# 检查设备连接方式
detect_connection_type() {
    local udid="$1"
    
    # 检查设备是否通过 USB 连接
    if command -v idevice_id &> /dev/null; then
        if idevice_id -l 2>/dev/null | grep -q "$udid"; then
            echo "USB"
            return 0
        fi
    fi
    
    # 检查是否通过网络连接
    if command -v ideviceinfo &> /dev/null; then
        local network_info
        network_info=$(ideviceinfo -u "$udid" -k NetworkType 2>/dev/null || true)
        if [[ "$network_info" == "WiFi" ]]; then
            echo "WiFi"
            return 0
        fi
    fi
    
    echo "unknown"
}

# 自动判断是否使用 iproxy
auto_detect_iproxy() {
    local udid="$1"
    
    # 1. 如果用户已经显式指定，直接返回
    if [[ "$USE_IPROXY" == "true" ]] || [[ "$USE_IPROXY" == "false" ]]; then
        echo -e "${BLUE}使用用户指定的 iproxy 设置: $USE_IPROXY${NC}"
        return 0
    fi
    
    # 2. 如果用户指定了非 localhost 的 HOST，可能是直接连接
    if [[ -n "$HOST" ]] && [[ "$HOST" != "127.0.0.1" ]] && [[ "$HOST" != "localhost" ]]; then
        echo -e "${BLUE}检测到用户指定了远程 HOST ($HOST)，使用直接连接${NC}"
        USE_IPROXY="false"
        return 0
    fi
    
    # 3. 尝试获取设备 IP 并测试连通性（优先 WiFi 直连）
    local device_ip
    device_ip=$(get_device_ip "$udid")
    
    if [[ -n "$device_ip" ]]; then
        echo -e "${BLUE}检测到设备 IP: $device_ip${NC}"
        if check_network_reachability "$device_ip" "$PORT"; then
            echo -e "${GREEN}设备 IP 可达，使用 WiFi 直连${NC}"
            USE_IPROXY="false"
            HOST="$device_ip"
            return 0
        else
            echo -e "${YELLOW}设备 IP 不可达，可能不在同一网络${NC}"
        fi
    else
        echo -e "${YELLOW}未检测到设备 IP${NC}"
    fi
    
    # 4. 检测设备连接方式，决定是否使用 iproxy
    local connection_type
    connection_type=$(detect_connection_type "$udid")
    echo -e "${BLUE}设备连接方式: $connection_type${NC}"
    
    # 5. 根据连接方式决定是否使用 iproxy
    if [[ "$connection_type" == "USB" ]]; then
        echo -e "${BLUE}使用 USB 连接 + iproxy 端口转发${NC}"
        USE_IPROXY="true"
        HOST="127.0.0.1"
    else
        # WiFi 连接或未知连接方式，尝试使用 iproxy
        echo -e "${YELLOW}WiFi 连接但设备不可达，尝试使用 iproxy${NC}"
        USE_IPROXY="true"
        HOST="127.0.0.1"
    fi
    
    return 0
}

# 检查 WDA 状态
check_wda_status() {
    local url="http://${HOST}:${PORT}/status"
    local response
    echo "[check_wda_status] 请求: $url" >&2
    response=$(curl -s --connect-timeout 5 -X GET "$url" 2>/dev/null) || true
    echo "[check_wda_status] 响应: ${response:0:200}" >&2
    if [[ -n "$response" ]]; then
        local ready
        ready=$(echo "$response" | jq -r '.value.ready // empty' 2>/dev/null) || true
        echo "[check_wda_status] ready=$ready" >&2
        if [[ "$ready" == "true" ]]; then
            echo "$response"
            return 0
        fi
    else
        echo "[check_wda_status] 无响应" >&2
    fi
    return 1
}

# 验证工具可用性
validate_tools() {
    local tools=("idevice_id" "xcrun" "jq" "tmux" "curl")
    local missing=()
    
    # 如果使用 iproxy，检查 iproxy 是否可用
    if [[ "$USE_IPROXY" == "true" ]]; then
        if ! command -v iproxy &> /dev/null; then
            missing+=("iproxy")
        fi
    fi
    
    # 如果直接连接，检查网络工具
    if [[ "$USE_IPROXY" == "false" ]]; then
        tools+=("ping" "nc")
    fi
    
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
    
    # 检查 Xcode 授权
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
    tmux new-session -d -s "iproxy" \
        "iproxy $local_port $remote_port -u $udid 2>&1 | tee ${LOG_DIR}/iproxy.log"
    
    echo -e "${GREEN}已启动 iproxy: localhost:$local_port -> device:$remote_port${NC}"
    
    # 等待 iproxy 就绪
    sleep 2
    
    # 设置 HOST 为 localhost
    HOST="127.0.0.1"
}

# 从日志中提取 WDA URL
extract_wda_url_from_log() {
    local log_file="$1"
    local max_wait=30
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        if [[ -f "$log_file" ]]; then
            local wda_url
            wda_url=$(grep -oE -m1 'ServerURLHere->http://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+' "$log_file" 2>/dev/null | sed 's/ServerURLHere->//' | head -1 || true)
            if [[ -n "$wda_url" ]]; then
                echo "$wda_url"
                return 0
            fi
        fi
        sleep 1
        wait_time=$((wait_time + 1))
    done
    
    return 1
}

# 启动 WDA 测试
start_wda_test() {
    local udid="$1"
    local log_file="${LOG_DIR}/wda.log"
    local cache_file="${CACHE_DIR}/wda.json"
    
    echo -e "${GREEN}启动 WDA 测试，设备 UDID: $udid${NC}"
    echo "日志文件: $log_file"
    echo "缓存文件: $cache_file"
    
    # 如果使用 iproxy，先启动端口转发
    if [[ "$USE_IPROXY" == "true" ]]; then
        start_iproxy "$udid" "$PORT" "$PORT"
    fi
    
    # 启动 tmux 会话运行 xcodebuild
    tmux new-session -d -s "wda" \
        "USE_PORT=$PORT xcodebuild -project \"$PROJECT_PATH\" -scheme \"$SCHEME\" -destination \"id=$udid\" test 2>&1 | tee \"$log_file\"; echo '测试完成，按任意键退出...'; read -n 1 -s"
    
    echo -e "${GREEN}已在 tmux 会话 'wda' 中启动 xcodebuild${NC}"
    echo "查看日志: tmux attach -t wda"
    
    # 从日志中提取实际的 WDA URL
    echo "等待 WDA 启动并获取服务器地址..."
    local actual_wda_url
    if actual_wda_url=$(extract_wda_url_from_log "$log_file"); then
        echo -e "${GREEN}检测到 WDA URL: $actual_wda_url${NC}"
        
        # 如果不是使用 iproxy，更新 HOST 为设备实际 IP
        if [[ "$USE_IPROXY" == "false" ]]; then
            local device_ip
            device_ip=$(echo "$actual_wda_url" | sed -n 's|http://\([^:]*\):.*|\1|p')
            local device_port
            device_port=$(echo "$actual_wda_url" | sed -n 's|.*:\([0-9]*\)$|\1|p')
            
            if [[ -n "$device_ip" ]]; then
                # 检查是否是私有 IP（设备 IP）
                if [[ "$device_ip" =~ ^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.) ]]; then
                    echo -e "${BLUE}更新连接地址为设备 IP: $device_ip:$device_port${NC}"
                    HOST="$device_ip"
                    PORT="${device_port:-$PORT}"
                fi
            fi
        fi
        # 尝试直接访问提取到的 WDA URL（设备可能已通过 WiFi 可达）
        if [[ "$USE_IPROXY" == "true" ]]; then
            local test_ip test_port
            test_ip=$(echo "$actual_wda_url" | sed -n 's|http://\([^:]*\):.*|\1|p')
            test_port=$(echo "$actual_wda_url" | sed -n 's|.*:\([0-9]*\)$|\1|p')
            if [[ -n "$test_ip" ]] && curl -s --connect-timeout 3 "${actual_wda_url}/status" > /dev/null 2>&1; then
                echo -e "${GREEN}WDA URL 直接可达，切换到直接连接${NC}"
                HOST="$test_ip"
                PORT="${test_port:-$PORT}"
                USE_IPROXY="false"
            fi
        fi
    else
        echo -e "${YELLOW}未能从日志中提取 WDA URL，使用默认配置${NC}"
    fi
    
    # 等待 WDA 完全启动
    echo "等待 WDA 完全就绪..."
    echo -e "${BLUE}检查 URL: http://${HOST}:${PORT}/status${NC}"
    local max_wait=60
    local wait_time=0
    local checked_url="http://${HOST}:${PORT}/status"
    while [[ $wait_time -lt $max_wait ]]; do
        sleep 2
        wait_time=$((wait_time + 2))
        if check_wda_status > /dev/null 2>&1; then
            echo -e "${GREEN}WDA 已就绪（等待时间: ${wait_time}s）${NC}"
            break
        fi
        # 首次失败时输出诊断信息
        if [[ $wait_time -eq 4 ]]; then
            local debug_resp
            debug_resp=$(curl -s --connect-timeout 3 -w '\nHTTP_CODE:%{http_code}' "${checked_url}" 2>&1) || true
            echo -e "${YELLOW}首次检查失败，诊断: ${debug_resp:0:300}${NC}"
        fi
        # iproxy 连续失败 ~15s 后尝试直接连接
        if [[ $wait_time -eq 15 ]] && [[ "$USE_IPROXY" == "true" ]] && [[ -n "${actual_wda_url:-}" ]]; then
            echo -e "${YELLOW}iproxy 连接超时，尝试直接连接 ${actual_wda_url}...${NC}"
            local fb_ip fb_port
            fb_ip=$(echo "$actual_wda_url" | sed -n 's|http://\([^:]*\):.*|\1|p')
            fb_port=$(echo "$actual_wda_url" | sed -n 's|.*:\([0-9]*\)$|\1|p')
            if [[ -n "$fb_ip" ]]; then
                HOST="$fb_ip"
                PORT="${fb_port:-$PORT}"
                USE_IPROXY="false"
                checked_url="http://${HOST}:${PORT}/status"
                echo -e "${GREEN}已切换到直接连接: ${checked_url}${NC}"
            fi
        fi
        echo "等待中... ($wait_time/$max_wait)"
    done
    
    # 获取最终状态
    local status_response
    status_response=$(check_wda_status) || true
    
    if [[ -n "$status_response" ]]; then
        local pid
        pid=$(echo "$status_response" | jq -r '.value.os.pid // "unknown"' 2>/dev/null) || pid="unknown"
        local session_id
        session_id=$(echo "$status_response" | jq -r '.sessionId // "none"' 2>/dev/null) || session_id="none"
        
        local output_json
        output_json=$(jq -n \
            --arg status "ready" \
            --arg udid "$udid" \
            --arg wda_endpoint "http://${HOST}:${PORT}" \
            --arg actual_wda_url "${actual_wda_url:-http://${HOST}:${PORT}}" \
            --arg pid "$pid" \
            --arg session_id "$session_id" \
            --arg use_iproxy "$USE_IPROXY" \
            --arg connection_type "$(detect_connection_type "$udid")" \
            '{
                status: $status,
                udid: $udid,
                wda_endpoint: $wda_endpoint,
                actual_wda_url: $actual_wda_url,
                pid: $pid,
                session_id: $session_id,
                use_iproxy: $use_iproxy,
                connection_type: $connection_type
            }')
        
        echo "$output_json" > "$cache_file"
        echo "$output_json" | jq '.'
        return 0
    else
        echo -e "${RED}WDA 未成功启动${NC}"
        local error_json
        error_json=$(jq -n \
            --arg status "error" \
            --arg udid "$udid" \
            --arg wda_endpoint "http://${HOST}:${PORT}" \
            --arg pid "unknown" \
            --arg session_id "none" \
            --arg use_iproxy "$USE_IPROXY" \
            '{
                status: $status,
                udid: $udid,
                wda_endpoint: $wda_endpoint,
                pid: $pid,
                session_id: $session_id,
                use_iproxy: $use_iproxy
            }')
        echo "$error_json" | jq '.'
        return 1
    fi
}

# 主流程
main() {
    echo -e "${GREEN}=== WDA 测试启动检查 ===${NC}"
    
    # 0. 获取设备 UDID（提前获取，用于后续判断）
    echo "0. 获取设备 UDID..."
    local udid
    if ! udid=$(get_device_udid); then
        echo -e "${RED}未找到连接的 iPhone 设备${NC}"
        exit 1
    fi
    echo -e "${GREEN}设备 UDID: $udid${NC}"
    
    # 1. 自动检测是否使用 iproxy
    echo "1. 检测连接方式..."
    auto_detect_iproxy "$udid"
    echo -e "${GREEN}连接方式: USE_IPROXY=$USE_IPROXY, HOST=$HOST${NC}"
    
    # 2. 检查 WDA 是否已启动
    echo "2. 检查 WDA 状态..."
    if status_response=$(check_wda_status); then
        echo -e "${GREEN}WDA 已启动，直接返回状态${NC}"
        echo "$status_response" | jq '.'
        
        local cache_file="${CACHE_DIR}/wda.json"
        local pid
        pid=$(echo "$status_response" | jq -r '.value.os.pid // "unknown"' 2>/dev/null) || pid="unknown"
        local session_id
        session_id=$(echo "$status_response" | jq -r '.sessionId // "none"' 2>/dev/null) || session_id="none"
        
        jq -n \
            --arg status "ready" \
            --arg udid "$udid" \
            --arg wda_endpoint "http://${HOST}:${PORT}" \
            --arg pid "$pid" \
            --arg session_id "$session_id" \
            '{
                status: $status,
                udid: $udid,
                wda_endpoint: $wda_endpoint,
                pid: $pid,
                session_id: $session_id
            }' > "$cache_file"
        
        exit 0
    fi
    echo "WDA 未启动，继续检查..."
    
    # 3. 验证工具可用性
    echo "3. 验证工具可用性..."
    if ! validate_tools; then
        exit 1
    fi
    echo -e "${GREEN}工具验证通过${NC}"
    
    # 4. 清理旧的 tmux session
    echo "4. 清理旧的 tmux session..."
    cleanup_old_tmux_sessions
    
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