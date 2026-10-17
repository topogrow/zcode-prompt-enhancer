import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PromptEngine } from '../core/prompt-engine.js';
import { ProjectProfiler } from '../core/project-profiler.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/**
 * 自动检测当前前台活跃编辑器的当前项目目录 (VS Code / Cursor / Terminal)
 */
function detectActiveProjectDir() {
  try {
    // 1. 尝试从最近绑定的本地配置文件读取
    const configPath = path.join(__dirname, '../../.last_project_dir');
    if (fs.existsSync(configPath)) {
      const savedDir = fs.readFileSync(configPath, 'utf8').trim();
      if (savedDir && fs.existsSync(savedDir)) return savedDir;
    }

    // 2. 尝试探测前台窗口的标题 (VS Code / Cursor 通常在标题中显示项目名或文件路径)
    const script = `
      tell application "System Events"
        set frontApp to name of first application process whose frontmost is true
        set windowTitle to ""
        try
          set windowTitle to name of front window of application process frontApp
        end try
        return frontApp & ":::" & windowTitle
      end tell
    `;
    const res = execSync(`osascript -e '${script}'`, { encoding: 'utf8' }).trim();
    const [appName, winTitle] = res.split(':::');
    // 如果窗口标题里有已知开发目录路径
    if (winTitle && winTitle.includes('/')) {
      const match = winTitle.match(/\/([^\s\-\—]+)/);
      if (match && fs.existsSync(match[0])) {
        return match[0];
      }
    }
  } catch (e) {}

  return null;
}

/**
 * 原位润色并替换主流程
 */
async function runInPlaceEnhance() {
  console.log('🪄 [PromptEnhancer] 正在获取前台选中文本...');

  // 1. 备份现有剪贴板
  let oldClip = '';
  try {
    oldClip = execSync('pbpaste', { encoding: 'utf8' });
  } catch (e) {}

  // 2. 发送 Cmd+C 获取选中的文本
  try {
    execSync(`osascript -e '
      tell application "System Events"
        keystroke "c" using command down
      end tell
    '`);
  } catch (e) {}

  // 短暂等待剪贴板同步
  await new Promise(r => setTimeout(r, 120));

  let selectedText = '';
  try {
    selectedText = execSync('pbpaste', { encoding: 'utf8' });
  } catch (e) {}

  if (!selectedText || !selectedText.trim()) {
    execSync(`osascript -e 'display notification "请先选中要润色的提示词文字" with title "🪄 PromptEnhancer"'`);
    return;
  }

  // 3. 关联当前项目目录
  const projectDir = detectActiveProjectDir();
  console.log(`📁 关联项目工程: ${projectDir || '通用模式 (未绑定)'}`);

  // 4. 调用 PromptEngine 增强提示词
  try {
    const result = await PromptEngine.enhance(selectedText, {
      projectDir,
    });

    const enhancedText = result.text;
    console.log(`✨ 增强完成 (${result.durationMs}ms):\n${enhancedText}`);

    // 5. 写入剪贴板并模拟 Cmd+V 原位粘贴替换
    const tempFile = path.join(__dirname, '../../.temp_clip.txt');
    fs.writeFileSync(tempFile, enhancedText, 'utf8');
    execSync(`cat "${tempFile}" | pbcopy`);
    try { fs.unlinkSync(tempFile); } catch (e) {}

    execSync(`osascript -e '
      tell application "System Events"
        keystroke "v" using command down
      end tell
    '`);

    execSync(`osascript -e 'display notification "提示词已完成增强替换！按 Cmd+Z 可撤销" with title "🪄 PromptEnhancer"'`);
  } catch (err) {
    console.error('Enhance failed:', err);
    // 恢复原剪贴板
    try {
      const tempFile = path.join(__dirname, '../../.temp_clip.txt');
      fs.writeFileSync(tempFile, oldClip, 'utf8');
      execSync(`cat "${tempFile}" | pbcopy`);
      try { fs.unlinkSync(tempFile); } catch (e) {}
    } catch (e) {}

    execSync(`osascript -e 'display notification "润色失败: ${err.message.replace(/"/g, '\\"')}" with title "🪄 PromptEnhancer"'`);
  }
}

runInPlaceEnhance();
