# WDA 命令参考

## 使用原则

- 先确认 `GET /status` 可用，再调需要 session 的接口
- 优先元素级接口，无稳定元素时退回坐标点击
- 简单手势坐标基准是元素左上角；W3C Actions 以中心点为基准，两者不混用

## 坐标系

- **屏幕绝对坐标**：原点 `(0,0)` 左上角，x 右增，y 下增。用于 `/wda/tap`、`/wda/swipe`、`/wda/dragfromtoforduration`
- **元素相对坐标**：偏移基准是元素边界左上角（非中心）。视觉模型输出中心点时需先换算
- **W3C Actions**：`origin: viewport` 时为绝对坐标；`origin: element` 时偏移基准是元素**中心** `(0.5, 0.5)`，与 `/wda/tap` 的左上角基准不同
- **常见误区**：不要把截图绝对坐标当元素偏移；不要把 W3C 中心点语义套到 `/wda/tap`

## Session 与健康检查

| 方法 | 路径 | 用途 |
|------|------|------|
| `POST` | `/session` | 创建会话 |
| `DELETE` | `/session` | 结束会话 |
| `GET` | `/session` | 读取当前活动 session |
| `GET` | `/status` | 服务状态，无需 session |
| `GET` | `/wda/healthcheck` | 轻量健康检查 |

## 元素属性与动作

| 类别 | 方法 | 路径 | 说明 |
|------|------|------|------|
| 属性 | `GET` | `/element/:uuid/text` | 获取文本 |
| 属性 | `GET` | `/element/:uuid/rect` | 位置与尺寸 |
| 属性 | `GET` | `/element/:uuid/enabled` | 可用状态 |
| 属性 | `GET` | `/element/:uuid/displayed` | 可见状态 |
| 属性 | `GET` | `/element/:uuid/selected` | 选中状态 |
| 属性 | `GET` | `/element/:uuid/attribute/:name` | 任意属性 |
| 动作 | `POST` | `/element/:uuid/click` | 点击 |
| 动作 | `POST` | `/element/:uuid/clear` | 清空文本 |
| 动作 | `POST` | `/element/:uuid/value` | 输入文本 |

```bash
# 输入示例
curl -X POST http://localhost:8100/session/$SESSION_ID/element/$ELEMENT_ID/value \
  -H "Content-Type: application/json" -d '{"value": ["hello"], "frequency": 30}'
```

## PickerWheel

```bash
curl -X POST http://localhost:8100/session/$SESSION_ID/wda/pickerwheel/$ELEMENT_ID/select \
  -H "Content-Type: application/json" \
  -d '{"order": "next", "value": "11 o'clock", "maxAttempts": 8}'
```

- 优先用专用路由，不走 `/element/:uuid/value`
- 语义：每次调用先移动一格再判断是否达到目标值
- 已在目标值时继续调用可能拨离目标
- 多轮控件（如时间选择器）一次只改一个 wheel，关闭弹层后重新读取

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

## 入口选择

| 场景 | 接口 |
|------|------|
| 对具体元素输入 | `POST /element/:uuid/value` |
| 清空文本 | `POST /element/:uuid/clear` |
| 已聚焦、只发键盘字符 | `POST /wda/keys` |

## 元素输入

```bash
curl -X POST http://localhost:8100/session/$SESSION_ID/element/$ELEMENT_ID/value \
  -H "Content-Type: application/json" \
  -d '{"value": ["text"], "frequency": 60}'
```

- `value` 接受字符串数组，WDA 拼接成最终内容
- `frequency` 可选，控制字符输入频率
- 元素级输入会先处理焦点管理

## 清空文本

```bash
curl -X POST http://localhost:8100/session/$SESSION_ID/element/$ELEMENT_ID/clear
```

清空失败时不要盲目循环；先判断控件类型。

## 向当前焦点发送按键

```bash
curl -X POST http://localhost:8100/session/$SESSION_ID/wda/keys \
  -H "Content-Type: application/json" \
  -d '{"value": ["hello"], "frequency": 30}'
```

适用：元素已聚焦但定位不稳定、需发送连续文本、需绕开焦点管理。

## PickerWheel

```bash
curl -X POST http://localhost:8100/session/$SESSION_ID/wda/pickerwheel/$ELEMENT_ID/select \
  -H "Content-Type: application/json" \
  -d '{"order": "next", "value": "58 minutes", "maxAttempts": 30}'
```

- `order` 只能 `next` 或 `previous`
- 每次调用先移动一格再检查是否达到目标值
- 已在目标值时继续调用可能拨离目标
- 多轮控件一次只改一个 wheel，关闭弹层后重新读取
- `/element/:uuid/value` 返回成功但 UI 没变 → 优先怀疑控件类型错误

## `/wda/keys` 特殊键名称

| 键类别 | 键名 |
|--------|------|
| 编辑键 | `Delete` `Return` `Enter` `Tab` `Space` `Escape` |
| 方向键 | `UpArrow` `DownArrow` `LeftArrow` `RightArrow` |
| 功能键 | `F1`~`F19` |
