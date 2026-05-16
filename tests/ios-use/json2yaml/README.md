# iOS Source JSON to YAML 转换工具

## 文件说明

- `source.json` - 原始 iOS WebDriverAgent source 数据
- `source_simple.yaml` - 精简版 YAML（只保留必要字段）
- `../convert_to_simple.py` - 转换脚本

## 使用方法

```bash
cd tests/ios-use/json2yaml
python3 ../convert_to_simple.py source.json source_simple.yaml
```

## 输出字段

每个节点只保留以下字段：
- `type` / `Icon: xxx` / `StaticText: xxx` - 类型和名称合并
- `name` - 名称（当没有 type 时）
- `value` - 值（如文本内容）
- `rect` - 位置和尺寸
- `traits` - 特性标记
- `children` - 子节点

## 优化策略

1. **Type-Name 合并** - `type: Icon` + `name: Calendar` → `Icon: Calendar`
2. **Rect 精简** - `x=0,y=0` 只保留尺寸 `402x874`
3. **删除空节点** - 只有 rect 的节点删除
4. **删除空 Window** - 没有 children 的 Window 节点删除

## 输出对比

| 版本 | 大小 | 行数 | 节点数 | 减少 |
|------|------|------|--------|------|
| 原始 JSON | 267KB | 5585 | 344 | - |
| 简单版 YAML | 10KB | 371 | 153 | 55.5% |

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
```

## 字段说明

| 字段 | 说明 | 示例 |
|------|------|------|
| `Icon: xxx` | 图标类型和名称 | `Icon: Weather` |
| `type: Window` | 节点类型（无名称时） | `type: Window` |
| `name: xxx` | 节点名称（无类型时） | `name: Dock` |
| `value` | 文本值 | `value: 10:43 PM` |
| `rect` | 位置尺寸 | `27,88 70x91` 或 `402x874` |
| `traits` | 特性标记 | `traits: UpdatesFrequently` |
