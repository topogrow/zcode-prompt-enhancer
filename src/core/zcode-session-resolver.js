import { execSync } from 'node:child_process';
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
    if (!sessionId || !sessionId.trim() || !this.isAvailable()) {
      return null;
    }

    const cleanId = sessionId.trim().replace(/^sess_/, '');
    const dbPath = this.getDbPath();

    // 同时支持完全匹配与前缀模糊匹配
    const sql = `
      SELECT id, title, directory, time_updated
      FROM session
      WHERE id = 'sess_${cleanId}' OR id = '${cleanId}' OR id LIKE '%${cleanId}%'
      ORDER BY time_updated DESC
      LIMIT 1;
    `.trim().replace(/\n/g, ' ');

    try {
      const output = execSync(`sqlite3 "${dbPath}" "${sql}"`, { encoding: 'utf8' }).trim();
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

    const dbPath = this.getDbPath();
    const sql = `
      SELECT id, title, directory, time_updated
      FROM session
      WHERE task_type = 'interactive' AND directory != ''
      ORDER BY time_updated DESC
      LIMIT ${limit};
    `.trim().replace(/\n/g, ' ');

    try {
      const output = execSync(`sqlite3 "${dbPath}" "${sql}"`, { encoding: 'utf8' }).trim();
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
