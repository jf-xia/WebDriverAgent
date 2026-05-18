#!/usr/bin/env bash
# ios_wda_snapshot.sh
# 获取 WDA 页面源码和截图，用于 ReAct 循环的 observe 阶段
set -euo pipefail

# 获取项目根目录（脚本位于 skills/ios-use/scripts/）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/tmp/wda.json"

# 加载公共函数
source "$SCRIPT_DIR/common.sh"

# 脚本专属默认值
OUTPUT_DIR=""
PYTHON_SCRIPT="$(dirname "$0")/source.json_to_yaml.py"

# 检查 Python 转换脚本是否存在
if [[ ! -f "$PYTHON_SCRIPT" ]]; then
    echo -e "${YELLOW}警告: Python 转换脚本不存在: $PYTHON_SCRIPT${NC}" >&2
    PYTHON_SCRIPT=""
fi

usage() {
    echo "Usage: $0 [--host <HOST>] [--port <PORT>]"
    echo "  --host    WDA 主机地址（默认从 wda.json 读取）"
    echo "  --port    WDA 端口（默认从 wda.json 读取）"
    exit 1
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --host)
            HOST="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}未知参数: $1${NC}" >&2
            usage
            ;;
    esac
done

# 获取下一个序号
get_next_number() {
    local dir="$1"
    local max=0

    if [[ -d "$dir" ]]; then
        local nums
        nums=$(find "$dir" -name "???-source.json" -type f 2>/dev/null | \
            xargs -I{} basename {} -source.json | \
            grep -E '^[0-9]{3}$' | \
            sort -n | tail -1 || true)
        if [[ -n "$nums" ]]; then
            max=$((10#$nums))
        fi
    fi

    # 超过 999 清空目录重新开始
    if [[ $max -ge 999 ]]; then
        rm -rf "${dir:?}"/*
        max=0
    fi

    printf "%03d" $((max + 1))
}

# 获取页面源码
fetch_source() {
    local output_file="$1"
    # /wda/accessibleSource
    local url="http://${HOST}:${PORT}/source?format=json&excluded_attributes=frame,nativeFrame,enabled,visible,accessible,focused,placeholderValue,minValue,maxValue"

    local response
    response=$(curl -s --connect-timeout 5 "$url" 2>/dev/null) || {
        echo -e "${RED}获取 source 失败: $url${NC}" >&2
        return 1
    }

    echo "$response" > "$output_file"
}

# 获取截图并转换为 JPEG
fetch_screenshot() {
    local output_file="$1"
    local url="http://${HOST}:${PORT}/screenshot"
    local tmp_png
    tmp_png=$(mktemp /tmp/wda-screenshot-XXXXXX.png)

    # 获取截图
    local response
    response=$(curl -s --connect-timeout 5 "$url" 2>/dev/null) || {
        echo -e "${RED}获取截图失败: $url${NC}" >&2
        rm -f "$tmp_png"
        return 1
    }

    # 解码 base64 并保存为 PNG
    echo "$response" | jq -r '.value' | base64 --decode > "$tmp_png" 2>/dev/null || {
        echo -e "${RED}解码截图失败${NC}" >&2
        rm -f "$tmp_png"
        return 1
    }

    # 转换为 JPEG 并 resize 到 1200px
    sips -Z 1200 -s format jpeg "$tmp_png" --out "$output_file" >/dev/null 2>&1 || {
        echo -e "${RED}转换截图失败${NC}" >&2
        rm -f "$tmp_png"
        return 1
    }

    rm -f "$tmp_png"
}

# 主流程
main() {
    # 检查 WDA 连接
    if ! check_wda; then
        exit 1
    fi

    local udid
    udid=$(jq -r '.udid // empty' "$CONFIG_FILE" 2>/dev/null)

    # 构建输出目录
    local date_str
    date_str=$(date +%Y%m%d)
    OUTPUT_DIR="$PROJECT_ROOT/tmp/wda-snapshot-${udid}/${date_str}"
    mkdir -p "$OUTPUT_DIR"

    # 获取序号
    local num
    num=$(get_next_number "$OUTPUT_DIR")

    # 获取 source
    local source_file="${OUTPUT_DIR}/${num}-source.json"
    fetch_source "$source_file"

    # 转换为 YAML 格式
    local yaml_file="${OUTPUT_DIR}/${num}-source.yaml"
    if [[ -n "$PYTHON_SCRIPT" ]] && [[ -f "$PYTHON_SCRIPT" ]]; then
        python3 "$PYTHON_SCRIPT" "$source_file" "$yaml_file" --remove-decoration 2>/dev/null || {
            yaml_file="$source_file"
        }
    else
        yaml_file="$source_file"
    fi

    # 获取截图
    local screenshot_file="${OUTPUT_DIR}/${num}-screenshot.jpg"
    fetch_screenshot "$screenshot_file"

    # 输出文件路径
    echo "$yaml_file"
    echo "$screenshot_file"
}

main "$@"
