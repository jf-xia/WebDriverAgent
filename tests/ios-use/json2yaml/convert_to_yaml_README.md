# iOS Source JSON to YAML 转换工具

## 概述

将 iOS WebDriverAgent 的 source JSON 转换为精简的 YAML 格式。

## 文件说明

- `convert_to_yaml.py` - 基础转换脚本
- `convert_to_yaml_v2.py` - 优化转换脚本（推荐使用）

## 使用方法

```bash
# 基础转换
python3 convert_to_yaml.py source.json output.yaml

# 优化转换（推荐）
python3 convert_to_yaml_v2.py source.json output.yaml

# 删除装饰性 Image 节点
python3 convert_to_yaml_v2.py source.json output.yaml --remove-decoration
```

## 优化策略

### 1. Rect 精简
- 删除 `x=0, y=0, width=0, height=0` 的全零 rect
- `x=0, y=0` 的 rect 只保留宽高：`402x874`
- 完整 rect 转为紧凑格式：`120,88 69x91`

### 2. Type-Name 合并
```yaml
# 原始格式
- type: Icon
  name: Calendar

# 优化格式
- Icon: Calendar
```

### 3. 空值删除
- 删除 `null` 值字段
- 删除空的 `children` 数组

### 4. 装饰节点删除（可选）
删除只有 `type` 和 `rect` 的 Image 节点（通常是图标标签图片）。

## 输出对比

| 版本 | 文件 | 大小 | 行数 | 节点数 |
|------|------|------|------|--------|
| 原始 | source.json | 267KB | 5585 | 344 |
| 基础 | source.yaml | 40KB | 1579 | 255 |
| 优化 | source_optimized.yaml | 13KB | 478 | 164 |
| 紧凑 | source_compact.yaml | 12KB | 422 | 164 |
| 最小 | source_minimal.yaml | 8.8KB | 321 | 124 |

## YAML 结构示例

```yaml
Application: ' '
rect: 402x874
children:
- type: Window
  rect: 402x874
  children:
  - name: Home screen icons
    rect: 402x874
    children:
    - type: Icon
      children:
      - Icon: Weather
      - Icon: Calendar
        value: Saturday, May 16
      - Icon: Mail
        value: No unread emails
      - Icon: Clock
        value: 10:43 PM
      - Icon: Settings
```

## 前三层结构分析

### Layer 0: Application
- 根节点，包含整个应用视图
- 通常只有 1 个节点

### Layer 1: Window
- 窗口层，包含 14 个窗口
- 大部分窗口只有基础 rect 信息
- 主要窗口包含 Home screen icons

### Layer 2-3: 内容层
- Home screen icons - 主屏幕图标
- StatusBar - 状态栏（时间、电量、信号等）
- 其他系统 UI 元素

## 节点类型统计

| 类型 | 数量 | 说明 |
|------|------|------|
| Other | 231 | 通用容器节点 |
| Icon | 52 | 应用图标 |
| Image | 42 | 图片元素 |
| Window | 14 | 窗口 |
| StaticText | 2 | 静态文本 |
| Application | 1 | 应用根节点 |
| PageIndicator | 1 | 页面指示器 |
| StatusBar | 1 | 状态栏 |

## 进一步优化建议

1. **删除空 Window 节点** - 只有 rect 的 Window 可能不需要
2. **合并相似 Icon 节点** - 相同位置的重复图标
3. **提取 StatusBar** - 状态栏信息可以单独提取
4. **扁平化嵌套** - 减少不必要的层级嵌套
