#!/usr/bin/env bash
# test_all.sh — iOS Click Demo 全功能测试 v5
# 基于实战验证的方案
set -eo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../ios-use/scripts"
source "$SCRIPTS_DIR/common.sh"

WDA="http://${HOST}:${PORT}"
APP_BUNDLE_ID="com.jianfeng.iosclickdemo"
LOG_DIR="$PROJECT_ROOT/tmp/test-results"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/test_$(date +%Y%m%d_%H%M%S).log"

PASS=0; FAIL=0
log()  { echo -e "$1" | tee -a "$LOG_FILE"; }
pass() { PASS=$((PASS+1)); log "${GREEN}[PASS]${NC} $1"; }
fail() { FAIL=$((FAIL+1)); log "${RED}[FAIL]${NC} $1"; }

do_snap() { bash "$SCRIPTS_DIR/ios_wda_snapshot.sh" --no-screenshot > /dev/null 2>&1; sleep 1; }
latest_yaml() {
    local sd=$(ls -dt "$PROJECT_ROOT/tmp/wda-snapshot-"*/ 2>/dev/null | head -1)
    [[ -z "$sd" ]] && { echo ""; return; }
    ls -t "$sd$(date +%Y%m%d)/"*-source.yaml 2>/dev/null | head -1
}
yaml_val() {
    grep -F -A1 "$1" "$2" 2>/dev/null | sed -n 's/.*value: //p' | head -1 || true
}
yaml_rect() {
    grep -F -A3 "$1" "$2" 2>/dev/null | sed -n 's/.*rect: //p' | head -1 || true
}
extract_num() {
    printf '%s\n' "$1" | grep -oE '[0-9]+' | head -1 || true
}
find_el_id() {
    curl -s "$WDA/session/$SESSION/elements" \
        -H "Content-Type: application/json" \
        -d "{\"using\": \"$1\", \"value\": \"$2\"}" \
        | python3 -c "import sys,json; arr=json.load(sys.stdin).get('value',[]); print(arr[0].get('ELEMENT','') if arr else '')" 2>/dev/null
}
active_bundle_id() {
    curl -s "$WDA/wda/activeAppInfo" | jq -r '.value.bundleId // empty'
}
el_click() { curl -s -X POST "$WDA/session/$SESSION/element/$1/click" -H "Content-Type: application/json" -d '{}' > /dev/null; }
tap() { curl -s -X POST "$WDA/session/$SESSION/wda/tap" -H "Content-Type: application/json" -d "{\"x\": $1, \"y\": $2}" > /dev/null; }
w3c_tap() {
    curl -s -X POST "$WDA/session/$SESSION/actions" \
        -H "Content-Type: application/json" \
        -d "{\"actions\":[{\"type\":\"pointer\",\"id\":\"f1\",\"parameters\":{\"pointerType\":\"touch\"},\"actions\":[{\"type\":\"pointerMove\",\"duration\":0,\"origin\":\"viewport\",\"x\":$1,\"y\":$2},{\"type\":\"pointerDown\",\"button\":0},{\"type\":\"pause\",\"duration\":100},{\"type\":\"pointerUp\",\"button\":0}]}]}" > /dev/null
}
rect_center() {
    local r="$1"
    local x=$(echo "$r" | cut -d',' -f1)
    local y=$(echo "$r" | cut -d',' -f2 | cut -d' ' -f1)
    local w=$(echo "$r" | cut -d' ' -f2 | cut -d'x' -f1)
    local h=$(echo "$r" | cut -d'x' -f2)
    echo "$((x + w/2)) $((y + h/2))"
}
rect_midpoint_y() {
    local upper_rect="$1"
    local lower_rect="$2"
    local upper_y=$(echo "$upper_rect" | cut -d',' -f2 | cut -d' ' -f1)
    local upper_h=$(echo "$upper_rect" | cut -d'x' -f2)
    local lower_y=$(echo "$lower_rect" | cut -d',' -f2 | cut -d' ' -f1)
    local upper_bottom=$((upper_y + upper_h))
    echo "$((upper_bottom + (lower_y - upper_bottom)/2))"
}

