<div align="center">
  <img src="assets/app-icon.png" width="128" height="128" alt="ZCODE提示词润色 Logo" style="border-radius: 28px; box-shadow: 0 12px 32px rgba(0,0,0,0.35);" />
  <h1>ZCODE 提示词润色</h1>
  <p><b>面向 AI 辅助编程与智能体研发的高性能桌面提示词智能增强工具</b></p>

  <p>
    <img src="https://img.shields.io/badge/Platform-macOS%2013%2B-blue?style=flat-square&logo=apple" alt="macOS" />
    <img src="https://img.shields.io/badge/Architecture-Swift%20%2B%20Node.js-orange?style=flat-square" alt="Architecture" />
    <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License" />
    <img src="https://img.shields.io/badge/Built%20for-ZCode%20%7C%20Cursor%20%7C%20VSCode-purple?style=flat-square" alt="Ecosystem" />
  </p>
</div>

---

## 🌟 核心特性 (Features)

### 1. 🎯 100% 工业级 Prompt 工程学规范（对齐 WorkBuddy）
- **绝不自行作答（Negative Constraint）**：严格约束模型只重写和细化需求，绝不自作主张提前写代码；
- **只定目标，不定解法**：聚焦于“做什么 (WHAT)”而非“怎么做 (HOW)”，将具体的实现路径留给编程主智能体；
- **语言严格保真（中英混排原样保留）**：程序员常说的 *“写个 hook 处理 loading 态”* 绝不会被强行翻译成生硬的纯英文或全中文；
- **输出纯净无污染**：内置后处理清洗流水线，自动剥离多余的双引号、Markdown 代码块标记及自言自语的前缀废话；
- **严格字数收敛**：结果收敛在 800 字符以内，避免污染主对话昂贵的上下文窗口。

### 2. ⚡ 毫秒级工程画像感知 (Project Profiler)
- **拒绝全量扫描的高开销**：在 **1.5ms** 内极速提取工程的 `package.json` / `Cargo.toml` / `go.mod` 等依赖与目录布局；
- **动态约束注入**：在提示词中自然融入项目真实使用的技术栈（如 `React 19`、`TypeScript`、`Tailwind CSS`），彻底消灭 AI 编程助手的“技术栈幻觉”。

### 3. 🔗 ZCode 会话一键联动 (ZCode Session Linkage)
- 直接联动本地 ZCode 会话数据库（`~/.zcode/cli/db/db.sqlite`）；
- 支持通过会话 ID 快速锁定，或在下拉列表中直接点选最近活跃的 ZCode 会话；
- 瞬间同步该会话关联的真实项目根路径与工程技术栈画像。

### 4. 💡 智能 ZCode 能力引用建议 (Capability Advisor)
- 根据提示词意图自动推导最匹配的 ZCode 专属运行时能力：
  - **复杂架构重构** ➔ 推荐 `[📋 Plan 模式]`；
  - **全库依赖排查** ➔ 推荐 `[🤖 Explore 只读智能体]`；
  - **多阶段流水线** ➔ 推荐 `[🔄 Dynamic Workflow 动态工作流]`；
  - **严谨业务逻辑** ➔ 推荐 `[🧪 TDD 测试驱动开发]`；
  - **交互看板大屏** ➔ 推荐 `[🎨 Gen UI 交互视图]`；
- 点击 **`[➕ 追加到提示词末尾]`**，一键将规范的调度声明注入到提示词尾部，发挥 ZCode 最大战斗力。

### 5. 🧲 主窗口磁贴吸附与实时联动跟随 (Magnetic Follow)
- 点击顶栏 **`[ ⇥ ]`** 按钮开启吸附模式；
- 内置 30 FPS 高帧率轻量运动监听器：**当拖拽或缩放 ZCode 窗口时，小工具就像磁铁一样无延迟紧贴在 ZCode 右侧同步跟随移动**；
- 退出吸附模式时自动平滑还原为普通悬浮窗。

