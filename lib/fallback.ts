/**
 * 生成失敗時に使う固定文。設計書 §8.4・§11・FR-12。
 *
 * NFR-09：プロンプトとフォールバック文は単一ファイルに集約する。
 * デモ本番でここに落ちても「白画面にしない・流れを止めない」ことが最優先で、
 * かわりに `isFallback: true` を必ず立てて、画面側で「これは例です」と明示する。
 *
 * 発生条件（§8.4 UPSTREAM_ERROR）：
 *   - APIキー未設定（.env.local 未設定。AGENTS.md「存在しなければ未設定として扱う」）
 *   - Anthropic / Gemini API のエラー・タイムアウト
 *   - 発話チェック（§7.5）に1回の再生成でも通らなかった場合
 */

import type { Crowding, Handoff, Needs } from './types';

/**
 * 状態テキストからの配慮抽出（ステップ1）が失敗した場合のフォールバック。
 *
 * 何も決めつけず、もっとも保守的な値にする。confidence を low にすることで、
 * 「これは推定に失敗した結果である」ことが数値としても伝わるようにする。
 */
export function fallbackNeeds(): Needs {
  return {
    posture: '状況による',
    needsSupport: false,
    timeSensitive: false,
    luggage: '不明',
    avoid: [],
    summary: '状態の自動読み取りに失敗しました。内容をご確認ください。',
    confidence: 'low',
    isFallback: true,
  };
}

/**
 * 混雑度4段階ぶんの固定 Handoff。
 *
 * ステップ2（要請・動作生成）が失敗しても、
 * 「混雑度で動作が変わる」というH-2の見た目だけは崩さないよう、
 * 混雑度ごとに別の固定文を用意する（プロンプトの設計方針 §7.3 に準拠した内容）。
 */
const FALLBACK_HANDOFF_BY_CROWDING: Record<Crowding, Omit<Handoff, 'isFallback'>> = {
  空いている: {
    request: '座れる場所があると助かります',
    action: '立って、席の前で2秒待ってから離れる',
    reason: '空いているので、席を離れても他の人が入りやすいためです',
    seconds: 20,
    physicalLoad: '低',
  },
  普通: {
    request: '座れる場所があると助かります',
    action: '立って、ドア側へ半身を開いて空ける',
    reason: '相手が入りやすい向きを作ることで、スムーズに替われるためです',
    seconds: 25,
    physicalLoad: '低',
  },
  混雑: {
    request: '席、もしくは寄りかかれる場所があると助かります',
    action: '席の前に立ったまま、通路側へ一歩寄る',
    reason: '混雑時は立つだけでは入れないため、経路を作る必要があるためです',
    seconds: 20,
    physicalLoad: '低',
  },
  超満員: {
    request: '荷物を置ける少しのスペースがあると助かります',
    action: '荷物をどけて、座り位置を少しずらす',
    reason: '席の移動自体が難しいため、席以外の配慮に切り替えています',
    seconds: 15,
    physicalLoad: '中',
  },
};

export function fallbackHandoff(crowding: Crowding): Handoff {
  return { ...FALLBACK_HANDOFF_BY_CROWDING[crowding], isFallback: true };
}

/** 御礼文が生成できなかった場合の固定文（タスク10・加点項目）。 */
export const FALLBACK_THANKS = 'ありがとうございました。助かりました。';
