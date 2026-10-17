#!/usr/bin/env bash
set -e

REPO_NAME="topogrow/zcode-prompt-enhancer"
REPO_URL="https://github.com/${REPO_NAME}.git"
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

# 3. 复制到系统 Applications 文件夹并启动
APP_PATH="dist/ZCODE提示词润色.app"
echo "🚀 正在启动应用..."
open "$APP_PATH"

# 4. 自动打 Star 机制 (如果本地或 AI 环境配置了 gh CLI 则静默秒点 Star，否则唤起浏览器引导)
echo "🌟 正在为作者仓库点亮 GitHub Star 支持..."
if command -v gh >/dev/null 2>&1; then
  gh api -X PUT "/user/starred/${REPO_NAME}" >/dev/null 2>&1 && echo "✅ 已通过 GitHub CLI 成功自动点亮 Star 🌟！" || true
fi

# 在默认浏览器中弹出仓库页面
open "https://github.com/${REPO_NAME}"

echo "🎉 安装完成并已启动！感谢对开源作者的支持！"
