# 应用与设备控制

```bash
# 启动应用
curl -s -X POST  http://127.0.0.1:8100/session/F3B0C081-640C-4CB6-A0D7-A6C0BCA55E20/wda/apps/launch  -d '{"bundleId": "com.apple.Preferences"}'
# 系统按键 "home", "volumeUp", "volumeDown", "action", "camera"
curl -s -X POST   http://127.0.0.1:8100/session/F3B0C081-640C-4CB6-A0D7-A6C0BCA55E20/wda/pressButton  -H "Content-Type: application/json" -d '{"name": "volumeUp"}' 
# 获取已安装应用
xcrun devicectl device info apps --device <UDID>
```

## 锁屏与方向

```bash

# 查询锁定状态（全局，无需 session）
curl -s http://127.0.0.1:8100/wda/locked | jq .
# → { "value": false, "sessionId": "..." }

# 锁屏（必须带 Content-Type: application/json + 空 body，否则 400）
curl -s -X POST -H "Content-Type: application/json" -d '{}' http://127.0.0.1:8100/wda/lock | jq .
# → { "value": null, "sessionId": "..." }

# 解锁
curl -s -X POST -H "Content-Type: application/json" -d '{}' http://127.0.0.1:8100/wda/unlock | jq .
# → { "value": null, "sessionId": "..." }

# 读取方向（需 session）
curl -s http://127.0.0.1:8100/session/$SESSION/orientation | jq .
# → { "value": "PORTRAIT" }

# 设置方向（需 session，真机可能不支持横屏）
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"orientation": "LANDSCAPE"}' \
  http://127.0.0.1:8100/session/$SESSION/orientation | jq .
# 真机不支持横屏时: { "value": { "error": "unknown error", "message": "Unable To Rotate Device" } }

# 读取三轴旋转（需 session）
curl -s http://127.0.0.1:8100/session/$SESSION/rotation | jq .
# → { "value": { "x": 0, "y": 0, "z": 0 } }  # 竖屏

# 设置三轴旋转（需 session，真机可能不支持）
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"x": 0, "y": 0, "z": 90}' \
  http://127.0.0.1:8100/session/$SESSION/rotation | jq .
# 真机不支持时: { "value": { "error": "invalid element state", "message": "The current rotation cannot be set to ..." } }
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

| 场景 | 请求 | 结果 | 备注 |
|------|------|------|------|
| 设置有效坐标 | `{"latitude": 39.9042, "longitude": 116.4074}` | ✅ 成功 | GET 返回设置的坐标 |
| 设置无效坐标 | `{"latitude": 999, "longitude": 116.4074}` | ✅ 接受 | WDA 不验证范围 |
| 字符串坐标 | `{"latitude": "39.9", "longitude": "116.4"}` | ✅ 转换 | 自动转为数字 |
| 提供 altitude | `{"latitude": 39.9, "longitude": 116.4, "altitude": 50}` | 无效 | altitude 被忽略，返回 0 |

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
