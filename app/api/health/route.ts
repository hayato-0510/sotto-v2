import { createHash } from 'node:crypto';
import { currentProvider } from '@/lib/llm';

/** 鍵の値を出さずに「どの鍵が載っているか」を突き合わせるための指紋（SHA-256 の先頭8桁）と長さ */
function fingerprint(value: string | undefined) {
  if (!value) return null;
  return { length: value.length, sha256: createHash('sha256').update(value).digest('hex').slice(0, 8) };
}

/** 疎通確認。鍵の値は返さない。provider が 'none' なら AI は動かずフォールバック文になる */
export function GET() {
  return Response.json({
    ok: true,
    provider: currentProvider(),
    blobKeyConfigured: Boolean(process.env.SOTTO_BLOB_KEY),
    googleKey: fingerprint(process.env.GOOGLE_API_KEY),
    blobKey: fingerprint(process.env.SOTTO_BLOB_KEY),
  });
}
