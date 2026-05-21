#!/usr/bin/env bash
# wda_guard.sh
# 检测并保守处理常见阻塞层：Alert / Sheet / Keyboard / extra Window
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

MODE="check"
DISMISS_KEYBOARD=0
ALLOW_CONFIRM=0
MAX_ACTIONS=2
WDA="http://${HOST}:${PORT}"

SAFE_BUTTONS=("Cancel" "Close" "Not Now" "Later" "Dismiss" "Don’t Allow" "Don't Allow")
CONFIRM_BUTTONS=("OK" "Allow" "Undo")

usage() {
    printf '%s\n' "Usage: $0 [--check] [--dismiss] [--dismiss-keyboard] [--allow-confirm] [--max-actions N]"
    printf '%s\n' "  --check             只检查阻塞层（默认）"
    printf '%s\n' "  --dismiss           尝试保守关闭 Alert / Sheet"
    printf '%s\n' "  --dismiss-keyboard  允许尝试关闭键盘"
    printf '%s\n' "  --allow-confirm     允许点击 OK / Allow / Undo 这类确认按钮"
    printf '%s\n' "  --max-actions N     最多尝试 N 次关闭动作（默认 2）"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)
            MODE="check"
            shift
            ;;
        --dismiss)
            MODE="dismiss"
            shift
            ;;
        --dismiss-keyboard)
            DISMISS_KEYBOARD=1
            shift
            ;;
        --allow-confirm)
            ALLOW_CONFIRM=1
            shift
            ;;
        --max-actions)
            MAX_ACTIONS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "未知参数: $1"
            usage
            ;;
    esac
done

fetch_source_json() {
    curl -s --connect-timeout 5 --max-time 10 "$WDA/source?format=json"
}

blocker_summary() {
    local source_json="$1"
    printf '%s' "$source_json" | jq -r '
      [
        ([.. | objects | select(.type? == "Alert" or .type? == "Sheet") | {type: .type, name: (.name // .label // .value // "unnamed")}] | .[] | "\(.type):\(.name)"),
                ([.. | objects | select(.type? == "Keyboard") | "Keyboard"] | .[])
      ] | .[]
    '
}

has_alert_or_sheet() {
    local source_json="$1"
    printf '%s' "$source_json" | jq -e '.. | objects | select(.type? == "Alert" or .type? == "Sheet")' >/dev/null
}

has_keyboard() {
    local source_json="$1"
    printf '%s' "$source_json" | jq -e '.. | objects | select(.type? == "Keyboard")' >/dev/null
}

find_named_element() {
    local session_id="$1"
    local name="$2"
    curl -s "$WDA/session/$session_id/elements" \
        -H "Content-Type: application/json" \
        -d "{\"using\": \"name\", \"value\": \"$name\"}" \
        | jq -r '.value[0].ELEMENT // .value[0]["element-6066-11e4-a52e-4f735466cecf"] // empty'
}

click_named_element() {
    local session_id="$1"
    local name="$2"
    local element_id
    element_id=$(find_named_element "$session_id" "$name")
    [[ -n "$element_id" ]] || return 1

    curl -s -X POST "$WDA/session/$session_id/element/$element_id/click" \
        -H "Content-Type: application/json" \
        -d '{}' >/dev/null
    return 0
}

dismiss_keyboard() {
    local session_id="$1"
    curl -s -X POST "$WDA/session/$session_id/wda/tap" \
        -H "Content-Type: application/json" \
        -d '{"x": 200, "y": 30}' >/dev/null
}

attempt_dismiss() {
    local session_id="$1"
    local source_json="$2"
    local button_name

    for button_name in "${SAFE_BUTTONS[@]}"; do
        if printf '%s' "$source_json" | jq -e --arg button_name "$button_name" '.. | objects | select(.type? == "Button" and (.name == $button_name or .label == $button_name or .value == $button_name))' >/dev/null; then
            log_warn "检测到阻塞层，尝试点击安全按钮: $button_name"
            click_named_element "$session_id" "$button_name" && return 0
        fi
    done

    if [[ "$ALLOW_CONFIRM" == "1" ]]; then
        for button_name in "${CONFIRM_BUTTONS[@]}"; do
            if printf '%s' "$source_json" | jq -e --arg button_name "$button_name" '.. | objects | select(.type? == "Button" and (.name == $button_name or .label == $button_name or .value == $button_name))' >/dev/null; then
                log_warn "检测到阻塞层，尝试点击确认按钮: $button_name"
                click_named_element "$session_id" "$button_name" && return 0
            fi
        done
    fi

    if [[ "$DISMISS_KEYBOARD" == "1" ]] && has_keyboard "$source_json"; then
        log_warn "检测到键盘，尝试点击顶部空白区关闭"
        dismiss_keyboard "$session_id"
        return 0
    fi

    return 1
}

main() {
    ensure_wda_ready >/dev/null
    local source_json
    source_json=$(fetch_source_json)

    if [[ -z "$source_json" ]]; then
        log_error "无法获取 WDA source"
        exit 1
    fi

    local summary
    summary=$(blocker_summary "$source_json" || true)

    if [[ -z "$summary" ]]; then
        log_success "未检测到阻塞层"
        exit 0
    fi

    log_warn "检测到潜在阻塞层:"
    printf '%s\n' "$summary" | sed 's/^/  - /'

    if [[ "$MODE" != "dismiss" ]]; then
        exit 2
    fi

    local session_id
    session_id=$(bash "$SCRIPT_DIR/wda_session.sh")
    local action_count=0

    while [[ $action_count -lt $MAX_ACTIONS ]]; do
        if ! has_alert_or_sheet "$source_json" && ! { [[ "$DISMISS_KEYBOARD" == "1" ]] && has_keyboard "$source_json"; }; then
            log_success "阻塞层已消失"
            exit 0
        fi

        attempt_dismiss "$session_id" "$source_json" || break
        action_count=$((action_count + 1))
        sleep 1
        source_json=$(fetch_source_json)
    done

    if ! has_alert_or_sheet "$source_json" && ! { [[ "$DISMISS_KEYBOARD" == "1" ]] && has_keyboard "$source_json"; }; then
        log_success "阻塞层已消失"
        exit 0
    fi

    log_warn "阻塞层仍存在，需要人工确认或更具体策略"
    blocker_summary "$source_json" | sed 's/^/  - /'
    exit 2
}

main "$@"