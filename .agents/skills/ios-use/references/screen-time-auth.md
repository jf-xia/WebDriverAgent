# Screen Time 权限授权流程

## 场景

App 首次请求 Screen Time 访问权限时的完整授权流程。

## 流程步骤

### 1. 检测权限弹窗

```bash
# 检查是否有弹窗
curl -s http://localhost:8100/session/{SESSION_ID}/alert/text

# 获取弹窗按钮
curl -s http://localhost:8100/session/{SESSION_ID}/wda/alert/buttons
```

弹窗内容：`"{AppName}" Would Like to Access Screen Time`

按钮：`Continue` / `Don't Allow`

### 2. 点击 Continue

```bash
# 方法1: 元素点击
curl -s -X POST http://localhost:8100/session/{SESSION_ID}/element \
  -H "Content-Type: application/json" \
  -d '{"using": "name", "value": "Continue"}'

curl -s -X POST http://localhost:8100/session/{SESSION_ID}/element/{ELEMENT_ID}/click

# 方法2: 坐标点击（元素点击失败时）
curl -s -X POST http://localhost:8100/session/{SESSION_ID}/wda/tap \
  -H "Content-Type: application/json" \
  -d '{"x": 127, "y": 528}'
```

### 3. Allow Access to Screen Time 页面

页面标题：`Allow Access to Screen Time`

按钮：`Allow with Face ID` / `Don't Allow`

```bash
# 点击 Allow with Face ID
curl -s -X POST http://localhost:8100/session/{SESSION_ID}/element \
  -H "Content-Type: application/json" \
  -d '{"using": "name", "value": "Allow with Face ID"}'

curl -s -X POST http://localhost:8100/session/{SESSION_ID}/element/{ELEMENT_ID}/click
```

### 4. Face ID 验证（可能失败）

点击后会触发 Face ID 验证。真机自动化时 Face ID 通常无法识别，会弹出密码输入界面。

### 5. 输入密码

弹窗：`Face Not Recognized` → 点击 `Enter Passcode`

密码输入界面：数字键盘，需要点击对应数字

```bash
# 数字键盘坐标（以 402x874 屏幕为例）
# 1 2 3   -> y ≈ 350
# 4 5 6   -> y ≈ 460
# 7 8 9   -> y ≈ 570
# 0       -> y ≈ 680

# x 坐标：1≈67, 2≈201, 3≈335, 4≈67, 5≈201, 6≈335...

# 输入密码 5555
for i in 1 2 3 4; do
  curl -s -X POST http://localhost:8100/session/{SESSION_ID}/wda/tap \
    -H "Content-Type: application/json" \
    -d '{"x": 201, "y": 460}'
  sleep 0.3
done
```

### 6. 授权成功确认

页面显示：`"{AppName}" Approved to Access Screen Time`

点击 `Done` 按钮完成。

```bash
curl -s -X POST http://localhost:8100/session/{SESSION_ID}/wda/tap \
  -H "Content-Type: application/json" \
  -d '{"x": 201, "y": 830}'
```

## 注意事项

1. **Face ID 无法自动化** - 真机测试时 Face ID 验证会失败，必须走密码流程
2. **密码需要提前获取** - 自动化前确认设备密码
3. **坐标因设备而异** - 上述坐标基于 402x874 屏幕，其他设备需调整
4. **系统弹窗限制** - 部分系统弹窗 WDA 无法通过 name 定位，需用坐标点击

## 完整脚本示例

```bash
#!/bin/bash
SESSION_ID="YOUR_SESSION_ID"
WDA_URL="http://127.0.0.1:8100"
PASSCODE="5555"

# 1. 检测并点击 Continue
ELEMENT=$(curl -s -X POST "${WDA_URL}/session/${SESSION_ID}/element" \
  -H "Content-Type: application/json" \
  -d '{"using": "name", "value": "Continue"}')
ELEMENT_ID=$(echo "$ELEMENT" | jq -r '.value.ELEMENT')
curl -s -X POST "${WDA_URL}/session/${SESSION_ID}/element/${ELEMENT_ID}/click"
sleep 1

# 2. 点击 Allow with Face ID
ELEMENT=$(curl -s -X POST "${WDA_URL}/session/${SESSION_ID}/element" \
  -H "Content-Type: application/json" \
  -d '{"using": "name", "value": "Allow with Face ID"}')
ELEMENT_ID=$(echo "$ELEMENT" | jq -r '.value.ELEMENT')
curl -s -X POST "${WDA_URL}/session/${SESSION_ID}/element/${ELEMENT_ID}/click"
sleep 1

# 3. 点击 Enter Passcode（如果出现）
curl -s -X POST "${WDA_URL}/session/${SESSION_ID}/wda/tap" \
  -H "Content-Type: application/json" \
  -d '{"x": 201, "y": 470}'
sleep 0.5

# 4. 输入密码
declare -A KEYS=( [1]="67,350" [2]="201,350" [3]="335,350" [4]="67,460" [5]="201,460" [6]="335,460" [7]="67,570" [8]="201,570" [9]="335,570" [0]="201,680" )

for (( i=0; i<${#PASSCODE}; i++ )); do
  digit="${PASSCODE:$i:1}"
  IFS=',' read -r x y <<< "${KEYS[$digit]}"
  curl -s -X POST "${WDA_URL}/session/${SESSION_ID}/wda/tap" \
    -H "Content-Type: application/json" \
    -d "{\"x\": $x, \"y\": $y}"
  sleep 0.3
done
sleep 1

# 5. 点击 Done
curl -s -X POST "${WDA_URL}/session/${SESSION_ID}/wda/tap" \
  -H "Content-Type: application/json" \
  -d '{"x": 201, "y": 830}'
```
