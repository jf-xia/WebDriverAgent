# iOS Click Demo 测试经验总结

## 测试结果

```
Total: 8 | PASS 8 | FAIL 0
```

## 已验证有效的方案

| 操作 | 方法 | 端点 | 状态 |
|------|------|------|------|
| 启动 App | 坐标点击 home screen 图标 | `/wda/tap` | ✅ |
| 按钮点击 | 元素查找 + W3C click | `/session/:sid/element/:eid/click` | ✅ |
| 坐标点击 | 直接坐标 | `/wda/tap` | ✅ |
| 文本输入 | setValue 字符数组 | `/session/:sid/element/:eid/value` | ✅ (追加) |
| 文本清空 | clear() | `/session/:sid/element/:eid/clear` | ❌ 不生效 |
| 滚动 | 元素 swipe UP | `/wda/element/:eid/swipe` `up` | ✅ |
| 全局 swipe | 主窗口 swipe | `/wda/swipe` | ❌ 不滚动目标区域 |
| 元素点击 | WDA tap | `/wda/element/:eid/tap` | ❌ 不稳定 |
| 应用启动 | launch API | `/wda/apps/launch` | ❌ 不可靠 |

## 关键发现（用于更新 SKILL.md）

### 1. 应用启动
- `launch` API 不可靠，可能只激活已运行进程
- **推荐**：先 snapshot 找图标 rect → 计算中心 → `/wda/tap` 坐标点击
- 启动后必须 sleep 5s（比文档中的 3s 更安全）

### 2. 元素点击
- **推荐** 用 W3C standard `/session/:sid/element/:eid/click`（带 `{}` body）
- **避免** `/wda/element/:eid/tap`（不可靠，可能不触发点击事件）

### 3. 文本输入
- `clear()` 完全无效 — WDA 不实现此端点或实现为空
- `setValue()` 永远**追加**文本，不会替换或清空
- 如需清空：选全部→删（删除键坐标点击×N 次）再 setValue
- setValue 后键盘自动弹出，需点空白区域关闭

### 4. 滚动/swipe
- **必须**先查找滚动容器元素（如 `accessibility id: "demo.scrollView"`）
- 对元素执行 `/wda/element/:eid/swipe`
- **方向**：`up` = 内容向下（显示更深元素），`down` = 内容向上
- 全局 `/wda/swipe` 不会作用于 scroll view

### 5. 操作节奏
- 操作后必须 snapshot 验证
- 操作间 sleep 2s
- App 启动后 sleep 5s

### 6. 元素定位
- `accessibility id` 和 `name` 都有效
- 从 response 取 `element-6066-11e4-a52e-4f735466cecf` 或 `ELEMENT`
- XCTest 只暴露 visible 元素

## Bug 修复

### common.sh PROJECT_ROOT 路径
**问题**：`PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"` 少算一级
**修复**：改为 `PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"`
**影响**：所有使用 PROJECT_ROOT 的脚本（snapshot、wda.json 路径等）之前都指向 `.agents/` 而非项目根

## 测试脚本

位置：`.agents/skills/tests/ios-click-demo/test_all.sh`
