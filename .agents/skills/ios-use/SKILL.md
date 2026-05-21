---
name: ios-use
description: "操作 iOS / iPhone 真机与模拟器。用于 WebDriverAgent 场景下的设备发现、WDA 启动、Session 创建、页面读取、元素交互、手势、系统控制、故障恢复。适用于 xcodebuild、simctl、curl 或 WDA REST API。"
argument-hint: "描述任务，例如：启动 WDA 并创建 session；读取 source 后点击按钮"
user-invocable: true
---

# iOS iPhone 使用能力

## 快速开始

**必须执行**:
- $SCRIPTS=./agents/skills/ios-use/scripts
- $WDA=http://127.0.0.1:8100
- $SCRIPTS/ios_wda_test_on_iphone.sh - 启动 WDA（检查/安装/启动，约 1~30s+）

### 执行流程 - 重复 ReAct 循环: 截屏 → 观察 → 决策 → 执行 → 截屏验证

1. $SCRIPTS/ios_wda_snapshot.sh - 获取页面源码 + 截图（输出到 {PROJECT_ROOT}/tmp/wda-snapshot-{UDID}/{yymmdd}/*.jpg & *.yaml，自动递增序号）然后决策分析
2. 执行决策 → 验证，例：点击坐标 (100, 200) 后重新截屏 - curl -s -X POST $WDA/session/$($SCRIPTS/wda_session.sh)/wda/tap -H "Content-Type: application/json" -d '{"x": 100, "y": 200}' | sleep 2 | $SCRIPTS/ios_wda_snapshot.sh

**核心原则：每次操作前必须截屏观察当前状态，禁止预测式连续操作。**

## 多次操作失败请使用代码库研究 

[codebase-research.md](references/codebase-research.md) 

# 应用与设备控制

```bash
# 获取已安装应用
xcrun devicectl device info apps --device <UDID>

# 启动应用 — launch API 在真机上不可靠，推荐坐标点击方式
# 1. 先截屏找图标
$SCRIPTS/ios_wda_snapshot.sh
# 2. 从 YAML 找图标 rect，计算中心坐标
# 3. 坐标点击图标
curl -s -X POST $WDA/session/$($SCRIPTS/wda_session.sh)/wda/tap \
  -H "Content-Type: application/json" \
  -d '{"x": 62, "y": 635}'
sleep 5  # 启动需等 5s（比常规 3s 更安全）
$SCRIPTS/ios_wda_snapshot.sh  # 验证是否成功打开

# launch API（备用，真机上可能不生效）
curl -s -X POST  $WDA/session/$($SCRIPTS/wda_session.sh)/wda/apps/launch  -d '{"bundleId": "com.apple.Preferences"}'

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
# 从 YAML snapshot 取元素 rect → 计算中心坐标 → /wda/tap
curl -s -X POST $WDA/session/$SESSION/wda/tap \
  -H "Content-Type: application/json" -d '{"x": 92, "y": 458}'

# 注意：/wda/element/:eid/tap 在真机上不一定触发点击事件，避免使用
```

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
