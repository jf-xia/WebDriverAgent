---
name: ios-use
description: "操作 iOS / iPhone 真机与模拟器。用于 WebDriverAgent 场景下的设备发现、WDA 启动、Session 创建、页面读取、元素交互、手势、系统控制、故障恢复。适用于 xcodebuild、simctl、curl 或 WDA REST API。"
argument-hint: "描述任务，例如：启动 WDA 并创建 session；读取 source 后点击按钮"
user-invocable: true
---

# iOS 使用能力

## 快速开始
```bash
# 一条命令自动处理设备检查、iproxy USB or WIFI、安装启动 WDA, log 输出到./tmp/wda-<UDID>.log

# 获取页面源码 和 截图
# todo 制作一个脚本，这个脚本专门用于获取页面源码（精简格式）和截图(压缩80%Quality&分辨率768px, 图片格式JPEG / WebP)的，不需要 session。
curl -s http://<HOST>:8100/wda/accessibleSource
curl -s http://<HOST>:8100/screenshot | jq -r '.value' | base64 --decode > 1.{think_action}.png
```

# 测试 iPhone 上的 WDA
# 自动检查 WDA 状态、验证工具、清理旧 tmux session、启动 xcodebuild 测试，输出状态 JSON 到 ./tmp/wda-<UDID>.json，日志到 ./tmp/wda-<UDID>.log
bash ios_wda_test_on_iphone.sh

## 工作流（ReAct 循环）

**核心原则：每次操作前必须截屏观察当前状态，禁止预测式连续操作。**

每个操作步骤都遵循：
```
截屏 → 观察屏幕内容 → 决策下一步 → 执行操作 → 再次截屏验证
```

### ReAct 模板
1. **Observe**：`ios_wda_snapshot.sh` 截屏 + 获取 source
2. **Think**：分析当前屏幕状态，确认目标元素位置和状态
3. **Act**：执行单个操作（点击/输入/滑动等）
4. **Verify**：再次截屏，确认操作生效
5. **Repeat**：回到步骤 1，直到任务完成

## WDA API 端点说明

| 端点 | 是否全局 | 说明 |
|------|----------|------|
| `/wda/homescreen` | ✅ 是 | 回到主屏，但某些设备不支持 |
| `/wda/apps/terminate` | ❌ 需 session | `POST /session/<ID>/wda/apps/terminate` |
| `/wda/apps/activate` | ❌ 需 session | `POST /session/<ID>/wda/apps/activate` |
| `/wda/tap` | ❌ 需 session | `POST /session/<ID>/wda/tap` |
| `/wda/swipe` | ❌ 需 session | `POST /session/<ID>/wda/swipe` |

> 💡 实际使用中，`/wda/apps/terminate` 比 `/wda/homescreen` 更可靠。

## 坐标系要点

| 场景 | 基准点 |
|------|--------|
| `/wda/tap`、`/wda/swipe` 等简单手势 | 屏幕绝对坐标，原点 `(0,0)` 左上角 |
| 元素 + 偏移量 | 偏移基准是**元素左上角**，不是中心 |
| W3C Actions | 通常以元素中心为基准，与 WDA 简单手势不同 |

## 点击策略

`element.click()` 依赖 WDA 计算中点，有时点错位置。使用 `ios_wda_click.sh` 选择策略：

| 策略 | 原理 | 适用场景 |
|------|------|----------|
| `element` | `/element/:uuid/click`，WDA 内部选中点 | 默认，元素小且居中时 |
| `center` | 获取 rect → 计算 `(x+w/2, y+h/2)` → `/wda/tap` 绝对坐标 | 元素大或中点偏移时 |
| `w3c` | W3C Actions pointerDown/pointerUp，最底层模拟 | element/center 都失败时 |
| `offset` | 获取 rect → `/wda/element/:uuid/tap` + 左上角偏移 | 需要精确偏移点击时 |

```bash
# 默认点击
bash ios_wda_click.sh --element-id <ID>
# 中心坐标点击（推荐当 element 点错时）
bash ios_wda_click.sh --element-id <ID> --strategy center
# W3C 模拟点击
bash ios_wda_click.sh --element-id <ID> --strategy w3c
# 偏移点击（基准是元素左上角）
bash ios_wda_click.sh --element-id <ID> --strategy offset --x-offset 30 --y-offset 10
```

> 偏移策略不传 x/y 时自动使用 `(width/2, height/2)` 等效中心点。

## 脚本参数速查

| 脚本 | 关键参数 |
|------|----------|
| `ios_wda_test_on_iphone.sh` | `--udid` `--host` `--port` `--project-path` `--scheme` |

## WDA API 核心速查

| 类别 | 关键接口 |
|------|----------|
| 状态 | `GET /status`、`GET /wda/healthcheck` |
| Session | `POST /session`、`DELETE /session` |
| 页面 | `GET /source`、`GET /wda/accessibleSource`、`GET /screenshot` |
| 元素 | `GET/POST /element/:uuid/{click,value,clear,text,rect,enabled,displayed}` |
| 手势 | `POST /wda/{tap,doubleTap,touchAndHold,swipe,pinch,rotate,dragfromtoforduration,scroll}` |
| 应用 | `POST /wda/apps/{launch,activate,terminate,state}`、`POST /wda/homescreen`（全局端点） |
| 弹窗 | `GET /alert/text`、`POST /alert/{accept,dismiss}`、`GET /wda/alert/buttons` |
| 设备 | `POST /wda/lock`、`/orientation`、`GET /wda/screen`、`/wda/device/info` |

## 详细文档

| 主题 | 路径 |
|------|------|
| 命令参考 | [command-reference.md](references/command-reference.md) |
| 应用与设备控制 | [app-and-device-control.md](references/app-and-device-control.md) |
| 多次操作失败请使用代码库研究 | [codebase-research.md](references/codebase-research.md) |