### 6. 🎨 现代高颜值 UI 与全套深浅色主题
- **四套主题开箱即用**：
  - **现代暗色 (Modern Dark)**：细腻半透明毛玻璃质感（默认）；
  - **纯黑模式 (Pure Black)**：OLED 极致深黑高对比度；
  - **ZCode 专属同步色 (ZCode Sync)**：提取 ZCode 客户端色系，浑然一体；
  - **浅色模式 (Light Mode)**：高对比度清爽浅色，**支持跟随 macOS 系统外观自动切换**；
- **全套矢量 SVG 图标**：全界面告别 Emoji 表情，采用极简矢量图标，并提供纯文本紧凑模式；
- **macOS 标准红黄绿控制按钮**：顶栏左侧标准红黄绿控制，原生支持关闭、最小化至 Dock 栏及缩放；
- **调度中心全面支持**：取消强制全局置顶，在系统调度中心（Mission Control）中可自由平铺、缩放与预览；
- **全键盘快捷键**：全面支持 `Cmd+C` / `Cmd+V` / `Ctrl+C` / `Ctrl+V` 复制粘贴。

---

## 🚀 快速开始 (Quick Start)

### 方式一：直接运行独立应用（无需环境配置）
1. 运行打包脚本生成 App：
   ```bash
   ./build-app.sh
   ```
2. 在 Finder 中打开 `dist/` 目录，直接双击 **`ZCODE提示词润色.app`**（或拖入 `/Applications`）即可启动运行。

### 方式二：开发调试模式
```bash
# 启动本地服务与原生桌面窗口
./start.sh
```
浏览器管理界面同步运行在：[http://localhost:38921/](http://localhost:38921/)

---

## ⚙️ 模型配置 (LLM Configuration)

在界面右上角点击 **`[ ⚙️ ]`** 齿轮图标，支持零代码配置各类大模型：

| 模型平台 | 配置端点 (Endpoint) | 推荐模型 (Model) | 说明 |
| :--- | :--- | :--- | :--- |
| **DeepSeek (推荐)** | `https://api.deepseek.com` | `deepseek-chat` | 极速响应（< 0.8s），中文提示词理解顶尖，成本极低 |
| **本地 Ollama (完全离线)** | `http://localhost:11434` | `qwen2.5-coder:7b` | 0 费用、零 Token 开销、代码完全离线私有化 |
| **OpenAI** | `https://api.openai.com` | `gpt-4o-mini` | 国际化小模型基准 |
| **自定义 (Custom)** | 兼容 OpenAI 格式端点 | 自定义模型名 | 适配通义千问、智谱 GLM、Claude 等 |

---

## 🛠️ 项目架构 (Architecture)

```text
zcode-prompt-enhancer/
├── assets/
│   ├── app-icon.png               # 1024x1024 高清应用图标
│   └── AppIcon.icns               # macOS 原生多分辨率图标包
├── src/
│   ├── core/
│   │   ├── project-profiler.js    # 毫秒级工程技术栈画像探测器
│   │   ├── prompt-engine.js       # 对齐 WorkBuddy 规则的提示词引擎
│   │   ├── zcode-session-resolver.js # ZCode 会话 ID 与工作区解析器
│   │   └── zcode-advisor.js       # ZCode 专属底层能力推荐器
│   ├── native/
│   │   └── main.swift             # 原生 macOS 宿主 (含磁贴跟随、主菜单与WKWebView)
│   ├── bridge/
│   │   └── in-place-enhancer.js   # 系统选中文本快捷键原位替换脚本
│   ├── ui/
│   │   └── index.html             # 现代响应式深浅色 Webview 界面
│   └── server.js                  # 本地守护服务核心 (端口 38921)
├── test/
│   └── run-tests.js               # 自动化集成测试套件 (6/6 通过)
├── build-app.sh                   # macOS 独立客户端打包构建脚本
├── start.sh                       # 本地一键启动脚本
└── package.json
```

---

## 📄 开源许可 (License)

本项目基于 [MIT License](LICENSE) 开源协议发布。
