/**
 * AI サーバの4本のエンドポイントを順に叩く疎通確認。デプロイ後の確認にも使う。
 *
 *   npm run smoke                                  # http://localhost:3000
 *   npm run smoke -- https://<デプロイ先>.vercel.app
 *
 * curl だと Windows の端末で日本語が化けて 400 になる（実際に踏んだ）ので、Node で送る。
 * 鍵の値は一切表示しない。/api/health は provider 名と鍵の有無だけを返す。
 */

const base = (process.argv[2] || 'http://localhost:3000').replace(/\/$/, '');

async function post(path, body) {
  const res = await fetch(`${base}${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  const json = await res.json();
  return { status: res.status, json };
}

const health = await (await fetch(`${base}/api/health`)).json();
console.log(`health   : provider=${health.provider} blobKey=${health.blobKeyConfigured ? 'set' : 'UNSET'}`);
if (health.provider === 'none') console.log('           → GOOGLE_API_KEY が未設定。以降は定型文になる');

const bad = await post('/api/needs', {});
console.log(`needs 400: ${bad.status === 400 ? 'ok' : 'NG'}`);

let t = Date.now();
const needs = await post('/api/needs', { text: '貧血気味で立っているとふらつく' });
console.log(`needs    : ${needs.status} ${Date.now() - t}ms ${needs.json.summary}${needs.json.isFallback ? '（定型）' : ''}`);

const demand = await post('/api/demands', { needs: needs.json });
const blob = demand.json.blob;
console.log(`demands  : ${demand.status} blob=${blob ? blob.length + '文字' : 'なし'}`);

for (const crowding of ['空いている', '超満員']) {
  t = Date.now();
  const h = await post('/api/handoff', { blob, crowding });
  console.log(`handoff  : ${h.status} ${Date.now() - t}ms [${crowding}] ${h.json.action}${h.json.isFallback ? '（定型）' : ''}`);
}

const tampered = await post('/api/handoff', { blob: blob.slice(0, -3) + 'xyz', crowding: '混雑' });
console.log(`tampered : ${tampered.status === 400 ? 'ok（400）' : 'NG ' + tampered.status}`);
