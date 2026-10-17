# 提示词增强小工具 (PromptEnhancer) 架构设计

## 一、 系统全景架构

```text
┌─────────────────────────────────────────────────────────────┐
│                 桌面端 UI 交互层 (Presentation Layer)       │
│  ┌───────────────────────┐       ┌───────────────────────┐  │
│  │   悬浮胶囊 / 托盘图标   │ <───> │  精简浮窗 (Popup UI)   │  │
│  └───────────────────────┘       └───────────────────────┘  │
│         ▲                                   │               │
│         │ 快捷键呼出 / 原位替换              ▼ 触发润色 / 回退  │
└─────────┼───────────────────────────────────┼───────────────┘
          │ (AppleScript / Accessibility)     │
┌─────────▼───────────────────────────────────▼───────────────┐
│                    核心业务层 (Core Layer)                   │
│                                                             │
│  1. 项目工程画像探测器 (Project Profiler)                   │
│     ├── 目录扫描 (package.json / Cargo.toml / go.mod ...)   │
│     ├── 顶层规范提取 (src/components, pages, api ...)        │
│     └── 指引扫描 (.cursorrules / CLAUDE.md / README.md)      │
│                                                             │
│  2. 提示词增强引擎 (Prompt Engine - WorkBuddy 对齐)           │
│     ├── System Prompt (代码助手专业 Prompt 约束)            │
│     ├── 动态工程上下文包装器 (Context Wrapper)              │
│     ├── 语言一致性校验器 (保持中英混排原貌)                   │
│     └── 后处理管道 (剥离包裹引号、清洗格式)                   │
│                                                             │
│  3. 状态与会话管理 (Session & State Machine)                │
│     ├── 撤销栈管理 (Backup Blocks & Revert)                 │
│     ├── 内容分叉感知 (Content Divergence Detector)          │
│     └── 异步取消控制 (AbortController Pipeline)             │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│                   模型通信层 (Provider Layer)                │
│   ├── 本地模型: Ollama (qwen2.5-coder, deepseek-coder 等)    │
│   └── 云端模型: DeepSeek API, OpenAI, Claude, 通义千问等    │
└─────────────────────────────────────────────────────────────┘
```

---

## 二、 关键技术问题剖析：如何关联项目目录来润色提示词？

很多开发者在尝试为 AI 工具增加“项目上下文”时容易陷入两个极端：
1. **极端 A（完全不关联）**：模型不知道项目用什么语言和框架，润色出来的提示词可能凭空假设或者太模糊；
2. **极端 B（过度关联 / 全仓库扫描）**：把成百上千个文件全都向量化或拼进 Prompt，导致耗时高达数秒甚至数十秒，Token 消耗巨大，完全无法满足在输入框“秒级润色”的极致体验。

### 我们的创新解法：“分层极速指纹提炼”（Tiered Fingerprinting）

我们将项目目录的感知分为**三层渐进式提炼**，整个探测过程在本地耗时 `< 15ms`，Token 消耗控制在 **50~100 Tokens** 以内：

```text
项目目录 (如 /my-project)
   │
   ├─► [Layer 1] 核心依赖探测器 (Dependency Profiler)
   │     • Node.js: package.json 中的 dependencies / devDependencies
   │     • Rust: Cargo.toml 中的 [dependencies]
   │     • Python: pyproject.toml / requirements.txt
   │     • Go: go.mod
   │     -> 提炼出关键技术栈标签: [React 19, TailwindCSS, Vite, TypeScript]
   │
   ├─► [Layer 2] 架构规范与目录结构 (Structure Profiler)
   │     • 仅遍历深度为 2 的顶层目录
   │     • 过滤无用目录: node_modules, .git, dist, build, target
   │     -> 提炼出组织惯例: src/{components, hooks, services, stores}
   │
   └─► [Layer 3] 项目已有契约规则 (Project Rules Profiler)
         • 检测是否存在规则文件: .cursorrules, CLAUDE.md, AGENTS.md
         • 仅提取前 30 行中的技术约束（如“全量使用 TypeScript 严格模式”，“组件必须使用函数式写法”）
```

### 动态注入 Prompt 的格式设计

提取后的结构化指纹，会在发送给模型时通过一个非常轻量、优雅的包裹层注入到 Prompt 尾部：

```text
[OPTIONAL PROJECT CONTEXT]
Project Directory: {projectName}
Language: {language}
Core Tech Stack: {frameworks}
Project Layout: {directories}
Conventions: {keyConventions}

[CONTEXT ENHANCEMENT RULE]
If the user's prompt relates to code implementation, naturally align the technical requirements with the existing project tech stack above. Do not introduce incompatible frameworks. If the prompt is general or non-coding, ignore this project context.
```

---

## 三、 对齐 WorkBuddy 的提示词工程细节

从本地已提取的代码中证实，WorkBuddy 的提示词之所以体感好，核心在于它的**四个黄金原则**：
1. **严格否定作答（Negative Constraint）**：明确写死 `Do NOT answer questions`，杜绝模型自己回答问题；
2. **语言严格保真**：中英混排保持原样，程序员常说的 *“帮我写个 hook 处理 loading 态”* 绝不会被翻译成别扭的全中文或全英文；
3. **只定目标，不定解法**：`Do NOT explain HOW to do things, focus on WHAT`，把具体的技术实现决策权留给后续的主编程模型；
4. **输出无污染**：去除外层引号、Markdown 代码块标记与客套话，确保直接贴入输入框立即可用。
