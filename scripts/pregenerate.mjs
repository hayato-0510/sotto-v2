/**
 * 混雑度対比（FR-13・審査用画面）のデータを事前生成して、Flutter の assets に書き出す。
 *
 *   npm run pregenerate
 *   npm run pregenerate -- "ギプスで座ると逆に痛い"
 *
 * ライブ生成にしない理由：撮影中にレート制限へ当たるリスクを負う価値がない（設計書 §3.1）。
 * 同じ Needs で混雑度だけを変え、動作が変わることを並べて見せる。
 *
 * 無料枠は 15 RPM。呼び出しの間に4秒あける（scripts/try.mjs と同じ配慮）。
 */

import { readFileSync, writeFileSync } from 'node:fs';

try {
  for (const line of readFileSync('.env.local', 'utf8').split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*?)\s*$/);
    if (!m) continue;
    const value = m[2].replace(/^(['"])(.*)\1$/, '$2');
    if (!process.env[m[1]]) process.env[m[1]] = value;
  }
} catch {
  // .env.local が無い場合は環境変数に任せる
}

const condition = process.argv[2] || '貧血気味で立っているとふらつく';
const out = 'mobile/assets/comparison.json';

const { currentProvider, extractNeeds, generateHandoff } = await import('../lib/llm.ts');
const { fallbackHandoff } = await import('../lib/fallback.ts');
const { containsSpeech } = await import('../lib/speech.ts');

if (currentProvider() === 'none') {
  console.error('GOOGLE_API_KEY が未設定です。生成せずに終了します（assets の定型文はそのまま）');
  process.exit(1);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

console.log(`状態: ${condition}`);
const needs = await extractNeeds(condition);
console.log(`確認: ${needs.summary}（${needs.confidence}）`);

const columns = [
  { crowding: '空いている', label: '空いている' },
  { crowding: '混雑', label: '混んでいる' },
  { crowding: '超満員', label: 'ぎゅうぎゅう' },
];

const items = [];
for (const c of columns) {
  await sleep(4000);
  let handoff;
  try {
    handoff = await generateHandoff(needs, { crowding: c.crowding, stopsToAlight: 3, hour: 8 });
  } catch (e) {
    console.warn(`${c.crowding}: 生成に失敗。定型文にします（${e.message}）`);
    handoff = fallbackHandoff(c.crowding);
  }
  if (containsSpeech(handoff.action)) {
    // lib/llm.ts で再生成済みのはずだが、最後の砦としてここでも見る
    console.warn(`${c.crowding}: 発話が混入。定型文にします`);
    handoff = fallbackHandoff(c.crowding);
  }
  console.log(`${c.label.padEnd(6)} ${handoff.action}${handoff.isFallback ? '（定型）' : ''}`);
  items.push({ crowding: c.crowding, label: c.label, handoff });
}

writeFileSync(
  out,
  JSON.stringify(
    {
      generatedAt: new Date().toISOString(),
      condition,
      note: 'scripts/pregenerate.mjs で生成した。手で編集しない',
      items,
    },
    null,
    2,
  ) + '\n',
);
console.log(`書き出し: ${out}`);
