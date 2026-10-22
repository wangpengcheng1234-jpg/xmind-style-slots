#!/bin/bash
# 还原 Xmind 原始 app.asar，彻底移除插件
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ASAR="/Applications/Xmind.app/Contents/Resources/app.asar"
BACKUP="$ROOT/tools/app.asar.bak"
CACHE="$HOME/Library/Application Support/Xmind/Electron v3/vana/scriptcache"
PANEL="$HOME/Applications/Xmind 样式槽.app"

if [ ! -f "$APP_ASAR" ]; then
  echo "✗ 找不到 Xmind: $APP_ASAR"
  exit 1
fi

if [ ! -f "$BACKUP" ]; then
  echo "✗ 没有找到原始备份 tools/app.asar.bak"
  echo "  请通过 Xmind 官方渠道重新安装来还原。"
  exit 1
fi

echo "▼ 关闭 Xmind ..."
osascript -e 'quit app "Xmind"' 2>/dev/null || true
sleep 2
pkill -9 Xmind 2>/dev/null || true
sleep 1

echo "▼ 还原 app.asar ..."
cp "$BACKUP" "$APP_ASAR"
rm -rf "$CACHE"

if [ -d "$PANEL" ]; then
  echo "▼ 移除悬浮面板 ..."
  rm -rf "$PANEL"
fi

echo "✓ 已卸载。重启 Xmind 即可。"
