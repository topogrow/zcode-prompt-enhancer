/**
 * ZCode 能力引用建议器 (ZCode Capability Advisor)
 * 解析润色后的提示词意图，结合关联项目工程画像，推导出最契合的 ZCode 底层能力与调用指令。
 */
export class ZCodeAdvisor {
  /**
   * 能力特征映射规则库
   */
  static get CAPABILITY_RULES() {
    return [
      {
        id: 'plan_mode',
        name: 'Plan 模式',
        badge: '📋 Plan 模式',
        keywords: [
          '重构', '架构', '重新设计', '改造', 'refactor', 'architecture',
          '模块拆解', '迁移', '系统设计', '方案对比', '多方案', '底层支持',
          '解耦', '微服务', '全面优化'
        ],
        reason: '任务涉及跨模块架构改造或多方案选型，建议先出设计方案经审批后再动手',
        directive: '请先进入 Plan 模式进行架构梳理与多方案对比，输出完整计划经我审批后再开始编写代码。'
      },
      {
        id: 'explore_agent',
        name: 'Explore 只读探索',
        badge: '🤖 Explore 智能体',
        keywords: [
          '调研', '全库', '全局搜索', '排查', '梳理依赖', '查一下', '代码库检索',
          '查找所有', '代码审计', '扫描', '探索', 'codebase search', 'find usages'
        ],
        reason: '任务涉及较大范围的代码库检索与依赖摸排，使用只读智能体可避免污染主上下文',
        directive: '请先派发 Explore 子智能体深入检索并梳理相关代码依赖与上下文，整理结论后再推进。'
      },
      {
        id: 'workflow',
        name: '动态工作流 (Workflow)',
        badge: '🔄 动态工作流',
        keywords: [
          '工作流', 'workflow', '批量', '流水线', 'pipeline', '分阶段执行',
          '步骤依赖', '并发', 'fan-out', '批处理', '定时调度'
        ],
        reason: '任务具备多步骤流程依赖或并发批处理特征，适合通过动态工作流编排运行',
        directive: '请使用 workflow 工作流编排本次任务，通过代码级控制流分步调度多智能体完成。'
      },
      {
        id: 'tdd',
        name: 'TDD 测试驱动开发',
        badge: '🧪 TDD 规范',
        keywords: [
          '单元测试', '单测', '测试先行', 'tdd', 'test-driven', '边界测试',
          '测试用例', '覆盖率', '回归测试', '断言', 'assert', '单元覆盖'
        ],
        reason: '任务涉及核心算法或核心业务逻辑，建议遵循测试驱动开发以保障稳健性',
        directive: '请遵循 TDD 规范：先针对关键边界情况编写失败的单元测试用例，再逐步实现逻辑直至全部通过。'
      },
      {
        id: 'visualize',
        name: 'Gen UI 可视化看板',
        badge: '🎨 Gen UI 交互视图',
        keywords: [
          '可视化', '原型', '界面预览', 'dashboard', '看板', '交互视图',
          '图表', '走查', '交互原型', '数据大屏', 'html视图'
        ],
        reason: '任务涉及 UI 呈现或数据可视化，适合使用 Gen UI 实时输出可交互原型',
        directive: '请使用 visualize 技能生成可交互的 HTML 视图或原型看板，直观呈现设计成果。'
      },
      {
        id: 'e2e_automation',
        name: '端到端自动化测试',
        badge: '🌐 自动化测试',
        keywords: [
          '端到端', 'e2e', '模拟器', '自动化测试', '页面走查', '截图验证',
          'playwright', '模拟点击', '小程序测试', 'ios模拟', '安卓测试'
        ],
        reason: '任务包含界面交互走查与集成测试，建议调度自动化工具执行并验证截帧',
        directive: '请调用对应的自动化测试工具执行完整的链路交互，并截屏验证关键页面的渲染状态。'
      }
    ];
  }

  /**
   * 分析提示词与项目上下文，生成 ZCode 能力建议
   * @param {string} text 润色后的提示词
   * @param {object|null} profile 关联工程画像
   * @returns {ZCodeAdviceResult}
   */
  static recommendCapabilities(text, profile = null) {
    if (!text || typeof text !== 'string' || !text.trim()) {
      return {
        matched: false,
        badges: [],
        primaryMode: '常规执行',
        reason: '输入内容较简短，建议直接执行',
        directive: '',
        appendText: ''
      };
    }

    const lower = text.toLowerCase();
    const matchedRules = [];

    // 1. 匹配规则
    for (const rule of this.CAPABILITY_RULES) {
      const isMatched = rule.keywords.some(kw => lower.includes(kw.toLowerCase()));
      if (isMatched) {
        matchedRules.push(rule);
      }
    }

    // 2. 结合工程画像微调建议
    if (profile) {
      const frameworkStr = (profile.frameworks || []).join(' ').toLowerCase();
      // 如果工程包含前端框架且提示词提到组件或界面，但尚未匹配到 visualize，可适度推荐
      if ((frameworkStr.includes('react') || frameworkStr.includes('vue')) &&
          (lower.includes('组件') || lower.includes('页面') || lower.includes('ui')) &&
          !matchedRules.some(r => r.id === 'visualize' || r.id === 'plan_mode')) {
        const visualizeRule = this.CAPABILITY_RULES.find(r => r.id === 'visualize');
        if (visualizeRule) matchedRules.push(visualizeRule);
      }
    }

    // 3. 如果没有命中任何特定重度能力，给出轻量标准建议（如优先使用 Read/搜索而非盲写）
    if (matchedRules.length === 0) {
      // 检查字数：如果超过 150 字的较长提示词，建议先梳理
      if (text.length > 150) {
        return {
          matched: true,
          badges: ['📋 Plan 模式'],
          primaryMode: '建议启用 Plan 模式',
          reason: '需求描述较详尽，建议先由模型梳理明确步骤',
          directive: '请先梳理具体的实施步骤与影响范围，确认无误后再执行代码修改。',
          appendText: '\n\n---\n[ZCODE 调度建议]\n请先梳理具体的实施步骤与影响范围，确认无误后再执行代码修改。'
        };
      }

      return {
        matched: false,
        badges: ['⚡ 直接执行'],
        primaryMode: '常规执行',
        reason: '常规明确的开发任务，可由主智能体直接执行',
        directive: '',
        appendText: ''
      };
    }

    // 4. 组装选中的能力
    const badges = matchedRules.map(r => r.badge);
    const reasons = matchedRules.map(r => r.reason).join('；');
    const directives = matchedRules.map(r => r.directive).join('\n');

    // 生成追加到提示词末尾的标准文本块
    const appendText = `\n\n---\n[ZCODE 调度建议]\n${directives}`;

    return {
      matched: true,
      badges,
      primaryMode: matchedRules[0].name,
      reason: reasons,
      directive: directives,
      appendText
    };
  }
}
