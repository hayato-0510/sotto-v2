/**
 * ステップ1：状態テキスト → Needs（設計書 §5、FR-11）。乗車前に1回だけ呼ばれる。
 * 生成に失敗したら固定文で応答し、isFallback を立てる（FR-12）。
 */

import { extractNeeds, GenerationError } from '@/lib/llm';
import { fallbackNeeds } from '@/lib/fallback';
import { NeedsRequestSchema } from '@/lib/contracts';
import { BadRequest, badRequest, describeError, readJson } from '@/lib/http';

export async function POST(request: Request) {
  let input;
  try {
    input = await readJson(request, NeedsRequestSchema);
  } catch (e) {
    if (e instanceof BadRequest) return badRequest(e);
    throw e;
  }

  try {
    const needs = await extractNeeds(input.text);
    return Response.json(needs);
  } catch (e) {
    if (e instanceof GenerationError) {
      console.warn('[api/needs] 生成に失敗。固定文で応答します:', describeError(e));
      return Response.json(fallbackNeeds());
    }
    throw e;
  }
}
