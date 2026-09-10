import { currentProvider } from '@/lib/llm';

/**
 * 疎通確認。鍵の値も、長さやハッシュのような照合に使える断片も返さない。
 * provider が 'none' なら AI は動かずフォールバック文になる。
 * blobKeyConfigured が false のとき、本番では /api/demands と /api/handoff が失敗する（lib/blob.ts）。
 */
export function GET() {
  return Response.json({
    ok: true,
    provider: currentProvider(),
    blobKeyConfigured: /^[0-9a-fA-F]{64}$/.test(process.env.SOTTO_BLOB_KEY ?? ''),
  });
}
