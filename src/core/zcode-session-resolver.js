import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

/**
 * ZCode 会话与工作区解析器 (ZCode Session Resolver)
 * 直接读取 ~/.zcode/cli/db/db.sqlite，实现会话 ID 与项目工作区的秒级映射
 */
export class ZCodeSessionResolver {
  static getDbPath() {
    return path.join(os.homedir(), '.zcode/cli/db/db.sqlite');
  }

  /**
   * 检查 ZCode 本地数据库是否存在
   * @returns {boolean}
   */
  static isAvailable() {
    return fs.existsSync(this.getDbPath());
  }

  /**
   * 通过会话 ID 解析关联的工程目录和信息
   * @param {string} sessionId 用户输入的会话 ID（支持带 sess_ 前缀或仅 UUID）
   * @returns {{ id: string, title: string, directory: string, timeUpdated: number } | null}
   */
  static resolveSession(sessionId) {
    if (!sessionId || typeof sessionId !== 'string' || !this.isAvailable()) {
      return null;
    }

    const cleanId = sessionId.trim().replace(/^sess_/, '');
    // 严格安全白名单校验：仅允许英文字母、数字、下划线及中划线 (最大128位)，彻底防御 SQL 与 Shell 注入
    if (!/^[a-zA-Z0-9_\-]{1,128}$/.test(cleanId)) {
      console.warn('[ZCodeSessionResolver Security]: 拦截到非法的会话 ID 输入:', cleanId);
      return null;
    }

    const dbPath = this.getDbPath();

    // 同时支持完全匹配与前缀模糊匹配
    const sql = `SELECT id, title, directory, time_updated FROM session WHERE id = 'sess_${cleanId}' OR id = '${cleanId}' OR id LIKE '%${cleanId}%' ORDER BY time_updated DESC LIMIT 1;`;

    try {
      // 采用 execFileSync 直接调用二进制，脱离 /bin/sh 解释器环境
      const output = execFileSync('sqlite3', [dbPath, sql], { encoding: 'utf8', timeout: 3000 }).trim();
      if (!output) return null;

      const [id, title, directory, timeUpdated] = output.split('|');
      return {
        id,
        title,
        directory,
        timeUpdated: Number(timeUpdated) || Date.now(),
      };
    } catch (e) {
      console.error('[ZCodeSessionResolver Error]:', e.message);
      return null;
    }
  }

  /**
   * 获取最近活跃的 ZCode 会话列表（方便在 UI 下拉框中直接点选）
   * @param {number} [limit=10]
   * @returns {Array<{ id: string, title: string, directory: string, timeUpdated: number }>}
   */
  static getRecentSessions(limit = 10) {
    if (!this.isAvailable()) return [];

    // 强化数值范围收敛防范
    const safeLimit = Math.max(1, Math.min(50, parseInt(limit, 10) || 10));
    const dbPath = this.getDbPath();
    const sql = `SELECT id, title, directory, time_updated FROM session WHERE task_type = 'interactive' AND directory != '' ORDER BY time_updated DESC LIMIT ${safeLimit};`;

    try {
      const output = execFileSync('sqlite3', [dbPath, sql], { encoding: 'utf8', timeout: 3000 }).trim();
      if (!output) return [];

      return output.split('\n').filter(Boolean).map(line => {
        const [id, title, directory, timeUpdated] = line.split('|');
        return {
          id,
          title,
          directory,
          timeUpdated: Number(timeUpdated) || Date.now(),
        };
      });
    } catch (e) {
      console.error('[ZCodeSessionResolver Recent Error]:', e.message);
      return [];
    }
  }
}
