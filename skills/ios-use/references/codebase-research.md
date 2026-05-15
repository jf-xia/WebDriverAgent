# 代码库研究与分析

## 概述

当现有脚本和文档不足以解释行为时，直接回到仓库代码确认真实实现。分析结果存到项目根目录 `tmp/`，供后续优化参考。

## 推荐方式

优先顺序：

1. `rg` 搜索：先找路由、handler、错误文本、capability 常量
2. 读实现文件：确认 handler 真正调用的 Objective-C / TypeScript 逻辑
3. 必要时看测试：优先 IntegrationTests、UnitTests、`test/` 下已有用例
4. 仍不清楚再看 `git log` / `git blame`

### 常用查询示例

```bash
# 接口处理链路
rg 'POST:@"/session"|handleCreateSession' WebDriverAgentLib lib test

# 参数生效机制
rg 'frequency|maxTypingFrequency' WebDriverAgentLib lib test

# 错误来源追踪
rg 'No Such Driver|FBSessionDoesNotExistException' WebDriverAgentLib lib test

# source 差异
rg 'accessibleSource|handleGetSourceCommand|handleGetAccessibleSourceCommand' WebDriverAgentLib

# 点击链路
rg 'element/:uuid/click|/wda/element/:uuid/tap|handleTap|handleClick' WebDriverAgentLib

# 键盘与输入
rg '/wda/keys|keyboard|value|clear' WebDriverAgentLib
```

## 研究流程

### 1. 问题识别

从以下来源识别问题：
- 操作失败日志
- 脚本执行异常
- 用户反馈的不一致行为
- 文档与实际行为的差异

### 2. 代码分析

直接定位相关代码路径：
- 接口处理链路
- 错误抛出点
- 参数验证逻辑
- 状态管理机制

### 3. 解决方案

根据分析结果提出解决方案：
- 修复 Skills 缺陷
- 优化操作流程
- 优化脚本

### 4. 验证与迭代

- 实施解决方案
- 通过脚本测试验证修复效果
- 收集反馈，必要时迭代优化

### 5. 验收

- 总结并记录在 `tmp/` 文件夹，供后续参考
- 把确认过的实现差异同步回 SKILL / reference / script