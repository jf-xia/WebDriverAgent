---
name: ios-use
description: "操作 iOS / iPhone 真机与模拟器。用于 WebDriverAgent 场景下的设备发现、WDA 启动、Session 创建、页面读取、元素交互、手势、系统控制、故障恢复。适用于 xcodebuild、simctl、curl 或 WDA REST API。"
argument-hint: "描述任务，例如：启动 WDA 并创建 session；读取 source 后点击按钮"
user-invocable: true
---

# iOS 使用能力

## 快速开始
```bash
# 安装启动 WDA, log 输出到{PROJECT_ROOT}/tmp/wda.log
bash ios_wda_test_on_iphone.sh

# 获取页面源码 + 截图, 输出到{PROJECT_ROOT}/tmp/wda-snapshot-{UDID}/{yymmdd}/*.jpg & *.yaml（自动递增序号）
bash ios_wda_snapshot.sh

# 执行操作，例如点击坐标 (x,y)

```

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

## 脚本参数速查

| 脚本 | 关键参数 |
|------|----------|
| `ios_wda_test_on_iphone.sh` | `--udid` `--host` `--port` `--project-path` `--scheme` |
| `ios_wda_snapshot.sh` | `--host` `--port` |

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
