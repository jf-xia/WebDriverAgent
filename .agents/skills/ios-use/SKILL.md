---
name: ios-use
description: "操作 iOS / iPhone 真机与模拟器。用于 WebDriverAgent 场景下的设备发现、WDA 启动、Session 创建、页面读取、元素交互、手势、系统控制、故障恢复。适用于 xcodebuild、simctl、curl 或 WDA REST API。"
argument-hint: "描述任务，例如：启动 WDA 并创建 session；读取 source 后点击按钮"
user-invocable: true
---

# iOS iPhone 使用能力

## 快速开始

**必须执行**:
- $SCRIPTS=./.agents/skills/ios-use/scripts
- $WDA=http://127.0.0.1:8100
- $SCRIPTS/ios_wda_test_on_iphone.sh - 启动/确保 WDA 可用（已运行时返回成功）
- $SCRIPTS/wda_session.sh - 默认每次创建新 session；如需显式复用当前 session，使用 `ensure`

### 默认流程 - YAML 观察优先

1. `$SCRIPTS/ios_wda_snapshot.sh` 默认同时抓 source/YAML 和 screenshot
2. 高频轮询、测试脚本、只关心结构化信息时，显式加 `--no-screenshot`
3. 观察 YAML + screenshot → 决策 → 执行 → 再抓 snapshot 验证。YAML 负责结构，screenshot 负责视觉交叉确认
4. 每轮任务默认创建新 session。若同一段命令需要固定 session，先 `SESSION=$($SCRIPTS/wda_session.sh)`，后续复用 `$SESSION`
5. 坐标类操作前，先排除阻塞层。优先运行 `$SCRIPTS/wda_guard.sh --check`
6. 对无 accessibility id 的点击区，不要长期依赖写死坐标。优先从相邻可见元素的 `rect` 推导点击点；动作后必须验证状态变化

**核心原则：每次操作前必须截屏观察当前状态，禁止预测式连续操作。**

## 通用策略

这个 skill 三层组织：

1. 基础能力：WDA ensure、session、snapshot、tap、element click、type、pressButton
2. 通用策略：打开 App、切换 App、滚动查找、输入长文本、弹窗处理
3. 任务组合：打开 Notes、新建 note、填表、截图取证、切换设置项

任务描述越通用，越优先复用第 1、2 层。不要把具体 App 流程固化成唯一入口。

## 多次操作失败请使用代码库研究 

[codebase-research.md](references/codebase-research.md) 

# 应用与设备控制

```bash
# 获取已安装应用
xcrun devicectl device info apps --device <UDID>

# 启动应用 — 始终使用 `launch`（简化流程），主屏点击作为最后兜底
SESSION=$($SCRIPTS/wda_session.sh)

# 直接使用 launch 启动目标 App（无论是否已激活）
curl -s -X POST $WDA/session/$SESSION/wda/apps/launch \
  -H "Content-Type: application/json" \
  -d '{"bundleId": "com.apple.mobilenotes"}'

# 只有在无法通过弹窗处理、回滚滚动、关闭键盘恢复状态时，才用 terminate -> launch 做最后兜底
# 不要把重启 App 当作默认恢复路径
curl -s -X POST $WDA/session/$SESSION/wda/apps/terminate \
  -H "Content-Type: application/json" \
  -d '{"bundleId": "com.apple.mobilenotes"}'
curl -s -X POST $WDA/session/$SESSION/wda/apps/launch \
  -H "Content-Type: application/json" \
  -d '{"bundleId": "com.apple.mobilenotes"}'

# 验证当前前台 App（如需进一步校验，可依据返回值判断）
curl -s $WDA/wda/activeAppInfo | jq .
$SCRIPTS/ios_wda_snapshot.sh

# 检查是否有系统弹窗/键盘挡住操作
$SCRIPTS/wda_guard.sh --check

# 保守关闭常见 Alert / Sheet（默认只点 Cancel / Close / Not Now / Dismiss / Don't Allow 一类安全按钮）
$SCRIPTS/wda_guard.sh --dismiss

# 如需顺带尝试收起键盘，再显式加参数
$SCRIPTS/wda_guard.sh --dismiss --dismiss-keyboard

# 主屏兜底（只有在 launch 未将 App 带到前台时才使用）
# 注意：多数情况下 launch 应足以启动或激活应用；若遇到启动失败再回主屏点击图标。
curl -s -X POST $WDA/session/$SESSION/wda/pressButton \
  -H "Content-Type: application/json" \
  -d '{"name": "home"}'
$SCRIPTS/ios_wda_snapshot.sh
# 从 YAML / screenshot 取图标坐标后点击（仅在必须时）
curl -s -X POST $WDA/session/$SESSION/wda/tap \
  -H "Content-Type: application/json" \
  -d '{"x": 62, "y": 635}'
sleep 5
$SCRIPTS/ios_wda_snapshot.sh

# 系统按键 "home", "volumeUp", "volumeDown", "action", "camera"
curl -s -X POST   $WDA/session/$($SCRIPTS/wda_session.sh)/wda/pressButton  -H "Content-Type: application/json" -d '{"name": "volumeUp"}' 
```

