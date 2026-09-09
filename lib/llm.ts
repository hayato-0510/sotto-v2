/**
 * LLMプロバイダ境界（設計書 §7.6・§7.7）。
 *
 * 第一候補は Google AI Studio（Gemini）。理由は速度ではなく鍵が無料で今日手に入るから。
 * `ANTHROPIC_API_KEY` を取得した場合の代替経路も残す。
 *
 * ステップ1・ステップ2の入出力（`Needs` / `Handoff`）はこのファイルの外へ
 * プロバイダ依存を漏らさない。鍵の状況が変わっても呼び出し側は作り直しにならない。
 *
 * APIキーが両方とも未設定の場合は `GenerationError` を投げる。
 * 呼び出し側（Route Handler）はこれを捕まえて `lib/fallback.ts` の固定文で応答する
 * （AGENTS.md「存在しなければ未設定として扱い、フォールバックで動かす」）。
 */

import { z } from 'zod';
import type { Handoff, Needs, Situation } from './types';
import { containsSpeech } from './speech';
import { HANDOFF_SYSTEM_PROMPT, NEEDS_SYSTEM_PROMPT } from './prompts';

// ── 生成失敗を表すエラー ──────────────────────────

/** 生成に失敗した（鍵未設定・APIエラー・タイムアウト）ことを表す。呼び出し側でフォールバックに切り替える。 */
export class GenerationError extends Error {}

/** 発話チェック（§7.5）に、1回の再生成でも通らなかったことを表す。GenerationError の一種として扱う。 */
export class SpeechLeakError extends GenerationError {}

// ── プロバイダ選択 ────────────────────────────────

export type LlmProvider = 'google' | 'anthropic' | 'none';

/**
 * 現在使えるプロバイダを返す。
 * 設計書 §7.6 の優先順位どおり、Google AI Studio を先に見る。
 */
export function currentProvider(): LlmProvider {
  if (process.env.GOOGLE_API_KEY) return 'google';
  if (process.env.ANTHROPIC_API_KEY) return 'anthropic';
  return 'none';
}

// ── スキーマ（両プロバイダ共通。lib/types.ts の形と手動で一致させること） ──
//
// Route Handler 側の入力検証（安全な再構造化出力の強制）にも使うため export する。

export const NeedsSchema = z.object({
  posture: z.enum(['座位が必要', '立位でも可（支えが要る）', '状況による']),
  needsSupport: z.boolean(),
  timeSensitive: z.boolean(),
  luggage: z.enum(['多い', '少ない', '不明']),
  avoid: z.array(z.string()),
  summary: z.string(),
  confidence: z.enum(['high', 'medium', 'low']),
});

export const HandoffSchema = z.object({
  request: z.string(),
  action: z.string(),
  reason: z.string(),
  seconds: z.number().int(),
  physicalLoad: z.enum(['低', '中']),
});

// ── Gemini 実装 ───────────────────────────────────

/**
 * 実測（2026-09-09、無料枠）で選定した。`GOOGLE_GEMINI_MODEL` で上書きできる。
 *
 * | モデル | 実測 | 判定 |
 * | :--- | :--- | :--- |
 * | gemini-3.5-flash-lite | 1〜2秒 | **採用**。NFR-01の目標5秒を大きく下回る |
 * | gemini-3.1-flash-lite | 2〜3秒 | 次点 |
 * | gemini-3-flash-preview | 504/503が頻発 | 無料枠では不安定で使えない |
 * | gemini-3.5-flash | 約30秒 | 遅すぎる |
 * | gemini-3.6-flash | 約99秒（"2+2"でも） | 論外 |
 * | gemini-2.5-flash / -lite | — | 新規利用不可（404）。設計書執筆時から状況が変わった |
 *
 * モデルの提供状況は動く。404や503が出たら、まず
 * `GET https://generativelanguage.googleapis.com/v1beta/models` で一覧を取り直すこと。
 */
const GEMINI_MODEL = process.env.GOOGLE_GEMINI_MODEL || 'gemini-3.5-flash-lite';

