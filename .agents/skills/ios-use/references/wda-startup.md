# WDA 启动参考

只在 `curl -s --connect-timeout 3 --max-time 10 $WDA/status | jq .` 不通时使用。

## 真机最简流程

```bash
SCRIPTS=./.agents/skills/ios-use/scripts
PORT=${PORT:-8100}
WDA=http://127.0.0.1:$PORT
PROJECT_PATH=~/work/WebDriverAgent/WebDriverAgent.xcodeproj
SCHEME=WebDriverAgentRunner
LOG_DIR=./tmp

if curl -s --connect-timeout 3 --max-time 10 "$WDA/status" | jq . >/dev/null 2>&1; then
  echo "WDA 已启动: $WDA"
  exit 0
fi

# 依赖: xcodebuild xcrun jq tmux iproxy idevice_id
# 安装 iproxy / idevice_id: brew install libimobiledevice

UDID=${UDID:-$(idevice_id -l 2>/dev/null | head -1)}
if [[ -z "$UDID" ]]; then
  UDID=$(xcrun xctrace list devices 2>/dev/null | awk '/^iPhone / && !/Offline/ && !/Simulator/ {print $NF}' | tr -d '()' | head -1)
fi

mkdir -p "$LOG_DIR"
tmux kill-session -t "iproxy-$PORT" 2>/dev/null || true
tmux kill-session -t "wda-$PORT" 2>/dev/null || true
if lsof -ti:"$PORT" >/dev/null; then
  lsof -ti:"$PORT" | xargs kill 2>/dev/null || true
fi

tmux new-session -d -s "iproxy-$PORT" \
  "iproxy $PORT $PORT -u $UDID 2>&1 | tee $LOG_DIR/iproxy.log"

tmux new-session -d -s "wda-$PORT" \
  "USE_PORT=$PORT xcodebuild -project \"$PROJECT_PATH\" -scheme \"$SCHEME\" -destination \"id=$UDID\" test 2>&1 | tee \"$LOG_DIR/wda.log\""

curl -s --connect-timeout 3 --max-time 10 "$WDA/status" | jq .
```

## 看日志

```bash
tmux attach -t "iproxy-$PORT"
tmux attach -t "wda-$PORT"
tail -f ./tmp/iproxy.log
tail -f ./tmp/wda.log
```

## 失败排查

1. 看 `tmp/iproxy.log` 是否端口转发成功。
2. 看 `tmp/wda.log` 是否卡在签名、信任、测试失败。
3. 确认 `UDID` 不是空值，设备已连接、已解锁、已信任 Mac。