# WDA Source 优化指南

## 问题描述
WDA的 `/source` API返回的信息过多，包含许多对AI Agent无用的属性，导致响应过大。

## 解决方案

### 1. 使用排除属性参数
WDA支持 `excluded_attributes` 参数来排除不需要的属性。

**推荐的精简URL：**
```
http://localhost:8100/source?format=json&excluded_attributes=frame,nativeFrame,enabled,visible,accessible,focused,placeholderValue,minValue,maxValue
```

**保留的属性：**
- `type` - 元素类型（必需）
- `rawIdentifier` - 元素标识符（有用）
- `name` - 元素名称（有用）
- `value` - 元素值（有用）
- `label` - 元素标签（有用）
- `rect` - 元素坐标和尺寸（必需，用于点击操作）
- `customActions` - 自定义操作（可选）
- `traits` - 元素特征（有用，包含按钮、链接等类型信息）

**排除的属性：**
- `frame` - 与`rect`重复，使用`rect`即可
- `nativeFrame` - 原始坐标系，通常不需要
- `enabled` - 启用状态，可从其他属性推断
- `visible` - 可见状态，可从其他属性推断
- `accessible` - 可访问性状态，通常不需要
- `focused` - 焦点状态，通常不需要
- `placeholderValue` - 占位符值，大多数元素没有
- `minValue` / `maxValue` - 最小/最大值，仅滑块等控件需要

### 2. 使用accessibleSource
更简洁的格式，只包含可访问性树：
```
http://localhost:8100/wda/accessibleSource
```

### 3. 使用脚本处理
提供Python脚本来获取、过滤和转换数据：

```bash
# 获取并转换为YAML
python3 wda_source_processor.py --host localhost --port 8100 --format yaml --output source.yaml

# 扁平化树形结构
python3 wda_source_processor.py --flatten --max-depth 2 --output flat-source.yaml

# 只保留特定属性
python3 wda_source_processor.py --keep type name label rect traits --output minimal.yaml
```

## 属性重要性分析

### 必需属性（AI Agent必须知道）
1. **type** - 元素类型（Button, TextField, Image等）
2. **rect** - 元素位置和尺寸，用于点击操作
3. **name/label** - 元素标识，用于查找和理解

### 有用属性（建议保留）
1. **rawIdentifier** - 元素唯一标识符
2. **value** - 元素当前值（如文本框内容）
3. **traits** - 元素特征（按钮、链接等）

### 可选属性（可排除）
1. **customActions** - 自定义操作，大多数元素没有
2. **frame/nativeFrame** - 与rect重复
3. **状态属性** - enabled, visible, accessible, focused

## 空值处理
- 完全省略空值属性（None、空字符串、空列表）
- 减少响应大小，提高可读性

## 扁平化选项
1. **完全扁平化** - 所有元素放在一个列表中，包含parent_id
2. **限制深度** - 只显示有限层级（如2-3层）
3. **保持树形** - 保留原始结构，但精简内容

## 推荐方案
对于AI Agent，建议：
1. 使用精简URL排除frame、nativeFrame等重复属性
2. 保留rect、type、name、label、traits
3. 使用脚本进一步处理，移除空值
4. 根据需要选择是否扁平化

## 测试命令
```bash
# 测试精简URL
curl "http://localhost:8100/source?format=json&excluded_attributes=frame,nativeFrame,enabled,visible,accessible,focused,placeholderValue,minValue,maxValue"

# 测试accessibleSource
curl "http://localhost:8100/wda/accessibleSource"

# 使用脚本处理
python3 wda_source_processor.py --format yaml --output test.yaml
```