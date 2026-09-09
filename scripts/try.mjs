/**
 * プロンプトを UI 抜きで試すためのスクリプト。
 *
 *   npm run try -- "貧血気味で立っているとふらつく" 超満員 3
 *   npm run try -- "貧血気味で立っているとふらつく" 空いている 3
 *
 * 同じ状態テキストで混雑度だけ変えて、action が変わることを確認するのが主な用途。
 * これが変わらないなら、企画の中核（設計書 H-2）が成立していない。
 *
 * lib/llm.ts をそのまま呼ぶ（プロンプト・スキーマの二重管理をしない）。
 * ステップ1（配慮抽出）も通してから、その配慮でステップ2を呼ぶ。
 *
 * 注意：実行するたびに API 利用料が発生する。回し過ぎないこと。
 * GOOGLE_API_KEY 使用時は無料枠 15 RPM の制限があるため、
 * 連続で回す場合は4秒以上間隔をあけること（設計書 §7.6・§13.3）。
 */

import { readFileSync } from 'node:fs';

// .env.local を読む（dotenv を入れずに済ませる）
//
// 引用符の除去を忘れないこと。Next.js の .env ローダは値を囲む引用符を剥がすため、
// ここで剥がしそこねると「アプリでは通るのに npm run try だけ 400 になる」という
// 再現しにくい食い違いが起きる（実際に踏んだ）。
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

const [text, crowding = '普通', stopsArg = '3'] = process.argv.slice(2);

if (!text) {
  console.error('使い方: npm run try -- "<状態テキスト>" [混雑度] [降車まで駅数]');
  console.error('  混雑度: 空いている | 普通 | 混雑 | 超満員');
  process.exit(1);
}

const stopsToAlight = Number(stopsArg);
if (![1, 3, 8].includes(stopsToAlight)) {
  console.error('降車まで駅数は 1 / 3 / 8 のいずれかにしてください。');
  process.exit(1);
}

const { currentProvider, extractNeeds, generateHandoff } = await import('../lib/llm.ts');
const { containsSpeech, findSpeechTerms } = await import('../lib/speech.ts');

const provider = currentProvider();
if (provider === 'none') {
  console.error(
    'GOOGLE_API_KEY も ANTHROPIC_API_KEY も未設定です。.env.local.example を参考に .env.local を作ってください。',
  );
  process.exit(1);
}

console.log(`使用プロバイダ: ${provider}`);

const started = Date.now();
const needs = await extractNeeds(text);
const needsMs = Date.now() - started;

const handoffStarted = Date.now();
const handoff = await generateHandoff(needs, {
  crowding,
  stopsToAlight,
  hour: new Date().getHours(),
});
const handoffMs = Date.now() - handoffStarted;

console.log(`\n状態     : ${text}`);
console.log(`混雑度   : ${crowding} / 降車まで ${stopsToAlight}駅`);
console.log('─'.repeat(56));
console.log(`確認     : ${needs.summary}（confidence: ${needs.confidence}）`);
console.log('─'.repeat(56));
console.log(`要請     : ${handoff.request}`);
console.log(`動作     : ${handoff.action}`);
console.log(`理由     : ${handoff.reason}`);
console.log(`所要     : 約${handoff.seconds}秒 / 負荷 ${handoff.physicalLoad}`);
console.log('─'.repeat(56));

const speechFound = containsSpeech(handoff.action);
console.log(
  `発話混入 : ${speechFound ? `❌ あり（${findSpeechTerms(handoff.action).join('・')}）` : '✅ なし'}`,
);
console.log(`所要時間 : ステップ1 ${needsMs}ms / ステップ2 ${handoffMs}ms`);
