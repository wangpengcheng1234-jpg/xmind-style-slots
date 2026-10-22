#!/bin/bash
# 打预编译 release：生成通用二进制的面板 app 打包
# 产物放到 release/XmindStylePanel-macos-universal.tar.gz
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${XMINDSLOTS_VERSION:-1.0}"
RELEASE="$ROOT/release"
rm -rf "$RELEASE"
mkdir -p "$RELEASE"

echo "▼ 编译面板 ..."
"$ROOT/panel/build.sh"

APP="$HOME/Applications/Xmind 样式槽.app"
OUT="$RELEASE/XmindStylePanel-macos-universal.tar.gz"

echo "▼ 打包 $OUT ..."
tar -czf "$OUT" -C "$HOME/Applications" "Xmind 样式槽.app"

echo ""
echo "✓ Release 打包完成"
echo "  产物: $OUT"
echo "  大小: $(du -sh "$OUT" | awk '{print $1}')"
echo ""
echo "  GitHub Release attach: release/XmindStylePanel-macos-universal.tar.gz"
