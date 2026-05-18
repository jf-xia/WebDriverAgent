---
name: ios-use
description: "操作 iOS / iPhone 真机与模拟器。用于 WebDriverAgent 场景下的设备发现、WDA 启动、Session 创建、页面读取、元素交互、手势、系统控制、故障恢复。适用于 xcodebuild、simctl、curl 或 WDA REST API。"
argument-hint: "描述任务，例如：启动 WDA 并创建 session；读取 source 后点击按钮"
user-invocable: true
---

# iOS iPhone 使用能力

## 快速开始

**核心原则：每次操作前必须截屏观察当前状态，禁止预测式连续操作。**

```bash
# 开始前必须检查 WDA, 如未运行则安装启动 (30s+), log 输出到{PROJECT_ROOT}/tmp/wda.log
sh ios_wda_test_on_iphone.sh

# 获取页面源码 + 截图, 输出到{PROJECT_ROOT}/tmp/wda-snapshot-{UDID}/{yymmdd}/*.jpg & *.yaml（自动递增序号）
sh ios_wda_snapshot.sh

# 决策下一步 → 执行操作 → 再次截屏验证, 例如：点击坐标 (100, 200), 完成后再次观察
curl -X POST http://127.0.0.1:8100/session/$(./scripts/wda_session.sh)/wda/tap -H "Content-Type: application/json" -d '{"x": 100, "y": 200}' && sh ios_wda_snapshot.sh

# 下一个 ReAct 循环: 截屏 → 观察屏幕内容 → 决策下一步 → 执行操作 → 再次截屏验证
```

## WDA API 核心速查

| 类别 | 关键接口 |
|------|----------|
| 状态 | `GET /status` |
| 元素 | `GET/POST /element/:uuid/{click,value,clear,text,rect,enabled,displayed}` |
| 手势 | `POST /wda/{tap,doubleTap,touchAndHold,swipe,pinch,rotate,dragfromtoforduration,scroll}` |
| 弹窗 | `GET /alert/text`、`POST /alert/{accept,dismiss}`、`GET /wda/alert/buttons` |

# 应用与设备控制

```bash
# 获取已安装应用
xcrun devicectl device info apps --device <UDID>

# 启动应用
curl -s -X POST  http://127.0.0.1:8100/session/$(./scripts/wda_session.sh)/wda/apps/launch  -d '{"bundleId": "com.apple.Preferences"}'

# 系统按键 "home", "volumeUp", "volumeDown", "action", "camera"
curl -s -X POST   http://127.0.0.1:8100/session/$(./scripts/wda_session.sh)/wda/pressButton  -H "Content-Type: application/json" -d '{"name": "volumeUp"}' 
```

## 元素属性与操作

```bash
# 前置：先 find 到元素，获取 UUID
UUID=$(curl -s -X POST http://127.0.0.1:8100/session/$(./scripts/wda_session.sh)/element -H "Content-Type: application/json" -d '{"using": "accessibility id", "value": "BackButton"}' | jq -r '.value["ELEMENT"]')

# PickerWheel
curl -X POST http://localhost:8100/session/$SESSION_ID/wda/pickerwheel/$ELEMENT_ID/select -H "Content-Type: application/json" -d '{"order": "next", "value": "11 o'clock", "maxAttempts": 8}'

# GET 文本内容
# StaticText 返回实际文本；Switch/Button 返回空字符串
curl -s http://127.0.0.1:8100/session/$(./scripts/wda_session.sh)/element/$UUID/text | jq .value

# GET 位置与尺寸：返回 {x, y, width, height}
curl -s http://127.0.0.1:8100/session/$(./scripts/wda_session.sh)/element/$UUID/rect | jq .value

# GET 可用状态：enabled 为 true/false
curl -s http://127.0.0.1:8100/session/$(./scripts/wda_session.sh)/element/$UUID/enabled | jq .value

# GET 可见状态：visible 为 true/false
curl -s http://127.0.0.1:8100/session/$(./scripts/wda_session.sh)/element/$UUID/displayed | jq .value

# GET 选中状态：Switch/CheckBox 等可选中元素返回 true/false
curl -s http://127.0.0.1:8100/session/$(./scripts/wda_session.sh)/element/$UUID/selected | jq .value

# GET 任意属性：26 个合法属性名
# UID, accessible, enabled, focused, frame, hittable, index,
# label, maxValue, minValue, name, nativeFrame, placeholderValue,
# rect, selected, traits, type, value, visible
# 及对应 wd* 前缀版本（wdUID, wdAccessible...）
curl -s http://127.0.0.1:8100/session/$(./scripts/wda_session.sh)/element/$UUID/attribute/name | jq .value

# POST 点击操作
curl -s -X POST http://127.0.0.1:8100/session/$(./scripts/wda_session.sh)/element/$UUID/click \
  -H "Content-Type: application/json" | jq .

# POST 清空文本（仅适用于 TextField/TextView 等输入框）
curl -s -X POST http://127.0.0.1:8100/session/$(./scripts/wda_session.sh)/element/$UUID/clear \
  -H "Content-Type: application/json" | jq .

# POST 输入文本（仅适用于 TextField/TextView，Safari 地址栏会弹键盘导致元素 stale）
curl -s -X POST http://127.0.0.1:8100/session/$(./scripts/wda_session.sh)/element/$UUID/value \
  -H "Content-Type: application/json" \
  -d '{"value": ["test"]}' | jq .

# 注意：操作后元素可能失效（如 Safari 弹出键盘），需重新 find
curl -s -X POST http://127.0.0.1:8100/session/$(./scripts/wda_session.sh)/element \
  -H "Content-Type: application/json" \
  -d '{"using": "accessibility id", "value": "BackButton"}' \
  | jq -r '.value["element-6066-11e4-a52e-4f735466cecf"]'
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

## 详细文档

| 主题 | 路径 |
|------|------|
| 命令参考 | [command-reference.md](references/command-reference.md) |
| 应用与设备控制 | [app-and-device-control.md](references/app-and-device-control.md) |
| 多次操作失败请使用代码库研究 | [codebase-research.md](references/codebase-research.md) |

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
curl -s http://127.0.0.1:8100/session/$(./scripts/wda_session.sh)/orientation | jq .
# → { "value": "PORTRAIT" }

# 设置方向
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"orientation": "LANDSCAPE"}' \
  http://127.0.0.1:8100/session/$(./scripts/wda_session.sh)/orientation | jq .

# 读取三轴旋转
curl -s http://127.0.0.1:8100/session/$(./scripts/wda_session.sh)/rotation | jq .

# 设置三轴旋转
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"x": 0, "y": 0, "z": 90}' \
  http://127.0.0.1:8100/session/$(./scripts/wda_session.sh)/rotation | jq .
```