# ─── main ───
log ""
log "${BLUE}══════════════════════════════════════${NC}"
log "${BLUE}  iOS Click Demo v5${NC}"
log "${BLUE}══════════════════════════════════════${NC}"

# Setup
log ""
log ">> Setup: WDA check..."
check_wda || { fail "WDA unreachable"; exit 1; }
pass "WDA reachable"

log ">> Setup: create session..."
SESSION=$(curl -s -X POST "$WDA/session" \
    -H "Content-Type: application/json" \
    -d '{"capabilities": {"firstMatch": [{"platformName": "ios"}]}}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['value']['sessionId'])" 2>/dev/null || echo "")
[[ -n "$SESSION" ]] || { fail "session create failed"; exit 1; }
log "  SESSION=$SESSION"
pass "Session created"

log ">> Setup: open IOSClickDemo..."
# Deterministic validation needs a clean app state.
curl -s -X POST "$WDA/session/$SESSION/wda/apps/terminate" \
    -H "Content-Type: application/json" \
    -d "{\"bundleId\": \"$APP_BUNDLE_ID\"}" > /dev/null 2>/dev/null || true
sleep 1
curl -s -X POST "$WDA/session/$SESSION/wda/apps/launch" \
    -H "Content-Type: application/json" \
    -d "{\"bundleId\": \"$APP_BUNDLE_ID\"}" > /dev/null
sleep 5
do_snap; Y=$(latest_yaml)
if [[ "$(head -1 "$Y")" != *"IOSClickDemo"* ]]; then
    ICON=$(grep -A3 "IOSClickDemo" "$Y" | grep "rect:" | head -1 | grep -oE '[0-9]+,[0-9]+ [0-9]+x[0-9]+')
    if [[ -n "$ICON" ]]; then
        read CX CY <<< "$(rect_center "$ICON")"
        tap $CX $CY; sleep 5; do_snap; Y=$(latest_yaml)
    fi
fi
[[ "$(head -1 "$Y")" == *"IOSClickDemo"* ]] || { fail "failed to open app"; exit 1; }
pass "IOSClickDemo opened"

log ">> Setup: dismiss keyboard..."
if grep -q "Keyboard" "$Y"; then tap 200 30; sleep 2; do_snap; Y=$(latest_yaml); fi
pass "Keyboard dismissed"

# ═══════════ TEST 1: Tap Button via element/click ═══════════
log ""
log "${BLUE}--- Test 1: Tap Button (element click) ---${NC}"
T1=$(extract_num "$(yaml_val "tap-demo.status" "$Y")"); T1=${T1:-0}
log "  initial count: $T1"

EL=$(find_el_id "accessibility id" "tap-demo.button")
if [[ -n "$EL" ]]; then
    el_click "$EL"; sleep 2; do_snap; Y=$(latest_yaml)
    T2=$(extract_num "$(yaml_val "tap-demo.status" "$Y")"); T2=${T2:-0}
    log "  after click: $T2"
    [[ "$T2" -gt "$T1" ]] && pass "Tap button: $T1 -> $T2" || fail "Tap button: no change ($T1)"
else
    fail "element not found: tap-demo.button"
fi

# ═══════════ TEST 2: Coordinate Tap (Direct RemoteXPC) ═══════════
log ""
log "${BLUE}--- Test 2: Coordinate Tap (Direct RemoteXPC) ---${NC}"
D1=$(extract_num "$(yaml_val "Direct tap received" "$Y")"); D1=${D1:-0}
log "  initial count: $D1"

# Derive the hidden tap zone from nearby accessible elements.
STATUS_RECT=$(yaml_rect "direct-tap.status" "$Y")
ZONE_LABEL_RECT=$(yaml_rect "Tap Anywhere In This Zone" "$Y")
read TAP_X _ <<< "$(rect_center "$ZONE_LABEL_RECT")"
TAP_Y=$(rect_midpoint_y "$STATUS_RECT" "$ZONE_LABEL_RECT")
TAP_X=${TAP_X:-201}
TAP_Y=${TAP_Y:-450}
if [[ "$TAP_Y" -lt 100 ]]; then
    TAP_Y=450
fi
log "  coords: ($TAP_X, $TAP_Y)"
tap $TAP_X $TAP_Y; sleep 2; do_snap; Y=$(latest_yaml)
D2=$(extract_num "$(yaml_val "Direct tap received" "$Y")"); D2=${D2:-0}
if [[ "$D2" -le "$D1" ]]; then
    log "  /wda/tap missed; retry with W3C Actions"
    w3c_tap $TAP_X $TAP_Y; sleep 2; do_snap; Y=$(latest_yaml)
    D2=$(extract_num "$(yaml_val "Direct tap received" "$Y")"); D2=${D2:-0}
fi
log "  after tap: $D2"
[[ "$D2" -gt "$D1" ]] && pass "Coord tap: $D1 -> $D2" || fail "Coord tap: no change ($D1)"

# ═══════════ TEST 3: Text Input ═══════════
log ""
log "${BLUE}--- Test 3: Text Input ---${NC}"
TX1=$(yaml_val "text-demo.field" "$Y")
log "  initial: '$TX1'"

EL=$(find_el_id "accessibility id" "text-demo.field")
if [[ -n "$EL" ]]; then
    curl -s -X POST "$WDA/session/$SESSION/element/$EL/value" \
        -H "Content-Type: application/json" \
        -d '{"value": ["_","A","D","D","E","D"]}' > /dev/null
    sleep 2; tap 200 30; sleep 1; do_snap; Y=$(latest_yaml)
    TX2=$(yaml_val "text-demo.field" "$Y")
    log "  after: '$TX2'"
    if echo "$TX2" | grep -q "_ADDED"; then
        pass "Text append: _ADDED appended"
    else
        fail "Text append: unexpected result '$TX2'"
    fi
else
    fail "element not found: text-demo.field"
fi

# ═══════════ TEST 4: Swipe / Scroll ═══════════
log ""
log "${BLUE}--- Test 4: Swipe (element swipe UP) ---${NC}"

# Find scroll view element first
SV=$(find_el_id "accessibility id" "demo.scrollView")
if [[ -z "$SV" ]]; then
    fail "scroll view element not found"
else
    log "  scrollView element: $SV"
    C1=$(grep "swipe-demo.cardLabel" "$Y" | grep -oE 'cardLabel\.[0-9]+' | sed 's/cardLabel\.//' | sort -n | tail -1 || echo "0")
    C1=${C1:-0}
    log "  initial max card: $C1"

    GOT7=0; CM=$C1
    for i in $(seq 1 10); do
        curl -s -X POST "$WDA/session/$SESSION/wda/element/$SV/swipe" \
            -H "Content-Type: application/json" \
            -d '{"direction": "up", "velocity": 1200}' > /dev/null
        sleep 2; do_snap; Y=$(latest_yaml)
        CM=$(grep "swipe-demo.cardLabel" "$Y" | grep -oE 'cardLabel\.[0-9]+' | sed 's/cardLabel\.//' | sort -n | tail -1 || echo "0")
        CM=${CM:-0}
        log "  swipe #$i: max card = $CM"
        [[ "$CM" -ge 7 ]] && { GOT7=1; break; }
    done

    if [[ "$GOT7" -eq 1 ]]; then
        pass "Swipe: reached card $CM (${i} swipes)"
    elif [[ "$CM" -gt "$C1" ]]; then
        pass "Swipe: progressed ($C1 -> $CM)"
    else
        fail "Swipe: no progress ($C1 -> $CM)"
    fi
fi

# ─── SUMMARY ───
log ""
log "${BLUE}══════════════════════════════════════${NC}"
log "Total: $((PASS+FAIL)) | ${GREEN}PASS $PASS${NC} | ${RED}FAIL $FAIL${NC}"
log "Log: $LOG_FILE"

curl -s -X POST "$WDA/session/$SESSION/wda/pressButton" \
    -H "Content-Type: application/json" -d '{"name": "home"}' > /dev/null 2>/dev/null || true

exit $FAIL
