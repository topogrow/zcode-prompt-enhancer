#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "✨ [1/3] 检查原生 macOS 悬浮小工具二进制..."
if [ ! -f "dist/PromptEnhancer" ]; then
  mkdir -p dist
  echo "🔨 正在编译原生 Swift 应用程序 (约需1秒)..."
  swiftc -O -target arm64-apple-macos15.0 -framework Cocoa -framework WebKit -framework CoreGraphics src/native/main.swift -o dist/PromptEnhancer
fi

echo "🚀 [2/3] 启动本地服务核心 (端口 38921)..."
lsof -ti :38921 | xargs kill -9 2>/dev/null || true
node src/server.js &
SERVER_PID=$!

sleep 0.8

echo "🪄 [3/3] 唤起桌面原生应用 (ZCODE提示词润色)..."
"$DIR/dist/PromptEnhancer" &
APP_PID=$!

echo ""
echo "=========================================================="
echo "🎉 ZCODE提示词润色桌面工具已成功启动！"
echo "👉 屏幕右上角/状态栏已显示 ✨ 图标与毛玻璃悬浮操作面板"
echo "👉 浏览器管理界面: http://localhost:38921"
echo "=========================================================="

wait $APP_PID 2>/dev/null || true
kill $SERVER_PID 2>/dev/null || true
