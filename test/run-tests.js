import assert from 'node:assert';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ProjectProfiler } from '../src/core/project-profiler.js';
import { PromptEngine, WORKBUDDY_SYSTEM_PROMPT, WORKBUDDY_USER_TEMPLATE } from '../src/core/prompt-engine.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.join(__dirname, '..');

console.log('🧪 开始运行 PromptEnhancer 核心测试套件...\n');

// ----------------------------------------------------
// Test 1: ProjectProfiler 性能与解析正确性
// ----------------------------------------------------
console.log('▶️ [Test 1] 验证 ProjectProfiler 毫秒级性能与依赖解析');
const t0 = performance.now();
const profile = ProjectProfiler.analyze(PROJECT_ROOT);
const t1 = performance.now();
const elapsed = t1 - t0;

console.log(`   耗时: ${elapsed.toFixed(2)} ms (目标 < 20ms)`);
assert.ok(elapsed < 50, 'ProjectProfiler 耗时超出预期阈值');
assert.strictEqual(profile.projectName, 'prompt-enhancer');
assert.strictEqual(profile.language, 'JavaScript');
assert.ok(Array.isArray(profile.directories), 'directories 应该为数组');
assert.ok(profile.directories.length > 0, '应该能够扫描出顶层目录');
console.log('   ✅ ProjectProfiler 测试通过！\n');

// ----------------------------------------------------
// Test 2: PromptEngine 规则体系对齐 WorkBuddy
// ----------------------------------------------------
console.log('▶️ [Test 2] 验证 PromptEngine 对 WorkBuddy 规则的 100% 对齐');
assert.ok(WORKBUDDY_SYSTEM_PROMPT.includes('Do NOT answer questions'), '缺少严禁作答规则');
assert.ok(WORKBUDDY_SYSTEM_PROMPT.includes('Do NOT suggest specific technologies'), '缺少严禁无端推荐技术栈规则');
assert.ok(WORKBUDDY_SYSTEM_PROMPT.includes('Do NOT explain HOW to do things, focus on WHAT'), '缺少只定目标不定解法规则');
assert.ok(WORKBUDDY_SYSTEM_PROMPT.includes('maximum length should be around 800 characters'), '缺少 800 字符限制');
assert.ok(WORKBUDDY_USER_TEMPLATE.includes('CRITICAL PRIORITY - LANGUAGE CONSISTENCY:'), '缺少语言一致性最高优先级');
assert.ok(WORKBUDDY_USER_TEMPLATE.includes('If the user mixes languages, keep a natural matching mix'), '缺少中英混排原貌保持规则');
console.log('   ✅ WorkBuddy 黄金约束对齐测试通过！\n');

// ----------------------------------------------------
// Test 3: 后处理清洗逻辑 (stripWrappingQuotes)
// ----------------------------------------------------
console.log('▶️ [Test 3] 验证后处理清洗函数 (防引号与格式污染)');
const cases = [
  { input: '"这是一段用英文引号包裹的提示词"', expected: '这是一段用英文引号包裹的提示词' },
  { input: '“这是中文双引号包裹的提示词”', expected: '这是中文双引号包裹的提示词' },
  { input: '```markdown\n实现一个富文本编辑器组件\n```', expected: '实现一个富文本编辑器组件' },
  { input: 'Enhanced prompt: 这是一个带前缀的提示词', expected: '这是一个带前缀的提示词' },
  { input: '润色后的提示词：设计一个订单详情页', expected: '设计一个订单详情页' },
];

for (const c of cases) {
  const actual = PromptEngine.stripWrappingQuotes(c.input);
  assert.strictEqual(actual, c.expected, `清洗失败: 输入 "${c.input}" -> 预期 "${c.expected}", 实际 "${actual}"`);
}
console.log('   ✅ 后处理清洗管道测试通过！\n');

// ----------------------------------------------------
// Test 4: 双通道模式测试 (无项目关联 vs 关联项目画像)
// ----------------------------------------------------
console.log('▶️ [Test 4] 验证双通道模式 (通用模式 vs 项目画像自适应模式)');
const inputPrompt = '写个统一的全局错误处理中间件';

// 4.1 未关联项目目录时
const payloadWithoutProject = PromptEngine.buildPromptPayload(inputPrompt, null);
assert.ok(!payloadWithoutProject.userPrompt.includes('[PROJECT ENVIRONMENT]'), '无项目模式不应包含工程环境');
assert.strictEqual(payloadWithoutProject.projectProfile, null);

// 4.2 关联项目目录时
const payloadWithProject = PromptEngine.buildPromptPayload(inputPrompt, PROJECT_ROOT);
assert.ok(payloadWithProject.userPrompt.includes('[PROJECT ENVIRONMENT]'), '关联模式应注入工程环境');
assert.ok(payloadWithProject.userPrompt.includes('prompt-enhancer'), '工程环境应包含项目名');
assert.ok(payloadWithProject.userPrompt.includes('SPECIAL INSTRUCTION FOR PROJECT CONTEXT'), '应包含工程自适应指令');
console.log('   ✅ 双通道构建模式验证通过！\n');

// ----------------------------------------------------
// Test 5: ZCode 会话 ID 联动与工作区解析
// ----------------------------------------------------
console.log('▶️ [Test 5] 验证 ZCode 会话 ID 解析与工作区目录联动');
import { ZCodeSessionResolver } from '../src/core/zcode-session-resolver.js';

