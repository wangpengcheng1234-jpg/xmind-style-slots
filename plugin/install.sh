#!/bin/bash
# 一键安装 Xmind 快捷样式槽插件
# 自举 node / npm / asar，从用户机器上的 Xmind 解包并注入
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/tools"
APP_ASAR="/Applications/Xmind.app/Contents/Resources/app.asar"
BACKUP="$TOOLS/app.asar.bak"
CACHE="$HOME/Library/Application Support/Xmind/Electron v3/vana/scriptcache"
SRC="$TOOLS/xmind-unpacked-orig"
BUILD="$TOOLS/build/xmind"
OUT="$TOOLS/build/app.asar"
ARCH="$(uname -m)"

# --- 前置检查 ---

if [ ! -f "$APP_ASAR" ]; then
  echo "✗ 找不到 Xmind: $APP_ASAR"
  echo "  请确认 Xmind 安装在 /Applications/Xmind.app"
  exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
  echo "✗ 缺少 swiftc（Xcode Command Line Tools）"
  echo "  运行: xcode-select --install"
  exit 1
fi

# --- 1. 自举 node ---

get_node() {
  local node_dir="$TOOLS/node"
  local node_bin="$node_dir/bin/node"
  if [ -x "$node_bin" ]; then
    echo "$node_bin"
    return
  fi
  if command -v node >/dev/null 2>&1; then
    echo "$(command -v node)"
    return
  fi
  echo "▼ 下载 Node.js v20.19.0 ..."
  local pkg="node-v20.19.0-darwin-${ARCH}"
  local url="https://nodejs.org/dist/v20.19.0/${pkg}.tar.xz"
  mkdir -p "$node_dir"
  curl -fsSL "$url" | tar -xJ -C "$TOOLS/node" --strip-components=1 || {
    echo "✗ Node.js 下载失败，请检查网络"
    exit 1
  }
  echo "$node_bin"
}

NODE_BIN="$(get_node)"
"$NODE_BIN" --version
export PATH="$(dirname "$NODE_BIN"):$PATH"
# 确认 npm 来自 node 包（而不是系统里可能没有）
NPM_BIN="$(command -v npm || true)"
if [ -z "$NPM_BIN" ]; then
  echo "✗ node 包里没找到 npm，请检查 tools/node 目录"
  exit 1
fi
echo "  npm: $("$NPM_BIN" --version)"

# --- 2. npm install asar ---

echo "▼ 安装 asar ..."
mkdir -p "$TOOLS"
cd "$TOOLS"
if [ ! -f package.json ]; then
  echo '{"dependencies":{"asar":"^3.2.0"}}' > package.json
fi
"$NPM_BIN" install --no-audit --no-fund --loglevel=error
ASAR_BIN="$TOOLS/node_modules/.bin/asar"
if [ ! -x "$ASAR_BIN" ]; then
  echo "✗ asar 安装失败"
  exit 1
fi

# --- 3. 备份原始 asar（首次） ---

if [ ! -f "$BACKUP" ]; then
  echo "▼ 备份原始 app.asar ..."
  cp "$APP_ASAR" "$BACKUP"
fi

# --- 4. 解包原始 asar（首次） ---

if [ ! -d "$SRC" ]; then
  echo "▼ 解包 Xmind app.asar ...（较大，请稍候）"
  mkdir -p "$TOOLS"
  cd "$TOOLS"
  "$ASAR_BIN" extract "$APP_ASAR" "$SRC"
fi

# --- 5. 注入 + 重打包 ---

echo "1/3 准备构建目录..."
rm -rf "$BUILD"
mkdir -p "$TOOLS/build"
cp -R "$SRC" "$BUILD"

echo "2/3 注入插件到 renderer/editor.js ..."
cat "$ROOT/plugin/xmind-style-slots.js" >> "$BUILD/renderer/editor.js"

# 开放本机调试端口（仅 127.0.0.1），供悬浮面板通信；并让面板跟随 Xmind 开关
cat >> "$BUILD/main/hook.js" <<'HOOK'

// === Xmind 样式槽面板 hook ===
try {
  const { app } = require("electron");
  const { exec } = require("child_process");
  const fs = require("fs");
  const path = require("path");
  const home = require("os").homedir();
  app.commandLine.appendSwitch("remote-debugging-port", "9222");
  app.commandLine.appendSwitch("remote-debugging-address", "127.0.0.1");

  const candidates = [
    path.join(home, "Applications", "Xmind 样式槽.app"),
    "/Applications/Xmind 样式槽.app",
  ];
  const panelApp = candidates.find((p) => fs.existsSync(p));
  if (panelApp) {
    setTimeout(() => exec(`open -gj "${panelApp}"`), 1500);
    app.on("will-quit", () => exec("pkill -f XmindStylePanel"));
  }
} catch (e) {}
HOOK

echo "3/3 打包 app.asar ..."
rm -f "$OUT"
cd "$TOOLS"
"$ASAR_BIN" pack "$BUILD" "$OUT" >/dev/null

# --- 6. 停 Xmind + 安装 ---

echo "▼ 关闭 Xmind 并替换 app.asar ..."
osascript -e 'quit app "Xmind"' 2>/dev/null || true
sleep 3
pkill -9 Xmind 2>/dev/null || true
sleep 1
cp "$OUT" "$APP_ASAR"
rm -rf "$CACHE"

# --- 7. 编译并安装悬浮面板 ---

echo "▼ 编译并安装悬浮面板 ..."
"$ROOT/panel/build.sh"

echo ""
echo "✓ 安装完成。启动 Xmind 后："
echo "    ⌃⌥1~5    应用样式槽"
echo "    ⌃⌥⇧1~5   保存当前样式到槽位"
echo ""
echo "  如需卸载：plugin/uninstall.sh"
