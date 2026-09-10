/**
 * ステップ2：封緘された需要 ＋ 混雑度 → Handoff（設計書 §5、FR-04・FR-07・FR-11）。
 * 譲る側が［ 譲る ］を押す都度呼ばれる。
 *
 * 発話チェックは lib/llm.ts の generateHandoff が行い、1回の再生成でも通らなければ
 * SpeechLeakError（GenerationError の一種）を投げる。ここで固定文に差し替える（FR-12）。
 * 封緘が解けない場合は 400。譲る側の端末に Needs を返すことは一切ない。
 */

import { BlobError, unseal } from '@/lib/blob';
import { generateHandoff, GenerationError } from '@/lib/llm';
import { fallbackHandoff } from '@/lib/fallback';
import { HandoffRequestSchema } from '@/lib/contracts';
import { BadRequest, badRequest, describeError, readJson } from '@/lib/http';
import type { Needs } from '@/lib/types';

export async function POST(request: Request) {
  let input;
  let demand;
  try {
    input = await readJson(request, HandoffRequestSchema);
    demand = unseal(input.blob);
  } catch (e) {
    if (e instanceof BadRequest || e instanceof BlobError) return badRequest(e);
    throw e;
  }

  // summary は封緘に含めていない。プロンプトの入力として空文字で埋める
  const needs: Needs = { ...demand.needs, summary: '' };
  const situation = {
    crowding: input.crowding,
    stopsToAlight: demand.stopsToAlight,
    hour: new Date().getHours(),
  };

  try {
    const handoff = await generateHandoff(needs, situation);
    return Response.json(handoff);
  } catch (e) {
    if (e instanceof GenerationError) {
      console.warn('[api/handoff] 生成に失敗。固定文で応答します:', describeError(e));
      return Response.json(fallbackHandoff(input.crowding));
    }
    throw e;
  }
}
