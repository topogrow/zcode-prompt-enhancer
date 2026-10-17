import fs from 'node:fs';
import path from 'node:path';

/**
 * 极速项目工程画像提取器 (Project Profiler)
 * 在 10ms 左右完成对目标项目目录的轻量分析，提取技术栈、关键目录结构与架构约定。
 */
export class ProjectProfiler {
  /**
   * 分析指定项目目录
   * @param {string} projectDir 目标项目绝对路径
   * @returns {ProjectProfile}
   */
  static analyze(projectDir) {
    if (!projectDir || !fs.existsSync(projectDir)) {
      return null;
    }

    const stat = fs.statSync(projectDir);
    if (!stat.isDirectory()) {
      return null;
    }

    const projectName = path.basename(projectDir);
    const frameworks = new Set();
    let language = 'Unknown';
    let buildTool = 'Unknown';

    // 1. 探测配置文件与依赖
    const packageJsonPath = path.join(projectDir, 'package.json');
    const cargoTomlPath = path.join(projectDir, 'Cargo.toml');
    const goModPath = path.join(projectDir, 'go.mod');
    const pyprojectPath = path.join(projectDir, 'pyproject.toml');
    const reqsPath = path.join(projectDir, 'requirements.txt');
    const tsconfigPath = path.join(projectDir, 'tsconfig.json');

    // Node / JS / TS 生态
    if (fs.existsSync(packageJsonPath)) {
      language = fs.existsSync(tsconfigPath) ? 'TypeScript' : 'JavaScript';
      try {
        const pkg = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
        const allDeps = {
          ...(pkg.dependencies || {}),
          ...(pkg.devDependencies || {}),
        };

        // 核心前端/后端框架
        if (allDeps['react']) frameworks.add(`React ${pkg.dependencies?.react ? pkg.dependencies.react.replace(/[\^~]/g, '') : ''}`.trim());
        if (allDeps['vue']) frameworks.add(`Vue ${pkg.dependencies?.vue ? pkg.dependencies.vue.replace(/[\^~]/g, '') : ''}`.trim());
        if (allDeps['next']) frameworks.add('Next.js');
        if (allDeps['nuxt']) frameworks.add('Nuxt.js');
        if (allDeps['svelte']) frameworks.add('Svelte');
        if (allDeps['electron']) frameworks.add('Electron');
        if (allDeps['@tauri-apps/api']) frameworks.add('Tauri');
        if (allDeps['express']) frameworks.add('Express');
        if (allDeps['koa']) frameworks.add('Koa');
        if (allDeps['nest']) frameworks.add('NestJS');
        if (allDeps['fastify']) frameworks.add('Fastify');

        // UI 与样式库
        if (allDeps['tailwindcss']) frameworks.add('Tailwind CSS');
        if (allDeps['antd']) frameworks.add('Ant Design');
        if (allDeps['element-plus']) frameworks.add('Element Plus');
        if (allDeps['@mui/material']) frameworks.add('Material UI');
        if (allDeps['shadcn-ui'] || allDeps['@radix-ui/react-primitive']) frameworks.add('Radix UI / shadcn');

        // 状态管理与数据流
        if (allDeps['zustand']) frameworks.add('Zustand');
        if (allDeps['redux'] || allDeps['@reduxjs/toolkit']) frameworks.add('Redux');
        if (allDeps['pinia']) frameworks.add('Pinia');
        if (allDeps['@tanstack/react-query']) frameworks.add('React Query');

        // 构建工具
        if (allDeps['vite']) buildTool = 'Vite';
        else if (allDeps['webpack']) buildTool = 'Webpack';
        else if (allDeps['turbo']) buildTool = 'Turborepo';
      } catch (e) {
        // 忽略解析错误
      }
    }

    // Rust 生态
    if (fs.existsSync(cargoTomlPath)) {
      language = 'Rust';
      buildTool = 'Cargo';
      try {
        const cargoText = fs.readFileSync(cargoTomlPath, 'utf8');
        if (cargoText.includes('tauri')) frameworks.add('Tauri');
        if (cargoText.includes('tokio')) frameworks.add('Tokio');
        if (cargoText.includes('actix-web')) frameworks.add('Actix-Web');
        if (cargoText.includes('axum')) frameworks.add('Axum');
        if (cargoText.includes('serde')) frameworks.add('Serde');
      } catch (e) {}
    }

    // Go 生态
    if (fs.existsSync(goModPath)) {
      language = 'Go';
      buildTool = 'Go Modules';
      try {
        const goModText = fs.readFileSync(goModPath, 'utf8');
        if (goModText.includes('github.com/gin-gonic/gin')) frameworks.add('Gin');
        if (goModText.includes('github.com/gofiber/fiber')) frameworks.add('Fiber');
      } catch (e) {}
    }

    // Python 生态
    if (fs.existsSync(pyprojectPath) || fs.existsSync(reqsPath)) {
      language = 'Python';
      try {
        const content = (fs.existsSync(pyprojectPath) ? fs.readFileSync(pyprojectPath, 'utf8') : '') +
          (fs.existsSync(reqsPath) ? fs.readFileSync(reqsPath, 'utf8') : '');
        if (content.includes('fastapi')) frameworks.add('Fastapi');
        if (content.includes('flask')) frameworks.add('Flask');
        if (content.includes('django')) frameworks.add('Django');
        if (content.includes('torch')) frameworks.add('PyTorch');
      } catch (e) {}
    }

    // 2. 扫描顶层核心结构 (深度<=2，过滤常见忽略目录)
    const ignoreDirs = new Set(['node_modules', '.git', 'dist', 'build', 'target', '.next', '.nuxt', '.turbo', '.vscode', '.idea']);
    const directories = [];
    try {
      const topItems = fs.readdirSync(projectDir);
      for (const item of topItems) {
        if (ignoreDirs.has(item) || item.startsWith('.')) continue;
        const fullPath = path.join(projectDir, item);
        try {
          if (fs.statSync(fullPath).isDirectory()) {
            // 检查子目录
            const subItems = fs.readdirSync(fullPath)
              .filter(sub => !ignoreDirs.has(sub) && !sub.startsWith('.'))
              .slice(0, 5);
            if (subItems.length > 0) {
              directories.push(`${item}/{${subItems.join(', ')}}`);
            } else {
              directories.push(item);
            }
          }
        } catch (e) {}
      }
    } catch (e) {}

    // 3. 提取项目规则 (如 CLAUDE.md, .cursorrules, AGENTS.md, README.md)
    let ruleExcerpt = '';
    const ruleFiles = ['.cursorrules', 'CLAUDE.md', 'AGENTS.md', '.rules'];
    for (const rf of ruleFiles) {
      const rfPath = path.join(projectDir, rf);
      if (fs.existsSync(rfPath)) {
        try {
          const lines = fs.readFileSync(rfPath, 'utf8').split('\n').slice(0, 20).join('\n').trim();
          if (lines) {
            ruleExcerpt = lines;
            break;
          }
        } catch (e) {}
      }
    }

    return {
      projectName,
      projectDir,
      language,
      buildTool,
      frameworks: Array.from(frameworks),
      directories: directories.slice(0, 6),
      ruleExcerpt: ruleExcerpt ? ruleExcerpt.slice(0, 300) : '',
    };
  }

