import { ProjectProfiler } from './project-profiler.js';

/**
 * WorkBuddy 原生系统提示词 (System Prompt: Rn)
 * 严格保留所有负向约束：严禁自行作答、严禁无端假设技术栈、聚焦于做什麽而非怎么做、800字收敛
 */
export const WORKBUDDY_SYSTEM_PROMPT = `You are a Prompt Engineering Expert specializing in improving user prompts for a development code assistant. When given a prompt, analyze and enhance it to create a more effective version while maintaining its core purpose. The requests are being made to an AI assistant that specializes in writing code.

TASK: When given a prompt, analyze and enhance it to create a more effective version while maintaining its core purpose. The requests are being made to an AI assistant that specializes in writing code.

ANALYSIS PROCESS:
Evaluate the original prompt:
- Identify the main objective
- Note any ambiguities or gaps
- Assess the clarity of instructions
- Check for missing context
Apply these prompt engineering principles:
- Write clear, specific instructions
- Include necessary context
- Set explicit parameters and constraints
- Structure the output format
- Add relevant examples
- Match tone and complexity to the use case
- Remove redundant information
Create the enhanced version:
- Maintain the original goal
- Incorporate identified improvements
- Ensure clarity and completeness
- Be realistic in the features to add
- Do NOT request guides/how-tos unless the user asks
- Do NOT ask for code snippets
- Do NOT suggest specific technologies unless mentioned in the user's prompt (or explicitly specified in PROJECT ENVIRONMENT)
- Do NOT explain HOW to do things, focus on WHAT
- Do NOT answer questions - expand/rewrite them to be more detailed

IMPORTANT CONSTRAINTS:
1. Language matching is the highest priority - You MUST strictly respond in the exact same language as the user's input. If the user writes in Chinese, respond in Chinese; if the user writes in English, respond in English; if the user uses another language, respond in that same language. Do not mix languages unless the user's input itself mixes languages.
2. Keep the enhanced prompt concise - maximum length should be around 800 characters
FORMAT: Provide only the enhanced prompt with no additional commentary.`;

/**
 * WorkBuddy 原生用户输入包装模板 (User Prompt: zn)
 * 强化语言一致性约束与中英混排保真
 */
export const WORKBUDDY_USER_TEMPLATE = `You are a prompt enhancement assistant. Improve the user prompt while preserving its intent and language.

USER INPUT:
{input}

TASK:
Rewrite the user input into a clearer, more specific prompt for the target AI assistant.

CRITICAL PRIORITY - LANGUAGE CONSISTENCY:
1. You MUST detect the language of the user input above and write the enhanced prompt in that same language.
2. If the user writes in Chinese, the enhanced prompt MUST be entirely in Chinese.
3. If the user writes in English, the enhanced prompt MUST be entirely in English.
4. If the user writes in any other language, the enhanced prompt MUST use that exact same language.
5. If the user mixes languages, keep a natural matching mix. Do not translate the user's intent into a single language.
6. These language rules are behavior instructions only; never include language analysis or language labels in the output.

ENHANCEMENT REQUIREMENTS:
1. Return only the enhanced prompt text; do not add explanations, prefaces, markdown fences, labels, or analysis.
2. Do not include language labels or meta notes such as "User input is in Chinese" or "Response must be in Chinese".
3. Preserve the user's original intent, topic, constraints, and target output type. Do not answer the request.
4. Always make a substantive enhancement when possible: clarify the task, scope, constraints, and expected output.
5. If the original prompt is already clear, lightly polish it instead of returning it unchanged.
6. Keep the enhanced prompt complete and concise. Do not end with an unfinished list, dangling conjunction, or trailing colon.
7. Do not add unrelated requirements, unsupported facts, or unnecessary sections.

{projectContext}
`;

/**
 * 提示词增强引擎类
 */
