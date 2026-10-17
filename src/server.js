import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { exec } from 'node:child_process';
import { promisify } from 'node:util';
import { ProjectProfiler } from './core/project-profiler.js';
import { PromptEngine } from './core/prompt-engine.js';
import { ZCodeSessionResolver } from './core/zcode-session-resolver.js';
import { ZCodeAdvisor } from './core/zcode-advisor.js';

const execAsync = promisify(exec);
const __dirname = path.dirname(fileURLToPath(import.meta.url));

const PORT = process.env.PORT || 38921;

// 读取 UI 页面
const UI_HTML = fs.readFileSync(path.join(__dirname, 'ui/index.html'), 'utf8');

const server = http.createServer(async (req, res) => {
  const parsedUrl = new URL(req.url, `http://localhost:${PORT}`);
  const pathname = parsedUrl.pathname;

  // 跨域支持
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  // 静态页面服务
  if (pathname === '/' || pathname === '/index.html') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(UI_HTML);
    return;
  }

  // 静态图标资源
  if (pathname === '/assets/logo.png') {
    const logoPath = path.join(__dirname, 'ui/assets/logo.png');
    if (fs.existsSync(logoPath)) {
      res.writeHead(200, { 'Content-Type': 'image/png', 'Cache-Control': 'public, max-age=86400' });
      res.end(fs.readFileSync(logoPath));
      return;
    }
  }

  // API 1: 提示词增强 (/api/enhance)
  if (pathname === '/api/enhance' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', async () => {
      try {
        const { text, projectDir, model, endpoint, apiKey } = JSON.parse(body || '{}');
        if (!text || !text.trim()) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Text cannot be empty' }));
          return;
        }

        // 调用 PromptEngine 增强提示词
        const result = await PromptEngine.enhance(text, {
          projectDir,
          model,
          endpoint,
          apiKey,
        });

        // 生成针对当前润色结果与工程环境的 ZCode 能力建议
        const zcodeAdvice = ZCodeAdvisor.recommendCapabilities(result.text, result.profile);

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          ...result,
          zcodeAdvice
        }));
      } catch (err) {
        console.error('[Enhance Error]:', err);
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: err.message || 'Enhancement failed' }));
      }
    });
    return;
  }

  // API 1.5: 独立获取 ZCode 能力调度建议 (/api/zcode-advisor)
  if (pathname === '/api/zcode-advisor' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        const { text, projectDir } = JSON.parse(body || '{}');
        let profile = null;
        if (projectDir) {
          profile = ProjectProfiler.analyze(projectDir);
        }
        const advice = ZCodeAdvisor.recommendCapabilities(text || '', profile);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(advice));
      } catch (err) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: err.message }));
      }
    });
    return;
  }

  // API 2: 获取项目工程画像 (/api/project-profile)
  if (pathname === '/api/project-profile' && req.method === 'GET') {
    const dir = parsedUrl.searchParams.get('dir');
    if (!dir) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Missing dir parameter' }));
      return;
    }

    const profile = ProjectProfiler.analyze(dir);
    if (!profile) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Directory not found or invalid' }));
      return;
    }

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(profile));
    return;
  }

  // API 3: 弹出 macOS 原生文件夹选择器对话框 (/api/select-project-dir)
  if (pathname === '/api/select-project-dir' && req.method === 'POST') {
    try {
      // 通过 AppleScript 唤起原生选文件夹对话框
      const script = `osascript -e 'POSIX path of (choose folder with prompt "请选择要关联的代码工程根目录：")'`;
      const { stdout } = await execAsync(script);
      const selectedDir = stdout.trim().replace(/\/$/, '');
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ dir: selectedDir }));
    } catch (e) {
      // 用户取消选择
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ dir: null, cancelled: true }));
    }
    return;
  }

  // API 3.1: 获取最近 ZCode 会话列表 (/api/recent-zcode-sessions)
  if (pathname === '/api/recent-zcode-sessions' && req.method === 'GET') {
    const list = ZCodeSessionResolver.getRecentSessions(8);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ sessions: list }));
    return;
  }

  // API 3.2: 根据会话 ID 解析关联工程与画像 (/api/resolve-zcode-session)
  if (pathname === '/api/resolve-zcode-session' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        const { sessionId } = JSON.parse(body || '{}');
        const sessionInfo = ZCodeSessionResolver.resolveSession(sessionId);
        if (!sessionInfo) {
          res.writeHead(404, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: `未找到会话 ID 为 ${sessionId} 的记录` }));
          return;
        }

        // 进一步提取该工程目录的画像
        const profile = ProjectProfiler.analyze(sessionInfo.directory);

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          session: sessionInfo,
          profile,
        }));
      } catch (err) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: err.message }));
      }
    });
    return;
  }

  // API 4: 将润色后的文本自动贴回前台活动窗口 (/api/paste-to-active-app)
  if (pathname === '/api/paste-to-active-app' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', async () => {
      try {
        const { text } = JSON.parse(body || '{}');
        if (text) {
          // 写入系统剪贴板并模拟 Cmd+V
          const tempFile = path.join(__dirname, '../.clip_tmp.txt');
          fs.writeFileSync(tempFile, text);
          const script = `
            cat "${tempFile}" | pbcopy
            osascript -e '
              tell application "System Events"
                key code 9 using command down -- Cmd + V
              end tell
            '
          `;
          await execAsync(script);
          try { fs.unlinkSync(tempFile); } catch (e) {}
        }
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true }));
      } catch (err) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: err.message }));
      }
    });
    return;
  }

  res.writeHead(404);
  res.end('Not Found');
});

server.listen(PORT, () => {
  console.log(`\n======================================================`);
  console.log(`✨ PromptEnhancer 服务已就绪: http://localhost:${PORT}`);
  console.log(`🚀 支持项目工程画像感知 + WorkBuddy 原生提示词润色体系`);
  console.log(`======================================================\n`);
});
