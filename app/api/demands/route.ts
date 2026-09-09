/**
 * 需要の宣言：本人が確認した Needs を封緘して返す（lib/blob.ts）。
 * サーバは何も保存しない。受け手の端末が封緘を持ち、BLE で譲る側へ渡す。
 */

import { seal } from '@/lib/blob';
import { DemandRequestSchema } from '@/lib/contracts';
import { BadRequest, badRequest, readJson } from '@/lib/http';

export async function POST(request: Request) {
  try {
    const input = await readJson(request, DemandRequestSchema);
    return Response.json({ blob: seal(input.needs, input.stopsToAlight) });
  } catch (e) {
    if (e instanceof BadRequest) return badRequest(e);
    throw e;
  }
}
