# Context: iOS Use Skill

## 决策记录

| ADR | 标题 | 状态 |
|-----|------|------|

## 术语

| 术语 | 定义 |
|------|------|
| WDA | WebDriverAgent，iOS 自动化测试服务，通过 HTTP JSON API 交互 |
| UDID | iOS 设备唯一标识符，40 位十六进制字符串 |
| wda_endpoint | WDA 服务地址，格式 `http://<host>:<port>`，存储在 `wda.json` 中 |
| snapshot | 单次 observe 操作，包含 source（页面结构）+ screenshot（屏幕截图） |
| source | 页面元素树的 JSON 表示，通过 `/wda/accessibleSource` 获取 |
| screenshot | 屏幕截图，原始 PNG 经 sips 转 JPEG 并 resize |

## 文件规范

| 文件 | 用途 | 命名规则 |
|------|------|----------|
| `wda.json` | WDA 运行状态和端点配置 | 固定名称，无 UDID |
| `wda.log` | WDA 运行日志 | 固定名称 |
| `iproxy.log` | iproxy 转发日志 | 固定名称 |
| `<NNN>-source.json` | snapshot 页面源码 | 三位数字序号递增 |
| `<NNN>-screenshot.jpg` | snapshot 截图 | 与 source 同序号配对 |

## 目录结构

```
./tmp/
├── wda.json
├── wda.log
├── iproxy.log
└── wda-snapshot-<UDID>/
    └── YYYYMMDD/
        ├── 001-source.json
        ├── 001-screenshot.jpg
        ├── 002-source.json
        └── 002-screenshot.jpg
```
