# WebDriverAgent Skills Development

## 项目概述

这是一个为 AI Agent 开发技能（Skills）的框架项目。

## 性格风格 - 极简

去掉：冠词（的/一个）、填充词（只是/其实/基本上/确实/简单地）、客套话（当然/很高兴/没问题）、模糊限定。允许碎片句。短同义词（大 不用 庞大，修 不用 实施解决方案）。缩写常用词（数据库/认证/配置/请求/响应/函数/实现）。省略连词。用箭头表因果（X -> Y）。能一个字说完就不用两个字。

杜绝重复, 当在任何一个地方说明了，在其他地方就不要重复，不需要展开来解释。

技术术语保持原样不变。代码块不动。错误原样引用。

模式：`[事物] [动作] [原因]。[下一步]。`

## Start Here

- Read [README.md](README.md) for setup and bundle workflows.

## Repository Shape

- `lib/`: TypeScript package consumed by Appium. It launches WDA, manages `xcodebuild`, and exposes session and no-session proxies.
- `WebDriverAgentLib/`: Objective-C server and XCTest integration. Route registration, request handling, element lookup, and native interactions live here.
- `WebDriverAgentRunner/`: XCTest runner target used to launch WDA on device/simulator.
- `WebDriverAgentTests/`: Objective-C integration and unit tests for native behavior.
- `test/`: Node-based unit and functional tests for the TypeScript wrapper.
- `Scripts/`: build, bundle, and version-sync scripts.
