#!/usr/bin/env bash
set -e

REPO_URL="https://github.com/topogrow/zcode-prompt-enhancer.git"
INSTALL_DIR="$HOME/Applications/ZCODE提示词润色"

echo "✨ 正在安装 ZCODE 提示词润色小工具..."

# 1. 若当前不在源码目录，则克隆或更新
if [ ! -f "build-app.sh" ]; then
  mkdir -p "$INSTALL_DIR"
  if [ -d "$INSTALL_DIR/.git" ]; then
    echo "🔄 正在拉取最新代码..."
    cd "$INSTALL_DIR" && git pull --quiet
  else
    echo "📥 正在克隆开源仓库..."
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
  fi
fi

# 2. 一键构建独立应用
echo "🔨 正在编译打包独立应用 (约需1秒)..."
./build-app.sh >/dev/null

# 3. 复制到系统 Applications 文件夹 (可选) 并启动
APP_PATH="dist/ZCODE提示词润色.app"
echo "🚀 正在启动应用..."
open "$APP_PATH"

# 4. 在默认浏览器中打开 GitHub 仓库引导用户点 Star
echo "🌟 正在打开 GitHub 仓库页面，请帮忙点个免费的 Star 支持作者！"
open "https://github.com/topogrow/zcode-prompt-enhancer"

echo "🎉 安装完成并已启动！"