## 手势

### 点击

```bash
# 坐标点击（无元素时为屏幕绝对坐标）
curl -s -X POST $WDA/session/$($SCRIPTS/wda_session.sh)/wda/tap \
  -H "Content-Type: application/json" \
  -d '{"x": 200, "y": 300}'

# 双击
curl -s -X POST $WDA/session/$($SCRIPTS/wda_session.sh)/wda/doubleTap \
  -H "Content-Type: application/json" \
  -d '{"x": 200, "y": 300}'

# 双指点击
curl -s -X POST $WDA/session/$($SCRIPTS/wda_session.sh)/wda/twoFingerTap \
  -H "Content-Type: application/json" \
  -d '{"element": "$ELEMENT_ID"}'

# 自定义点击次数
curl -s -X POST $WDA/session/$($SCRIPTS/wda_session.sh)/wda/tapWithNumberOfTaps \
  -H "Content-Type: application/json" \
  -d '{"numberOfTaps": 3, "numberOfTouches": 1, "x": 200, "y": 300}'

# 元素偏移点击（偏移基准：元素左上角）
curl -s -X POST $WDA/session/$($SCRIPTS/wda_session.sh)/wda/element/$ELEMENT_ID/tap \
  -H "Content-Type: application/json" \
  -d '{"x": 50, "y": 20}'
```

### 查找元素并点击（完整流程）

```bash
# 1. 通过 accessibility id 查找元素
ELEMENT_ID=$(curl -s $WDA/session/$SESSION/elements -H "Content-Type: application/json" \
  -d '{"using": "accessibility id", "value": "tap-demo.button"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['value'][0]['element-6066-11e4-a52e-4f735466cecf'])")
# 也可用 'ELEMENT' 字段
ELEMENT_ID=$(curl -s $WDA/session/$SESSION/elements -H "Content-Type: application/json" \
  -d '{"using": "accessibility id", "value": "tap-demo.button"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['value'][0]['ELEMENT'])")

# 2. W3C standard click（推荐，可靠触发点击事件）
curl -s -X POST $WDA/session/$SESSION/element/$ELEMENT_ID/click \
  -H "Content-Type: application/json" -d '{}'

# 备选：坐标点击（对无 accessibility id 的元素）
# 从 YAML snapshot 取相邻锚点 rect → 推导目标区中心/中线 → /wda/tap 或 W3C Actions
curl -s -X POST $WDA/session/$SESSION/wda/tap \
  -H "Content-Type: application/json" -d '{"x": 92, "y": 458}'

# 注意：/wda/element/:eid/tap 在真机上不一定触发点击事件，避免使用
```

### 点击失败时的回退顺序

1. 先查阻塞层：优先 `$SCRIPTS/wda_guard.sh --check`
2. 有元素时优先 `/element/:id/click`
3. 无元素但有稳定锚点时，用 YAML `rect` 动态推导坐标
4. 坐标点击先试 `/wda/tap`；仍失败再试 W3C Actions
5. 每次点击后立刻 snapshot，确认目标状态确实变化；HTTP 200 不等于命中成功

### 动态坐标策略

1. 先找目标区附近稳定锚点：标题、状态文案、分区标签
2. 用锚点 `rect` 算中心点，或取两个锚点之间的中点
3. 避免把一次调试得到的常量坐标长期写进脚本
4. 如果页面会滚动，先确认锚点当前仍在可见区，再执行坐标动作

### 文本输入（完整流程）

