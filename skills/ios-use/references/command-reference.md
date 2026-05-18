# WDA 命令参考

## 简单手势

| 方法 | 路径 | 关键参数 | 说明 |
|------|------|----------|------|
| `POST` | `/wda/tap` | `x`, `y` | 点击坐标（无元素时为屏幕绝对坐标） |
| `POST` | `/wda/element/:uuid/tap` | `x`, `y` | 点击元素，x/y 是相对元素**左上角**的偏移 |
| `POST` | `/wda/doubleTap` | `x`, `y` | 双击 |
| `POST` | `/wda/twoFingerTap` | 元素或坐标 | 双指点击 |
| `POST` | `/wda/tapWithNumberOfTaps` | `numberOfTaps`, `numberOfTouches` | 自定义点击次数 |
| `POST` | `/wda/touchAndHold` | `duration`, `x`, `y` | 长按 |
| `POST` | `/wda/swipe` | `direction`, `velocity` | 滑动 |
| `POST` | `/wda/pinch` | `scale`, `velocity` | 捏合 |
| `POST` | `/wda/rotate` | `rotation`, `velocity` | 旋转 |
| `POST` | `/wda/dragfromtoforduration` | `fromX`, `fromY`, `toX`, `toY`, `duration` | 拖拽 |
| `POST` | `/wda/forceTouch` | `pressure`, `duration`, `x`, `y` | 压感触控 |
| `POST` | `/wda/scroll` | `direction`/`distance`/`name`/`predicateString` | 滚动 |

```bash
# 滑动
curl -X POST http://localhost:8100/session/$SESSION_ID/wda/swipe \
  -H "Content-Type: application/json" -d '{"direction": "up", "velocity": 1200}'

# 滚动到目标
curl -X POST http://localhost:8100/session/$SESSION_ID/wda/scroll \
  -H "Content-Type: application/json" -d '{"predicateString": "label BEGINSWITH \"Item\""}'

# 元素偏移点击（偏移基准是元素左上角）
curl -X POST http://localhost:8100/session/$SESSION_ID/wda/element/$ELEMENT_ID/tap \
  -H "Content-Type: application/json" -d '{"x": 50, "y": 20}'
```

## W3C Actions

| 方法 | 路径 | 用途 |
|------|------|------|
| `POST` | `/session/:sid/actions` | 执行 W3C 动作链 |
| `DELETE` | `/session/:sid/actions` | 释放所有动作源 |

```bash
# W3C 点击（viewport 绝对坐标）
curl -X POST http://localhost:8100/session/$SESSION_ID/actions \
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

# W3C 点击元素（元素中心 + 偏移）
curl -X POST http://localhost:8100/session/$SESSION_ID/actions \
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
```