assert.ok(ZCodeSessionResolver.isAvailable(), 'ZCode 本地数据库应该存在');
const recentSessions = ZCodeSessionResolver.getRecentSessions(5);
assert.ok(Array.isArray(recentSessions), '应该返回会话数组');
assert.ok(recentSessions.length > 0, '应该能够查出本地真实会话');
console.log(`   成功拉取到 ${recentSessions.length} 个本地活跃 ZCode 会话:`);
recentSessions.forEach(s => console.log(`   - [${s.id.slice(0, 16)}...] ${s.title} -> ${s.directory}`));

// 使用第一个真实会话 ID 进行匹配解析测试
const firstSess = recentSessions[0];
const resolved = ZCodeSessionResolver.resolveSession(firstSess.id);
assert.ok(resolved, '应该成功通过会话 ID 解析到会话详情');
assert.strictEqual(resolved.id, firstSess.id);
assert.strictEqual(resolved.directory, firstSess.directory);
console.log(`   ✅ 成功通过会话 ID 锁定工程工作区: ${resolved.directory}`);
console.log('   ✅ ZCode 会话联动引擎测试通过！\n');

// ----------------------------------------------------
// Test 6: ZCode 能力引用建议推理与生成规范
// ----------------------------------------------------
console.log('▶️ [Test 6] 验证 ZCode 能力引用建议 (ZCodeAdvisor) 意图匹配与生成');
import { ZCodeAdvisor } from '../src/core/zcode-advisor.js';

// 场景 1: 复杂架构重构 -> 推荐 Plan 模式
const refactorPrompt = '重构系统的鉴权模块架构，实现无感刷新与多端会话互斥';
const advice1 = ZCodeAdvisor.recommendCapabilities(refactorPrompt);
assert.ok(advice1.matched, '应该成功命中能力');
assert.ok(advice1.badges.some(b => b.includes('Plan')), '重构任务应该命中 Plan 模式');
assert.ok(advice1.appendText.includes('[ZCODE 调度建议]'), '追加文本应符合规范');
console.log('   - 场景 1 (架构重构): 命中', advice1.badges);

// 场景 2: 全库调研与依赖排查 -> 推荐 Explore 智能体
const explorePrompt = '全库调研现有各模块中涉及支付回调的接口，梳理所有代码依赖';
const advice2 = ZCodeAdvisor.recommendCapabilities(explorePrompt);
assert.ok(advice2.matched, '应该成功命中能力');
assert.ok(advice2.badges.some(b => b.includes('Explore')), '全库检索任务应该命中 Explore 智能体');
console.log('   - 场景 2 (全库调研): 命中', advice2.badges);

// 场景 3: 单元测试先行 -> 推荐 TDD
const tddPrompt = '编写针对订单退款状态机的单元测试，要求覆盖各类极端并发边界情况';
const advice3 = ZCodeAdvisor.recommendCapabilities(tddPrompt);
assert.ok(advice3.matched, '应该成功命中能力');
assert.ok(advice3.badges.some(b => b.includes('TDD')), '单元测试任务应该命中 TDD 规范');
console.log('   - 场景 3 (单测覆盖): 命中', advice3.badges);

// 场景 4: 结合前端工程画像 -> 推荐 Gen UI 可视化
const mockProfile = { frameworks: ['React 19', 'Tailwind CSS'] };
const uiPrompt = '设计一个财务对账的数据大屏与看板原型组件';
const advice4 = ZCodeAdvisor.recommendCapabilities(uiPrompt, mockProfile);
assert.ok(advice4.matched, '应该成功命中能力');
assert.ok(advice4.badges.some(b => b.includes('Gen UI') || b.includes('可视化')), '大屏看板应推荐 Gen UI');
console.log('   - 场景 4 (前端画像+看板): 命中', advice4.badges);

// 验证追加到提示词末尾的组装测试
const fullCombined = refactorPrompt + advice1.appendText;
assert.ok(fullCombined.startsWith(refactorPrompt), '提示词正文应保持在最前');
assert.ok(fullCombined.endsWith(advice1.directive), 'ZCode 调度指令应在末尾');
console.log('   ✅ 追加到提示词末尾逻辑验证正确');
console.log('   ✅ ZCode 能力建议器测试通过！\n');

// ----------------------------------------------------
// Test 7: P0 安全加固与注入攻击拦截防御验证
// ----------------------------------------------------
console.log('▶️ [Test 7] 验证 P0 安全加固：SQL / Shell 注入拦截与字符白名单');
const maliciousInputs = [
  "'; DROP TABLE session; --",
  "$(whoami)",
  "`id`",
  "sess_123' OR '1'='1",
  "../../../etc/passwd",
  "sess_test; rm -rf /"
];

for (const input of maliciousInputs) {
  const result = ZCodeSessionResolver.resolveSession(input);
  assert.strictEqual(result, null, `恶意注入应当被拦截为 null: ${input}`);
}
console.log('   ✅ 成功拦截所有潜在恶意 SQL / 命令注入请求 (6/6)');
console.log('   ✅ P0 安全防御测试通过！\n');

console.log('🎉 所有自动化测试全部通过 (7/7)！');