```bash
# 1. 获取文本框元素 ID
EL_ID=$(curl -s $WDA/session/$SESSION/elements -H "Content-Type: application/json" \
  -d '{"using": "accessibility id", "value": "text-demo.field"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['value'][0]['element-6066-11e4-a52e-4f735466cecf'])")

# 2. 输入文本（逐字符数组，会触发键盘）
# ⚠️ clear() 在真机上不生效！setValue 永远追加文本，不会替换
# 如需替换文本，需要先手动删除（点字段 → 全选 → 删 → 再输入）
curl -s -X POST $WDA/session/$SESSION/element/$EL_ID/value \
  -H "Content-Type: application/json" \
  -d '{"value": ["W","D","A","T","e","s","t","2","0","2","6"]}'

# 3. 等键盘弹出，点击空白处关闭
sleep 2
curl -s -X POST $WDA/session/$SESSION/wda/tap \
  -H "Content-Type: application/json" -d '{"x": 200, "y": 30}'
sleep 1
# 验证输入结果
$SCRIPTS/ios_wda_snapshot.sh
```

### 长按与拖拽

```bash
# 长按（duration 单位：秒）
curl -s -X POST $WDA/session/$($SCRIPTS/wda_session.sh)/wda/touchAndHold \
  -H "Content-Type: application/json" \
  -d '{"x": 200, "y": 300, "duration": 2}'

# 拖拽
curl -s -X POST $WDA/session/$($SCRIPTS/wda_session.sh)/wda/dragfromtoforduration \
  -H "Content-Type: application/json" \
  -d '{"fromX": 100, "fromY": 200, "toX": 300, "toY": 400, "duration": 1}'
```

### 高级手势

```bash
# 滑动（direction: up/down/left/right）
curl -s -X POST $WDA/session/$($SCRIPTS/wda_session.sh)/wda/swipe \
  -H "Content-Type: application/json" \
  -d '{"direction": "up", "velocity": 1200}'

# 捏合（scale > 1 放大，< 1 缩小）
curl -s -X POST $WDA/session/$($SCRIPTS/wda_session.sh)/wda/pinch \
  -H "Content-Type: application/json" \
  -d '{"scale": 0.5, "velocity": 100}'

# 旋转（rotation 弧度）
curl -s -X POST $WDA/session/$($SCRIPTS/wda_session.sh)/wda/rotate \
  -H "Content-Type: application/json" \
  -d '{"rotation": 3.14, "velocity": 100}'

# 压感触控（pressure 0~1, duration 单位：秒）
curl -s -X POST $WDA/session/$($SCRIPTS/wda_session.sh)/wda/forceTouch \
  -H "Content-Type: application/json" \
  -d '{"x": 200, "y": 300, "pressure": 0.8, "duration": 0.5}'
```

### 滚动

> ⚠️ 真机实战验证：全局 `/wda/swipe` 不作用于 ScrollView！必须对滚动容器元素执行 swipe。

```bash
# 1. 先找到滚动容器元素（如 ScrollView 的 accessibility id）
SCROLL_EL=$(curl -s $WDA/session/$SESSION/elements \
  -H "Content-Type: application/json" \
  -d '{"using": "accessibility id", "value": "demo.scrollView"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['value'][0]['ELEMENT'])")

# 2. 对元素执行 swipe — UP = 内容向下（显示更深元素），DOWN = 内容向上
curl -s -X POST $WDA/session/$SESSION/wda/element/$SCROLL_EL/swipe \
  -H "Content-Type: application/json" \
  -d '{"direction": "up", "velocity": 1200}'

# 单次 swipe 滚动距离有限，多次调用覆盖完整区域
# 每次 swipe 后 snapshot 验证是否到达目标
for i in $(seq 1 5); do
  curl -s -X POST $WDA/session/$SESSION/wda/element/$SCROLL_EL/swipe \
    -H "Content-Type: application/json" \
    -d '{"direction": "up", "velocity": 1200}' > /dev/null
  sleep 2
  $SCRIPTS/ios_wda_snapshot.sh
done
```

> **方向含义**：WDA swipe direction 是手势方向。`up` = 手指向上滑 = 内容向下滚（看到更深内容）。`down` = 手指向下滑 = 内容向上滚。勿与视觉方向混淆。

