import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { exec, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { ProjectProfiler } from './core/project-profiler.js';
import { PromptEngine } from './core/prompt-engine.js';
import { ZCodeSessionResolver } from './core/zcode-session-resolver.js';
import { ZCodeAdvisor } from './core/zcode-advisor.js';

const execAsync = promisify(exec);
const __dirname = path.dirname(fileURLToPath(import.meta.url));

const PORT = process.env.PORT || 38921;
const HOST = '127.0.0.1'; // 显式绑定本地环回接口，拒绝局域网未授权访问

// 读取 UI 页面
const UI_HTML = fs.readFileSync(path.join(__dirname, 'ui/index.html'), 'utf8');

// P0 安全加固: 允许的跨域来源白名单 (严禁对敏感接口开放通配符 '*')
const ALLOWED_ORIGINS = new Set([
  `http://localhost:${PORT}`,
  `http://127.0.0.1:${PORT}`,
]);

function handleCors(req, res) {
  const origin = req.headers.origin;
  // 原生应用 WKWebView 或直接访问时可能无 origin，放行
  if (!origin) {
    return true;
  }

  if (ALLOWED_ORIGINS.has(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    res.setHeader('Vary', 'Origin');
    return true;
  }

  // 阻断来自外部网页的非受信跨域调用 (防御 CSRF 与本地代码执行)
  res.writeHead(403, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'CORS forbidden: untrusted origin' }));
  return false;
}

// P1 健壮性加固: 安全的 JSON 流式解析与 1MB 载荷上限防 DoS
const MAX_PAYLOAD_BYTES = 1024 * 1024; // 1 MB

function parseJsonBody(req, limit = MAX_PAYLOAD_BYTES) {
  return new Promise((resolve, reject) => {
    let body = '';
    let bytesReceived = 0;

    req.on('data', chunk => {
      bytesReceived += chunk.length;
      if (bytesReceived > limit) {
        req.destroy();
        const err = new Error('Payload Too Large (Exceeded 1MB limit)');
        err.statusCode = 413;
        reject(err);
        return;
      }
      body += chunk;
    });

    req.on('end', () => {
      try {
        resolve(JSON.parse(body || '{}'));
      } catch (e) {
        const err = new Error('Malformed JSON payload');
        err.statusCode = 400;
        reject(err);
      }
    });

    req.on('error', reject);
  });
}

// P1 进程守护: 父进程存活心跳监测 (防止宿主意外崩溃造成孤儿进程占死端口)
function startParentHeartbeat() {
  // 优先取显式指定的父进程 PID
  const parentArgIdx = process.argv.indexOf('--parent-pid');
  const targetPid = parentArgIdx !== -1 && process.argv[parentArgIdx + 1]
    ? parseInt(process.argv[parentArgIdx + 1], 10)
    : process.ppid;

  if (!targetPid || targetPid <= 1) return;

  const timer = setInterval(() => {
    try {
      process.kill(targetPid, 0);
    } catch (e) {
      // 只有在明确报 ESRCH (No such process) 时才判定父进程死亡
      if (e.code === 'ESRCH') {
        console.log(`[Server] 宿主进程 (PID: ${targetPid}) 已终止，Node 守护服务自退出释放端口。`);
        process.exit(0);
      }
    }
  }, 3000);
  timer.unref();
}

startParentHeartbeat();

const server = http.createServer(async (req, res) => {
  const parsedUrl = new URL(req.url, `http://${HOST}:${PORT}`);
  const pathname = parsedUrl.pathname;

  // 执行安全 CORS 拦截与校验
  if (!handleCors(req, res)) {
    return;
  }

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
    try {
      const { text, projectDir, model, endpoint, apiKey } = await parseJsonBody(req);
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
      const status = err.statusCode || 500;
      console.error('[Enhance Error]:', err.message);
      res.writeHead(status, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: err.message || 'Enhancement failed' }));
    }
    return;
  }

  // API 1.5: 独立获取能力调度建议 (/api/zcode-advisor)
  if (pathname === '/api/zcode-advisor' && req.method === 'POST') {
    try {
      const { text, projectDir } = await parseJsonBody(req);
      let profile = null;
      if (projectDir) {
        profile = ProjectProfiler.analyze(projectDir);
      }
      const advice = ZCodeAdvisor.recommendCapabilities(text || '', profile);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(advice));
    } catch (err) {
      const status = err.statusCode || 500;
      res.writeHead(status, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: err.message }));
    }
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
      const script = `osascript -e 'POSIX path of (choose folder with prompt "请选择要关联的代码工程根目录：")'`;
      const { stdout } = await execAsync(script);
      const selectedDir = stdout.trim().replace(/\/$/, '');
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ dir: selectedDir }));
    } catch (e) {
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
    try {
      const { sessionId } = await parseJsonBody(req);
      const sessionInfo = ZCodeSessionResolver.resolveSession(sessionId);
      if (!sessionInfo) {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: `未找到有效的会话记录` }));
        return;
      }

      const profile = ProjectProfiler.analyze(sessionInfo.directory);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        session: sessionInfo,
        profile,
      }));
    } catch (err) {
      const status = err.statusCode || 500;
      res.writeHead(status, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: err.message }));
    }
    return;
  }

  // API 4: 将润色后的文本自动贴回前台活动窗口 (/api/paste-to-active-app)
  if (pathname === '/api/paste-to-active-app' && req.method === 'POST') {
    try {
      const { text } = await parseJsonBody(req);
      if (text) {
        // 使用内存管道直接写入系统剪贴板，彻底避免文件写入竞争与路径注入
        await new Promise((resolve, reject) => {
          const pbcopy = spawn('pbcopy');
          pbcopy.stdin.write(text);
          pbcopy.stdin.end();
          pbcopy.on('close', code => {
            if (code === 0) resolve();
            else reject(new Error(`pbcopy exited with code ${code}`));
          });
          pbcopy.on('error', reject);
        });

        // 发送按键指令模拟粘贴
        await execAsync(`osascript -e 'tell application "System Events" to key code 9 using command down'`);
      }
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: true }));
    } catch (err) {
      const status = err.statusCode || 500;
      res.writeHead(status, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: err.message }));
    }
    return;
  }

  res.writeHead(404);
  res.end('Not Found');
});

server.listen(PORT, HOST, () => {
  console.log(`\n======================================================`);
  console.log(`✨ PromptEnhancer 服务已就绪: http://${HOST}:${PORT}`);
  console.log(`🔒 安全机制: CORS 白名单防护 + 1MB 载荷上限 + PID 心跳看门狗`);
  console.log(`======================================================\n`);
});
