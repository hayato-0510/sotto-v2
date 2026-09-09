/**
 * アプリ（Flutter）と AI サーバの間の契約。zod で入力を検証する。
 *
 * Dart 側（mobile/lib/api/contracts.dart）に同じ形がある。**変更時は両方直す**（設計書 §4）。
 *
 * 一覧：
 *   POST /api/needs    { text }                  → Needs
 *   POST /api/demands  { needs, stopsToAlight? } → { blob }        （封緘。lib/blob.ts）
 *   POST /api/handoff  { blob, crowding }        → Handoff
 *   GET  /api/health                             → { ok, provider } （鍵の値は返さない）
 */

import { z } from 'zod';
import { NeedsSchema } from './llm';

/** FR-03：自由記述は最大100字。選択肢の文を先頭に足すので余裕を持って200字まで受ける */
export const NeedsRequestSchema = z.object({
  text: z.string().trim().min(1).max(200),
});

export const StopsToAlightSchema = z.union([z.literal(1), z.literal(3), z.literal(8)]);

export const DemandRequestSchema = z.object({
  needs: NeedsSchema.extend({ isFallback: z.boolean().optional() }),
  /** UI では聞かない（画面を増やさない）。既定は3駅 */
  stopsToAlight: StopsToAlightSchema.default(3),
});

export const CrowdingSchema = z.enum(['空いている', '普通', '混雑', '超満員']);

export const HandoffRequestSchema = z.object({
  blob: z.string().min(1).max(2000),
  crowding: CrowdingSchema,
});
