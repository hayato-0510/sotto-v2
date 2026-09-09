/** Route Handler 共通の小物。JSON の読み取りと、検証失敗の 400 応答 */

import type { z } from 'zod';

export class BadRequest extends Error {}

export async function readJson<T extends z.ZodType>(
  request: Request,
  schema: T,
): Promise<z.infer<T>> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    throw new BadRequest('本文が JSON ではありません');
  }
  const parsed = schema.safeParse(body);
  if (!parsed.success) {
    const detail = parsed.error.issues.map((i) => `${i.path.join('.')} ${i.message}`).join('; ');
    throw new BadRequest(`入力が不正です: ${detail}`);
  }
  return parsed.data;
}

/**
 * 生成失敗のログ用。原因（cause）の status とメッセージまで辿る。
 * 鍵の値はエラーメッセージに含まれない（SDK は鍵を伏せる）が、念のため URL のクエリは落とす。
 */
export function describeError(error: unknown): string {
  const parts: string[] = [];
  let e: unknown = error;
  for (let depth = 0; e && depth < 4; depth++) {
    const err = e as { message?: string; status?: number; cause?: unknown; name?: string };
    const status = err.status !== undefined ? ` [${err.status}]` : '';
    parts.push(`${err.name ?? 'Error'}${status}: ${(err.message ?? String(e)).replace(/\?key=[^&\s]+/g, '?key=***')}`);
    e = err.cause;
  }
  return parts.join(' ← ');
}

export function badRequest(error: unknown): Response {
  const message = error instanceof Error ? error.message : '不正なリクエスト';
  return Response.json({ error: message }, { status: 400 });
}