> **XCTest 可见性**：XCTest 只渲染 visible 区域，screen 外的元素不会被暴露。滚动需让目标进入可见范围后才能通过元素查找定位。

## W3C Actions

> 通过 `/session/:sid/actions` 执行动作链，`DELETE /session/:sid/actions` 释放所有动作源。

```bash
# W3C 点击（viewport 绝对坐标）
curl -s -X POST $WDA/session/$($SCRIPTS/wda_session.sh)/actions \
  -H "Content-Type: application/json" -d '{
  "actions": [{
    "type": "pointer", "id": "f1",
    "parameters": {"pointerType": "touch"},
    "actions": [
      {"type": "pointerMove", "duration": 0, "origin": "viewport", "x": 200, "y": 300},
      {"type": "pointerDown", "button": 0},
      {"type": "pause", "duration": 100},
      {"type": "pointerUp", "button": 0}
    ]
  }]
}'

# W3C 点击元素（元素中心 + x/y 偏移）
curl -s -X POST $WDA/session/$($SCRIPTS/wda_session.sh)/actions \
  -H "Content-Type: application/json" -d '{
  "actions": [{
    "type": "pointer", "id": "f1",
    "parameters": {"pointerType": "touch"},
    "actions": [
      {"type": "pointerMove", "duration": 0, "origin": {"element-6066-11e4-a52e-4f735466cecf": "$ELEMENT_ID"}, "x": 0, "y": 0},
      {"type": "pointerDown", "button": 0},
      {"type": "pause", "duration": 100},
      {"type": "pointerUp", "button": 0}
    ]
  }]
}'

# 释放所有动作源
curl -s -X DELETE $WDA/session/$($SCRIPTS/wda_session.sh)/actions
```

## 锁屏

```bash
# 查询锁定状态（全局，无需 session）
curl -s $WDA/wda/locked | jq .value

# 锁屏（必须带 Content-Type: application/json + 空 body，否则 400）
curl -s -X POST -H "Content-Type: application/json" -d '{}' $WDA/wda/lock | curl -s $WDA/wda/locked | jq .value

# 解锁
curl -s -X POST -H "Content-Type: application/json" -d '{}' $WDA/wda/unlock | sleep 3 | curl -s $WDA/wda/locked | jq .value
```

## 模拟位置

```bash
# 读取当前模拟位置
curl -s $WDA/wda/simulatedLocation | jq .
# → { "value": { "altitude": null, "longitude": null, "latitude": null }, "sessionId": "..." }

# 设置经纬度（北京坐标）
curl -s -X POST $WDA/wda/simulatedLocation \
  -H "Content-Type: application/json" \
  -d '{"latitude": 39.9042, "longitude": 116.4074}' | jq .
# → { "value": null, "sessionId": "..." }

# 验证设置生效
curl -s $WDA/wda/simulatedLocation | jq .
# → { "value": { "altitude": 0, "longitude": 116.4074, "latitude": 39.9042 }, ... }

# 清除模拟位置
curl -s -X DELETE $WDA/wda/simulatedLocation | jq .
# → { "value": null, "sessionId": "..." }
```

## 屏幕与设备信息

```bash
#返回屏幕尺寸、状态栏尺寸、缩放比例。
curl -s $WDA/wda/screen

# 返回 locale、时区、型号、UUID、UI 风格等设备元数据。
curl -s $WDA/wda/device/info | jq .value

# 返回前台应用信息。
curl -s $WDA/wda/activeAppInfo | jq .value

# 返回设备地理位置。需在 **Settings → Privacy → Location Services → WebDriverAgent-Runner → Always** 授权，否则经纬度始终为 0。
curl -s $WDA/wda/device/location | jq .value
```

## 方向

```bash
# 读取方向
curl -s $WDA/session/$($SCRIPTS/wda_session.sh)/orientation | jq .
# → { "value": "PORTRAIT" }

# 设置方向
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"orientation": "LANDSCAPE"}' \
  $WDA/session/$($SCRIPTS/wda_session.sh)/orientation | jq .

# 读取三轴旋转
curl -s $WDA/session/$($SCRIPTS/wda_session.sh)/rotation | jq .

# 设置三轴旋转
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"x": 0, "y": 0, "z": 90}' \
  $WDA/session/$($SCRIPTS/wda_session.sh)/rotation | jq .
```