/**
 * Anthropic の `effort` に対応する Gemini 側のつまみ。
 *
 * 既定のまま（thinking 高め）だと無料枠で60秒タイムアウトが頻発し、
 * NFR-01（10秒以内・目標5秒）をまったく満たせない。実測のうえでここを絞る。
 */
type ThinkingLevel = 'minimal' | 'low' | 'medium' | 'high';

/** タイムアウト。60秒待つとデモが死ぬ。待たずにフォールバックへ倒す方が体験がよい。 */
const GEMINI_TIMEOUT_MS = 20_000;

/** Google 側の一時的な過負荷か（503 UNAVAILABLE / 504 DEADLINE_EXCEEDED）。 */
function isTransientGeminiError(cause: unknown): boolean {
  const status = (cause as { status?: number } | undefined)?.status;
  return status === 503 || status === 504;
}

async function geminiGenerateJson<T extends z.ZodType>(
  systemInstruction: string,
  userContent: unknown,
  schema: T,
  thinkingLevel: ThinkingLevel,
): Promise<z.infer<T>> {
  const apiKey = process.env.GOOGLE_API_KEY;
  if (!apiKey) throw new GenerationError('GOOGLE_API_KEY が未設定です');

  // 列挙も動的importから取る。SDKをモジュール読み込み時に引き込まないため。
  const { GoogleGenAI, ThinkingLevel: Level } = await import('@google/genai');
  const client = new GoogleGenAI({ apiKey, httpOptions: { timeout: GEMINI_TIMEOUT_MS } });

  const level = {
    minimal: Level.MINIMAL,
    low: Level.LOW,
    medium: Level.MEDIUM,
    high: Level.HIGH,
  }[thinkingLevel];

  const request = () =>
    client.models.generateContent({
      model: GEMINI_MODEL,
      contents: JSON.stringify(userContent),
      config: {
        systemInstruction,
        responseMimeType: 'application/json',
        // プロンプトでJSONを懇願しない。responseJsonSchema で強制する（設計書 §7.6）
        responseJsonSchema: z.toJSONSchema(schema),
        thinkingConfig: { thinkingLevel: level },
      },
    });

  let response;
  try {
    response = await request();
  } catch (cause) {
    // Google 側の一時的な過負荷（503/504）は無料枠で珍しくない。実測でも頻発した。
    // ここでフォールバックに落とすと「例文です」がデモの最中に出て体験を損なうため、
    // 一時的なものだけ1回だけ即リトライする。鍵の誤りや404はリトライしても無駄なので素通しする
    if (!isTransientGeminiError(cause)) {
      throw new GenerationError('Gemini API 呼び出しに失敗しました', { cause });
    }
    try {
      response = await request();
    } catch (retryCause) {
      throw new GenerationError('Gemini API 呼び出しに失敗しました（リトライ後も失敗）', {
        cause: retryCause,
      });
    }
  }

  const text = response.text;
  if (!text) throw new GenerationError('Gemini から空の応答が返りました');

  let parsedJson: unknown;
  try {
    parsedJson = JSON.parse(text);
  } catch (cause) {
    throw new GenerationError('Gemini の応答がJSONとして解釈できません', { cause });
  }

  const result = schema.safeParse(parsedJson);
  if (!result.success) {
    throw new GenerationError('Gemini の応答がスキーマに一致しません', { cause: result.error });
  }
  return result.data;
}

// ── Anthropic 実装（代替経路） ────────────────────

