import { currentProvider } from '@/lib/llm';

/** 疎通確認。鍵の値は返さない。provider が 'none' なら AI は動かずフォールバック文になる */
export function GET() {
  return Response.json({
    ok: true,
    provider: currentProvider(),
    blobKeyConfigured: Boolean(process.env.SOTTO_BLOB_KEY),
  });
}
