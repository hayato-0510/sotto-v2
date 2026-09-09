/**
 * 設計書 §6 のデータモデル。sotto（旧リポジトリ）から、接続方式に依存しない
 * 部分だけを移植した（docs/POSTMORTEM.md 参照）。`Session` / `SessionState` は
 * 「合言葉」接続方式そのものだったため持ってきていない。
 *
 * 意図的に持っていないもの：
 *   - 疾患名・障害名のフィールド（設計書 §12.1「障害情報を送らない」）
 *   - 顔写真・氏名（同上）
 * 追加しないこと。
 */

// ── 乗車前の登録 ─────────────────────────────────

export type StopsToAlight = 1 | 3 | 8;

export interface Condition {
  /** 自由記述。属性ではなく「その日の状態」を書く。最大200字 */
  text: string;
  stopsToAlight: StopsToAlight;
}

// ── ステップ1の出力（状態 → 配慮） ────────────────

export type Posture = '座位が必要' | '立位でも可（支えが要る）' | '状況による';

export interface Needs {
  posture: Posture;
  /** 手すり・壁など支えが要るか */
  needsSupport: boolean;
  /** 早さが重要か（気分不良など） */
  timeSensitive: boolean;
  luggage: '多い' | '少ない' | '不明';
  /** 避けたいこと。書かれていないことを創作しない。空配列を許す */
  avoid: string[];
  /** 本人が読んで確認するための一文（20〜40字）。他人には見せない */
  summary: string;
  confidence: 'high' | 'medium' | 'low';
  /** 生成に失敗し、固定文で代替した場合に true（FR-12）。画面で明示すること */
  isFallback?: boolean;
}

// ── 車内状況 ─────────────────────────────────────

export type Crowding = '空いている' | '普通' | '混雑' | '超満員';

export interface Situation {
  crowding: Crowding;
  stopsToAlight: StopsToAlight;
  /** 0-23。サーバ側で付与する */
  hour: number;
}

// ── ステップ2の出力（配慮＋状況 → 受け渡し） ──────

export interface Handoff {
  /** リクエスターが本当に求めていること。1文。席とは限らない */
  request: string;
  /** サポーターの動作。10〜20字。**発話を含めてはならない** */
  action: string;
  /** なぜその動作が最適か。混雑と降車駅数に触れる1文 */
  reason: string;
  seconds: number;
  /** '高' を持たない。重い動作を生成させないため */
  physicalLoad: '低' | '中';
  /** 生成に失敗し、固定文で代替した場合に true（FR-12）。画面で明示すること */
  isFallback?: boolean;
}

// 発話チェックは lib/speech.ts に一本化する（旧リポジトリでは types.ts にも
// 簡易版が重複していた。「手伝う」を誤検出しない等の調整は speech.ts 側にしかない）
