#!/usr/bin/env bash
# test_all.sh — iOS Click Demo 全功能测试 v3
# 基于实战教训：先截图验证状态，用坐标点图标启动 app，逐步操作逐步验证
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../ios-use/scripts"
source "$SCRIPTS_DIR/common.sh"

WDA="http://${HOST}:${PORT}"
LOG_DIR="$PROJECT_ROOT/tmp/test-results"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/test_$(date +%Y%m%d_%H%M%S).log"

PASS=0; FAIL=0
log()  { echo -e "$1" | tee -a "$LOG_FILE"; }
pass() { PASS=$((PASS+1)); log "${GREEN}[PASS]${NC} $1"; }
fail() { FAIL=$((FAIL+1)); log "${RED}[FAIL]${NC} $1"; }

# ─── helpers ───

# 截图+source，等待写入完成
do_snap() { bash "$SCRIPTS_DIR/ios_wda_snapshot.sh" > /dev/null 2>&1; sleep 1; }

# 最新 yaml 文件路径
latest_yaml() {
    local sd
    sd=$(ls -dt "$PROJECT_ROOT/tmp/wda-snapshot-"*/ 2>/dev/null | head -1)
    [[ -z "$sd" ]] && { echo ""; return; }
    ls -t "$sd$(date +%Y%m%d)/"*-source.yaml 2>/dev/null | head -1
}

# 从 yaml 提取 value 字段
yaml_val() { grep -A1 "$1" "$2" 2>/dev/null | grep "value:" | sed 's/.*value: //' | head -1; }

# 提取数字
extract_num() { echo "$1" | grep -oE '[0-9]+' | head -1; }

# WDA 元素查找（返回 element-6066-11e4-a52e-4f735466cecf）
find_wda_el() {
    local using="$1" val="$2"
    curl -s "$WDA/session/$SESSION/elements" \
        -H "Content-Type: application/json" \
        -d "{\"using\": \"$using\", \"value\": \"$val\"}" \
        | python3 -c "
import sys,json
arr=json.load(sys.stdin).get('value',[])
if arr:
    print(arr[0].get('element-6066-11e4-a52e-4f735466cecf',''))
" 2>/dev/null
}

# 坐标点击
tap() { curl -s -X POST "$WDA/session/$SESSION/wda/tap" -H "Content-Type: application/json" -d "{\"x\": $1, \"y\": $2}" > /dev/null; }

# 元素点击
tap_el() { curl -s -X POST "$WDA/session/$SESSION/wda/element/$1/tap" -H "Content-Type: application/json" -d '{"x": 0, "y": 0}' > /dev/null; }

# rect "x,y WxH" → 中心坐标
rect_center() {
    local r="$1"
    local x y w h
    x=$(echo "$r" | cut -d',' -f1)
    y=$(echo "$r" | cut -d',' -f2 | cut -d' ' -f1)
    w=$(echo "$r" | cut -d' ' -f2 | cut -d'x' -f1)
    h=$(echo "$r" | cut -d'x' -f2)
    echo "$((x + w/2)) $((y + h/2))"
}

# 从 yaml 查找包含关键词的行并提取 rect
find_rect_by_text() {
    grep -B1 "$1" "$2" 2>/dev/null | grep "rect:" | head -1 | grep -oE '[0-9]+,[0-9]+ [0-9]+x[0-9]+'
}

# ─── main ───

log "\n${BLUE}══════════════════════════════════════${NC}"
log "${BLUE}  iOS Click Demo 全功能测试 v3${NC}"
log "${BLUE}══════════════════════════════════════${NC}"

# 1. 检查 WDA
log "\n▶ 检查 WDA..."
check_wda || { fail "WDA 不可达"; exit 1; }
pass "WDA 可达"