  /**
   * 格式化为注入到 Prompt 的结构化轻量文本 (Token 开销约 50~100)
   * @param {ProjectProfile} profile
   * @returns {string}
   */
  static formatForPrompt(profile) {
    if (!profile) return '';

    const lines = [
      `[PROJECT ENVIRONMENT]`,
      `- Project Name: ${profile.projectName}`,
      `- Language/Runtime: ${profile.language}`,
    ];

    if (profile.frameworks && profile.frameworks.length > 0) {
      lines.push(`- Key Frameworks & Libraries: ${profile.frameworks.join(', ')}`);
    }

    if (profile.buildTool && profile.buildTool !== 'Unknown') {
      lines.push(`- Build Tool: ${profile.buildTool}`);
    }

    if (profile.directories && profile.directories.length > 0) {
      lines.push(`- Directory Layout: ${profile.directories.join(', ')}`);
    }

    if (profile.ruleExcerpt) {
      lines.push(`- Project Guidelines Excerpt:\n"""\n${profile.ruleExcerpt}\n"""`);
    }

    lines.push(
      `\n[SPECIAL INSTRUCTION FOR PROJECT CONTEXT]:`,
      `When enhancing the prompt for code-related tasks, ensure the requirements naturally align with the project's existing tech stack and conventions above. Do NOT introduce conflicting or uninstalled frameworks. If the user's prompt is non-technical or general, focus on the user's intent without forcing project context.`
    );

    return lines.join('\n');
  }
}