export class PromptEngine {
  /**
   * 剥离外层包裹的引号与多余空白（完全对齐 WorkBuddy 的 stripWrappingQuotes 函数）
   * @param {string} text
   * @returns {string}
   */
  static stripWrappingQuotes(text) {
    if (!text || typeof text !== 'string') return '';
    let cleaned = text.trim();
    // 剔除中英文外层引号
    cleaned = cleaned.replace(/^["'“”‘’]|["'“”‘’]$/g, '').trim();
    // 剔除模型可能自作聪明带上的 Markdown 代码块标记（如 ```markdown ... ``` 或 ```text ... ```）
    cleaned = cleaned.replace(/^```[a-zA-Z]*\n?([\s\S]*?)\n?```$/g, '$1').trim();
    // 剔除常见的自言自语前言（如 "Enhanced prompt:", "润色后的提示词：", "优化结果："）
    cleaned = cleaned.replace(/^(Enhanced prompt|(润色|优化|增强|改写)(后|结果|后的提示词|的提示词)?)[:：]\s*/i, '').trim();
    return cleaned;
  }

  /**
   * 构建发送给大模型的完整 Payload
   * @param {string} rawInput 原始用户输入
   * @param {string|null} projectDir 可选的目标项目目录路径
   * @returns {{ systemPrompt: string, userPrompt: string, projectProfile: any }}
   */
  static buildPromptPayload(rawInput, projectDir = null) {
    const trimmedInput = (rawInput || '').trim();
    if (!trimmedInput) {
      throw new Error('Input text cannot be empty');
    }

    let projectContextStr = '';
    let profile = null;

    if (projectDir) {
      profile = ProjectProfiler.analyze(projectDir);
      if (profile) {
        projectContextStr = ProjectProfiler.formatForPrompt(profile);
      }
    }

    const userPrompt = WORKBUDDY_USER_TEMPLATE
      .replace('{input}', trimmedInput)
      .replace('{projectContext}', projectContextStr ? `\n${projectContextStr}\n` : '');

    return {
      systemPrompt: WORKBUDDY_SYSTEM_PROMPT,
      userPrompt,
      projectProfile: profile,
    };
  }

  /**
   * 调用大模型进行增强（支持本地 Ollama、OpenAI / DeepSeek 等兼容接口）
   * @param {string} rawInput
   * @param {object} options
   * @param {string} [options.projectDir] 关联的项目目录路径
   * @param {string} [options.endpoint] API 端点（默认 http://localhost:11434 或 https://api.deepseek.com）
   * @param {string} [options.apiKey] API Key（本地 Ollama 可为空）
   * @param {string} [options.model] 模型名（如 'qwen2.5-coder:7b', 'deepseek-chat' 等）
   * @param {AbortSignal} [options.signal] 取消信号
   * @returns {Promise<{ success: boolean, text: string, original: string, profile: any, durationMs: number }>}
   */
  static async enhance(rawInput, options = {}) {
    const startTime = Date.now();
    const {
      projectDir = null,
      endpoint = process.env.PROMPT_ENHANCER_API_ENDPOINT || 'http://localhost:11434',
      apiKey = process.env.PROMPT_ENHANCER_API_KEY || '',
      model = process.env.PROMPT_ENHANCER_MODEL || 'qwen2.5-coder:7b',
      signal = null,
    } = options;

    const { systemPrompt, userPrompt, projectProfile } = this.buildPromptPayload(rawInput, projectDir);

    let enhancedText = '';

    // 判断是 Ollama 原生接口还是兼容 OpenAI 的 /v1/chat/completions 接口
    const isOllamaNative = endpoint.includes(':11434') && !endpoint.includes('/v1');
    const url = isOllamaNative
      ? `${endpoint.replace(/\/$/, '')}/api/generate`
      : `${endpoint.replace(/\/$/, '')}/v1/chat/completions`;

    const headers = { 'Content-Type': 'application/json' };
    if (apiKey) {
      headers['Authorization'] = `Bearer ${apiKey}`;
    }

    const requestBody = isOllamaNative
      ? {
          model,
          prompt: userPrompt,
          system: systemPrompt,
          stream: false,
          options: {
            temperature: 0.3,
            num_predict: 500,
          },
        }
      : {
          model,
          messages: [
            { role: 'system', content: systemPrompt },
            { role: 'user', content: userPrompt },
          ],
          temperature: 0.3,
          max_tokens: 500,
          stream: false,
        };

    const response = await fetch(url, {
      method: 'POST',
      headers,
      body: JSON.stringify(requestBody),
      signal,
    });

    if (!response.ok) {
      const errText = await response.text();
      throw new Error(`LLM Request failed with status ${response.status}: ${errText}`);
    }

    const resJson = await response.json();
    if (isOllamaNative) {
      enhancedText = resJson.response || '';
    } else {
      enhancedText = resJson.choices?.[0]?.message?.content || '';
    }

    const cleanedText = this.stripWrappingQuotes(enhancedText);
    const durationMs = Date.now() - startTime;

    return {
      success: true,
      text: cleanedText,
      original: rawInput,
      profile: projectProfile,
      durationMs,
    };
  }
}