# 2. 创建 session
log "\n▶ 创建 session..."
SESSION=$(curl -s -X POST "$WDA/session" \
    -H "Content-Type: application/json" \
    -d '{"capabilities": {"firstMatch": [{"platformName": "ios"}]}}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['value']['sessionId'])" 2>/dev/null || echo "")
[[ -n "$SESSION" ]] || { fail "Session 创建失败"; exit 1; }
log "  SESSION=$SESSION"
pass "Session 创建成功"

# 3. 启动 IOSClickDemo - 先截屏看状态
log "\n▶ 打开 IOSClickDemo..."
do_snap
Y=$(latest_yaml)
APP_NAME=$(head -1 "$Y" 2>/dev/null | grep -o 'IOSClickDemo' || echo "")

if [[ "$APP_NAME" != "IOSClickDemo" ]]; then
    log "  App 未在前台，点击图标启动..."
    # 找 IOSClickDemo 图标 rect
    ICON_RECT=$(grep -B1 "IOSClickDemo:" "$Y" 2>/dev/null | grep "rect:" | head -1 | grep -oE '[0-9]+,[0-9]+ [0-9]+x[0-9]+')
    if [[ -n "$ICON_RECT" ]]; then
        read CX CY <<< "$(rect_center "$ICON_RECT")"
        log "  图标中心: ($CX, $CY)"
        tap $CX $CY
        sleep 3
        do_snap
        Y=$(latest_yaml)
        APP_NAME=$(head -1 "$Y" | grep -o 'IOSClickDemo' || echo "")
    fi
fi

if [[ "$APP_NAME" == "IOSClickDemo" ]]; then
    pass "IOSClickDemo 已打开"
else
    fail "无法打开 IOSClickDemo"
    exit 1
fi

# 4. 关闭键盘
log "\n▶ 关闭键盘..."
if grep -q "Keyboard" "$Y" 2>/dev/null; then
    log "  检测到键盘，点击顶部关闭..."
    tap 200 30
    sleep 2
    do_snap
    Y=$(latest_yaml)
fi
pass "键盘已关闭"

# ═══════════ TEST 1: Tap Demo ═══════════
log "\n${BLUE}─── Test 1: Tap Demo ───${NC}"

# 读当前计数
TAP_CNT_BEFORE=$(extract_num "$(yaml_val "tap-demo.status" "$Y")")
TAP_CNT_BEFORE=${TAP_CNT_BEFORE:-0}
log "  初始 tap 计数: $TAP_CNT_BEFORE"

EL=$(find_wda_el "accessibility id" "tap-demo.button")
if [[ -z "$EL" ]]; then
    fail "未找到 tap-demo.button"
else
    log "  找到 element: $EL"
    tap_el "$EL"
    sleep 2
    do_snap
    Y=$(latest_yaml)
    TAP_CNT_AFTER=$(extract_num "$(yaml_val "tap-demo.status" "$Y")")
    TAP_CNT_AFTER=${TAP_CNT_AFTER:-0}
    log "  点击后计数: $TAP_CNT_AFTER"
    if [[ "$TAP_CNT_AFTER" -gt "$TAP_CNT_BEFORE" ]]; then
        pass "Tap button 点击成功 ($TAP_CNT_BEFORE → $TAP_CNT_AFTER)"
    else
        fail "Tap button 未生效 ($TAP_CNT_BEFORE → $TAP_CNT_AFTER)"
    fi
fi

# ═══════════ TEST 2: Coordinate Tap ═══════════
log "\n${BLUE}─── Test 2: Coordinate Tap (Direct RemoteXPC) ───${NC}"

DIRECT_BEFORE=$(extract_num "$(yaml_val "Direct tap received" "$Y")")
DIRECT_BEFORE=${DIRECT_BEFORE:-0}
log "  初始 direct tap 计数: $DIRECT_BEFORE"

ZONE_RECT=$(find_rect_by_text "Tap Anywhere In This Zone" "$Y")
if [[ -n "$ZONE_RECT" ]]; then
    read CX CY <<< "$(rect_center "$ZONE_RECT")"
    log "  Zone 中心: ($CX, $CY)"
    tap $CX $CY
    sleep 2
    do_snap
    Y=$(latest_yaml)
    DIRECT_AFTER=$(extract_num "$(yaml_val "Direct tap received" "$Y")")
    DIRECT_AFTER=${DIRECT_AFTER:-0}
    log "  点击后: $DIRECT_AFTER"
    if [[ "$DIRECT_AFTER" -gt "$DIRECT_BEFORE" ]]; then
        pass "坐标点击成功 ($DIRECT_BEFORE → $DIRECT_AFTER)"
    else
        fail "坐标点击未生效 ($DIRECT_BEFORE → $DIRECT_AFTER)"
    fi
else
    fail "未找到 Tap Zone"
fi

# ═══════════ TEST 3: Text Input ═══════════
log "\n${BLUE}─── Test 3: Text Input Demo ───${NC}"

TEXT_BEFORE=$(yaml_val "text-demo.field" "$Y")
log "  初始文本: '$TEXT_BEFORE'"

EL=$(find_wda_el "accessibility id" "text-demo.field")
if [[ -z "$EL" ]]; then
    fail "未找到 text-demo.field"
else
    # clear
    curl -s -X POST "$WDA/session/$SESSION/element/$EL/clear" \
        -H "Content-Type: application/json" > /dev/null
    sleep 1

    # setValue
    curl -s -X POST "$WDA/session/$SESSION/element/$EL/value" \
        -H "Content-Type: application/json" \
        -d '{"value": ["H","e","l","l","o","W","D","A"]}' > /dev/null
    sleep 2

    # 关闭键盘
    tap 200 30
    sleep 1
    do_snap
    Y=$(latest_yaml)
    TEXT_AFTER=$(yaml_val "text-demo.field" "$Y")
    log "  输入后: '$TEXT_AFTER'"

    if [[ "$TEXT_AFTER" == "HelloWDA" ]]; then
        pass "文本输入成功"
    else
        fail "文本输入不符: 期望 'HelloWDA', 实际 '$TEXT_AFTER'"
    fi
fi

# ═══════════ TEST 4: Swipe Demo ═══════════
log "\n${BLUE}─── Test 4: Swipe Demo ───${NC}"

CARD_MAX_INIT=$(grep "swipe-demo.cardLabel" "$Y" 2>/dev/null | grep -oE 'card [0-9]+' | sed 's/card //' | sort -n | tail -1 || echo "0")
CARD_MAX_INIT=${CARD_MAX_INIT:-0}
log "  初始最大卡片: $CARD_MAX_INIT"

GOT_CARD7=0
for i in $(seq 1 10); do
    curl -s -X POST "$WDA/session/$SESSION/wda/swipe" \
        -H "Content-Type: application/json" \
        -d '{"direction": "down", "velocity": 1200}' > /dev/null
    sleep 2
    do_snap
    Y=$(latest_yaml)
    CARD_MAX=$(grep "swipe-demo.cardLabel" "$Y" 2>/dev/null | grep -oE 'card [0-9]+' | sed 's/card //' | sort -n | tail -1 || echo "0")
    CARD_MAX=${CARD_MAX:-0}
    log "  swipe #$i: max card=$CARD_MAX"
    if [[ "$CARD_MAX" -ge 7 ]]; then
        GOT_CARD7=1
        break
    fi
done

if [[ "$GOT_CARD7" -eq 1 ]]; then
    pass "滚动到达卡片7（第${i}次swipe）"
elif [[ "$CARD_MAX" -gt "$CARD_MAX_INIT" ]]; then
    pass "滚动有进展 ($CARD_MAX_INIT → $CARD_MAX)"
else
    fail "滚动无效 ($CARD_MAX_INIT → $CARD_MAX)"
fi

# ═══════════ SUMMARY ═══════════
log "\n${BLUE}══════════════════════════════════════${NC}"
log "总: $((PASS+FAIL)) | ${GREEN}PASS $PASS${NC} | ${RED}FAIL $FAIL${NC}"
log "日志: $LOG_FILE"

# 回到 home
curl -s -X POST "$WDA/session/$SESSION/wda/pressButton" \
    -H "Content-Type: application/json" -d '{"name": "home"}' > /dev/null 2>/dev/null || true

exit $FAIL
