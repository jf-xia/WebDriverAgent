---
name: ios-use
description: "操作 iOS / iPhone 真机与模拟器。用于 WebDriverAgent 场景下的设备发现、WDA 启动、Session 创建、页面读取、元素交互、手势、系统控制、故障恢复。适用于 xcodebuild、simctl、curl 或 WDA REST API。"
argument-hint: "描述任务，例如：启动 WDA 并创建 session；读取 source 后点击按钮"
user-invocable: true
---

# iOS iPhone 使用能力

## 快速开始

脚本位于技能的 [scripts/](scripts/) 子目录, 请确认 $SCRIPTS 环境变量指向该目录。

### 执行流程 - 重复 ReAct 循环: 截屏 → 观察 → 决策 → 执行 → 截屏验证

1. $SCRIPTS/ios_wda_test_on_iphone.sh - 启动 WDA（检查/安装/启动，约 1~30s+，日志输出到 {PROJECT_ROOT}/tmp/wda.log）
2. $SCRIPTS/ios_wda_snapshot.sh - 获取页面源码 + 截图（输出到 {PROJECT_ROOT}/tmp/wda-snapshot-{UDID}/{yymmdd}/*.jpg & *.yaml，自动递增序号）
3. 决策 → 执行 → 验证，例：点击坐标 (100, 200) 后重新截屏 - curl -s -X POST http://127.0.0.1:8100/session/$($SCRIPTS/wda_session.sh)/wda/tap -H "Content-Type: application/json" -d '{"x": 100, "y": 200}' | sleep 2 | $SCRIPTS/ios_wda_snapshot.sh

**核心原则：每次操作前必须截屏观察当前状态，禁止预测式连续操作。**

## 多次操作失败请使用代码库研究 

[codebase-research.md](references/codebase-research.md) 

# 应用与设备控制

```bash
# 获取已安装应用
xcrun devicectl device info apps --device <UDID>

# 启动应用
curl -s -X POST  http://127.0.0.1:8100/session/$SESSION/wda/apps/launch  -d '{"bundleId": "com.apple.Preferences"}'

# 系统按键 "home", "volumeUp", "volumeDown", "action", "camera"
curl -s -X POST   http://127.0.0.1:8100/session/$SESSION/wda/pressButton  -H "Content-Type: application/json" -d '{"name": "volumeUp"}' 
```

## 锁屏

```bash
# 查询锁定状态（全局，无需 session）
curl -s http://127.0.0.1:8100/wda/locked | jq .value

# 锁屏（必须带 Content-Type: application/json + 空 body，否则 400）
curl -s -X POST -H "Content-Type: application/json" -d '{}' http://127.0.0.1:8100/wda/lock | curl -s http://127.0.0.1:8100/wda/locked | jq .value

# 解锁
curl -s -X POST -H "Content-Type: application/json" -d '{}' http://127.0.0.1:8100/wda/unlock | sleep 3 | curl -s http://127.0.0.1:8100/wda/locked | jq .value
```

## 模拟位置

```bash
# 读取当前模拟位置
curl -s http://127.0.0.1:8100/wda/simulatedLocation | jq .
# → { "value": { "altitude": null, "longitude": null, "latitude": null }, "sessionId": "..." }

# 设置经纬度（北京坐标）
curl -s -X POST http://127.0.0.1:8100/wda/simulatedLocation \
  -H "Content-Type: application/json" \
  -d '{"latitude": 39.9042, "longitude": 116.4074}' | jq .
# → { "value": null, "sessionId": "..." }

# 验证设置生效
curl -s http://127.0.0.1:8100/wda/simulatedLocation | jq .
# → { "value": { "altitude": 0, "longitude": 116.4074, "latitude": 39.9042 }, ... }

# 清除模拟位置
curl -s -X DELETE http://127.0.0.1:8100/wda/simulatedLocation | jq .
# → { "value": null, "sessionId": "..." }
```

## 屏幕与设备信息

```bash
#返回屏幕尺寸、状态栏尺寸、缩放比例。
curl -s http://127.0.0.1:8100/wda/screen

# 返回 locale、时区、型号、UUID、UI 风格等设备元数据。
curl -s http://127.0.0.1:8100/wda/device/info | jq .value

# 返回前台应用信息。
curl -s http://127.0.0.1:8100/wda/activeAppInfo | jq .value

# 返回设备地理位置。需在 **Settings → Privacy → Location Services → WebDriverAgent-Runner → Always** 授权，否则经纬度始终为 0。
curl -s http://127.0.0.1:8100/wda/device/location | jq .value
```

## 方向

```bash
# 读取方向
curl -s http://127.0.0.1:8100/session/$SESSION/orientation | jq .
# → { "value": "PORTRAIT" }

# 设置方向
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"orientation": "LANDSCAPE"}' \
  http://127.0.0.1:8100/session/$SESSION/orientation | jq .

# 读取三轴旋转
curl -s http://127.0.0.1:8100/session/$SESSION/rotation | jq .

# 设置三轴旋转
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"x": 0, "y": 0, "z": 90}' \
  http://127.0.0.1:8100/session/$SESSION/rotation | jq .
```

## 手势

### 点击

```bash
# 坐标点击（无元素时为屏幕绝对坐标）
curl -s -X POST http://127.0.0.1:8100/session/$SESSION/wda/tap \
  -H "Content-Type: application/json" \
  -d '{"x": 200, "y": 300}'

# 双击
curl -s -X POST http://127.0.0.1:8100/session/$SESSION/wda/doubleTap \
  -H "Content-Type: application/json" \
  -d '{"x": 200, "y": 300}'

# 双指点击
curl -s -X POST http://127.0.0.1:8100/session/$SESSION/wda/twoFingerTap \
  -H "Content-Type: application/json" \
  -d '{"element": "$ELEMENT_ID"}'

# 自定义点击次数
curl -s -X POST http://127.0.0.1:8100/session/$SESSION/wda/tapWithNumberOfTaps \
  -H "Content-Type: application/json" \
  -d '{"numberOfTaps": 3, "numberOfTouches": 1, "x": 200, "y": 300}'

# 元素偏移点击（偏移基准：元素左上角）
curl -s -X POST http://127.0.0.1:8100/session/$SESSION/wda/element/$ELEMENT_ID/tap \
  -H "Content-Type: application/json" \
  -d '{"x": 50, "y": 20}'
```

### 长按与拖拽

```bash
# 长按（duration 单位：秒）
curl -s -X POST http://127.0.0.1:8100/session/$SESSION/wda/touchAndHold \
  -H "Content-Type: application/json" \
  -d '{"x": 200, "y": 300, "duration": 2}'

# 拖拽
curl -s -X POST http://127.0.0.1:8100/session/$SESSION/wda/dragfromtoforduration \
  -H "Content-Type: application/json" \
  -d '{"fromX": 100, "fromY": 200, "toX": 300, "toY": 400, "duration": 1}'
```

### 高级手势

```bash
# 滑动（direction: up/down/left/right）
curl -s -X POST http://127.0.0.1:8100/session/$SESSION/wda/swipe \
  -H "Content-Type: application/json" \
  -d '{"direction": "up", "velocity": 1200}'

# 捏合（scale > 1 放大，< 1 缩小）
curl -s -X POST http://127.0.0.1:8100/session/$SESSION/wda/pinch \
  -H "Content-Type: application/json" \
  -d '{"scale": 0.5, "velocity": 100}'

# 旋转（rotation 弧度）
curl -s -X POST http://127.0.0.1:8100/session/$SESSION/wda/rotate \
  -H "Content-Type: application/json" \
  -d '{"rotation": 3.14, "velocity": 100}'

# 压感触控（pressure 0~1, duration 单位：秒）
curl -s -X POST http://127.0.0.1:8100/session/$SESSION/wda/forceTouch \
  -H "Content-Type: application/json" \
  -d '{"x": 200, "y": 300, "pressure": 0.8, "duration": 0.5}'
```

### 滚动

```bash
# 按方向滚动（direction: up/down/left/right，distance: 滚动距离）
curl -s -X POST http://127.0.0.1:8100/session/$SESSION/wda/scroll \
  -H "Content-Type: application/json" \
  -d '{"direction": "down", "distance": 50}'

# 滚动到匹配的元素（name 或 predicateString）
curl -s -X POST http://127.0.0.1:8100/session/$SESSION/wda/scroll \
  -H "Content-Type: application/json" \
  -d '{"name": "Item 5"}'

# 使用 predicateString 滚动到目标
curl -s -X POST http://127.0.0.1:8100/session/$SESSION/wda/scroll \
  -H "Content-Type: application/json" \
  -d '{"predicateString": "label BEGINSWITH \"Item\""}'
```

## W3C Actions

> 通过 `/session/:sid/actions` 执行动作链，`DELETE /session/:sid/actions` 释放所有动作源。

```bash
# W3C 点击（viewport 绝对坐标）
curl -s -X POST http://127.0.0.1:8100/session/$SESSION/actions \
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
curl -s -X POST http://127.0.0.1:8100/session/$SESSION/actions \
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
curl -s -X DELETE http://127.0.0.1:8100/session/$SESSION/actions
```