async function anthropicGenerateJson<T extends z.ZodType>(
  systemInstruction: string,
  userContent: unknown,
  schema: T,
  effort: 'medium' | 'high',
): Promise<z.infer<T>> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new GenerationError('ANTHROPIC_API_KEY が未設定です');

  const { default: Anthropic } = await import('@anthropic-ai/sdk');
  const { zodOutputFormat } = await import('@anthropic-ai/sdk/helpers/zod');
  const client = new Anthropic({ apiKey, timeout: 60_000 });

  let res;
  try {
    res = await client.messages.parse({
      model: 'claude-opus-5',
      max_tokens: 16000,
      output_config: { format: zodOutputFormat(schema), effort },
      system: systemInstruction,
      messages: [{ role: 'user', content: JSON.stringify(userContent) }],
    });
  } catch (cause) {
    // 具体的なものから連鎖で捕まえる（設計書 §7.7）。ここでは呼び出し側に GenerationError として一律通知する
    if (cause instanceof Anthropic.RateLimitError) {
      throw new GenerationError('Anthropic のレート制限に達しました', { cause });
    }
    if (cause instanceof Anthropic.APIConnectionError) {
      throw new GenerationError('Anthropic への接続に失敗しました', { cause });
    }
    if (cause instanceof Anthropic.APIError) {
      throw new GenerationError('Anthropic APIがエラーを返しました', { cause });
    }
    throw new GenerationError('Anthropic API 呼び出しに失敗しました', { cause });
  }

  if (!res.parsed_output) throw new GenerationError('構造化出力の取得に失敗しました');
  return res.parsed_output;
}

// ── 公開API：ステップ1（抽出） ────────────────────

/** 状態テキストから配慮（Needs）を抽出する。乗車前に1回のみ呼ばれる想定（NFR-02）。 */
export async function extractNeeds(text: string): Promise<Needs> {
  const provider = currentProvider();
  const userContent = { 状態: text };

  if (provider === 'google') {
    // 実測：thinkingLevel 'low' だと明確な入力でも confidence が不当に低くなる
    // （例：「貧血気味で立っているとふらつく」ですら曖昧な summary しか作れなかった）。
    // 乗車前・1回だけなので、medium にして品質を優先する
    return geminiGenerateJson(NEEDS_SYSTEM_PROMPT, userContent, NeedsSchema, 'medium');
  }
  if (provider === 'anthropic') {
    return anthropicGenerateJson(NEEDS_SYSTEM_PROMPT, userContent, NeedsSchema, 'medium');
  }
  throw new GenerationError('LLMプロバイダが未設定です（GOOGLE_API_KEY / ANTHROPIC_API_KEY）');
}

// ── 公開API：ステップ2（生成） ────────────────────

async function generateHandoffOnce(needs: Needs, situation: Situation): Promise<Handoff> {
  const provider = currentProvider();
  const userContent = {
    配慮: needs,
    車内状況: {
      混雑度: situation.crowding,
      降車まで: `${situation.stopsToAlight}駅`,
    },
  };

  if (provider === 'google') {
    // 生成品質がそのまま評価対象（§7.3）。ステップ1より高く保つが、
    // 既定（high 相当）だと無料枠でタイムアウトが頻発するため medium で妥協する。
    return geminiGenerateJson(HANDOFF_SYSTEM_PROMPT, userContent, HandoffSchema, 'medium');
  }
  if (provider === 'anthropic') {
    return anthropicGenerateJson(HANDOFF_SYSTEM_PROMPT, userContent, HandoffSchema, 'high');
  }
  throw new GenerationError('LLMプロバイダが未設定です（GOOGLE_API_KEY / ANTHROPIC_API_KEY）');
}

/**
 * 配慮＋車内状況から要請と動作（Handoff）を生成する。
 *
 * 設計書 §7.5：action に発話系の語が含まれたら1回だけ再生成し、
 * それでも含むなら `SpeechLeakError` を投げる。呼び出し側（Route Handler）は
 * これを捕まえてフォールバック文（`lib/fallback.ts`）に切り替えること。
 * ここをLLMの出力任せにしないのが、このプロダクトの存在理由そのものである。
 */
export async function generateHandoff(needs: Needs, situation: Situation): Promise<Handoff> {
  const first = await generateHandoffOnce(needs, situation);
  if (!containsSpeech(first.action)) return first;

  const retried = await generateHandoffOnce(needs, situation);
  if (!containsSpeech(retried.action)) return retried;

  throw new SpeechLeakError('再生成しても発話系の語が action に含まれています');
}
