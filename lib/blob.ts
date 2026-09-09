/**
 * 需要データの封緘（sealed blob）。設計書 §7.2 の空欄を埋める設計判断（開発計画 §1.2-A）。
 *
 * 受け手の Needs はサーバがここで暗号化し、受け手の端末が封緘したまま保持する。
 * 譲る側の端末は BLE（GATT）で封緘されたまま受け取り、サーバに渡して Handoff を得る。
 * 譲る側の端末は Needs を一度も復号できない（AGENTS.md §3「障害情報を送らない」）。
 *
 * これでサーバは状態を持たない。Vercel のサーバレスで in-memory ストアが
 * インスタンス間で分散する問題（前身の lib/sessions.ts が踏んだ穴）を根本から避ける。
 *
 * 封緘の中身は Needs（summary を除く）と発生時刻。summary は本人確認用の文であり、
 * 端末の外に出す必要がない（lib/types.ts）。
 */

import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { z } from 'zod';
import { NeedsSchema } from './llm';
import type { Needs, StopsToAlight } from './types';

/** 封緘の中身。summary を持たない */
export const SealedDemandSchema = z.object({
  v: z.literal(1),
  needs: NeedsSchema.omit({ summary: true }),
  stopsToAlight: z.union([z.literal(1), z.literal(3), z.literal(8)]),
  /** 発生時刻（epoch ms）。待ち時間の長い順の割り当て（設計書 §2.6）に使う */
  createdAt: z.number().int(),
});
export type SealedDemand = z.infer<typeof SealedDemandSchema>;

export class BlobError extends Error {}

/**
 * 開発用の固定鍵。SOTTO_BLOB_KEY が未設定のときだけ使う。
 * 公開環境でこれが使われると、譲る側の端末を持つ人が Needs を復号できてしまう。
 * 疾患名は元から含まれない（型に無い）が、それでも公開時は必ず環境変数を設定すること。
 */
const DEV_KEY_HEX = '5f2b7d3c9a1e4b6d8c0f2a4e6b8d1c3e5a7c9e1b3d5f7a9c1e3b5d7f9a1c3e5b';
let warned = false;

function key(): Buffer {
  const hex = process.env.SOTTO_BLOB_KEY;
  if (hex && /^[0-9a-fA-F]{64}$/.test(hex)) return Buffer.from(hex, 'hex');
  if (!warned) {
    warned = true;
    console.warn(
      '[sotto] SOTTO_BLOB_KEY が未設定です。開発用の固定鍵で封緘します。公開環境では必ず設定してください',
    );
  }
  return Buffer.from(DEV_KEY_HEX, 'hex');
}

/** Needs を封緘する。戻り値は base64url 文字列（GATT で数百バイトに収まる） */
export function seal(needs: Needs, stopsToAlight: StopsToAlight, now = Date.now()): string {
  // summary と isFallback は端末の外に出さない。持ち出す項目を明示的に列挙する
  const payload: SealedDemand = {
    v: 1,
    needs: {
      posture: needs.posture,
      needsSupport: needs.needsSupport,
      timeSensitive: needs.timeSensitive,
      luggage: needs.luggage,
      avoid: needs.avoid,
      confidence: needs.confidence,
    },
    stopsToAlight,
    createdAt: now,
  };
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key(), iv);
  const body = Buffer.concat([cipher.update(JSON.stringify(payload), 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, tag, body]).toString('base64url');
}

/** 封緘を解く。改竄・鍵違い・形式違いはすべて BlobError */
export function unseal(blob: string): SealedDemand {
  const raw = Buffer.from(blob, 'base64url');
  if (raw.length < 12 + 16 + 1) throw new BlobError('封緘データが短すぎます');
  const iv = raw.subarray(0, 12);
  const tag = raw.subarray(12, 28);
  const body = raw.subarray(28);
  let text: string;
  try {
    const decipher = createDecipheriv('aes-256-gcm', key(), iv);
    decipher.setAuthTag(tag);
    text = Buffer.concat([decipher.update(body), decipher.final()]).toString('utf8');
  } catch {
    throw new BlobError('封緘データを復号できません（鍵違いか改竄）');
  }
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    throw new BlobError('封緘データの中身が JSON ではありません');
  }
  const parsed = SealedDemandSchema.safeParse(json);
  if (!parsed.success) throw new BlobError('封緘データの中身がスキーマに一致しません');
  return parsed.data;
}
