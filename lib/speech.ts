/**
 * 生成された「動作」に発話が含まれていないかを検査する。
 *
 * 設計書 §7.5。このプロダクトの存在理由が「声をかけないこと」である以上、
 * ここを LLM の出力任せにしない。プロンプトで禁止したうえで、
 * サーバ側で必ずこの関数を通す。該当したら1回だけ再生成し、
 * それでも含むならフォールバック文を使う。
 */

/**
 * 発話を示す語のパターン。
 *
 * 「伝」を単体で見ないのは、**「手伝う」が発話ではない**ため。
 * 「荷物を手伝って持ち上げる」は正当な無言動作なので、誤検出させない。
 */
const SPEECH_PATTERNS: readonly RegExp[] = [
  /声/,
  /話しかけ/,
  /話す/,
  /話して/,
  /(?<!手)伝え/,
  /言っ/,
  /言う/,
  /言葉/,
  /呼びかけ/,
  /呼んで/,
  /挨拶/,
  /すみません/,
  /一言/,
];

/** 動作テキストに発話が含まれていれば true。 */
export function containsSpeech(action: string): boolean {
  return SPEECH_PATTERNS.some((pattern) => pattern.test(action));
}

/** 検出された語を返す。ログとデバッグ用。 */
export function findSpeechTerms(action: string): string[] {
  return SPEECH_PATTERNS.flatMap((pattern) => {
    const hit = action.match(pattern);
    return hit ? [hit[0]] : [];
  });
}
