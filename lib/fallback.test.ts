import { describe, expect, it } from 'vitest';
import { fallbackHandoff } from './fallback';
import { containsSpeech } from './speech';
import type { Crowding } from './types';

/**
 * lib/fallback.ts の固定文は lib/llm.ts の発話チェック（1回だけ再生成）を通らない
 * 経路（APIキー未設定・生成失敗）で直接ユーザーに表示される。
 * ここが発話を含んでいたら §7.5 の安全設計そのものが崩れるため、固定で回帰させる。
 */

const CROWDINGS: Crowding[] = ['空いている', '普通', '混雑', '超満員'];

describe('固定文のaction に発話が含まれない', () => {
  it.each(CROWDINGS)('%s', (crowding) => {
    const handoff = fallbackHandoff(crowding);
    expect(containsSpeech(handoff.action)).toBe(false);
  });
});

describe('固定文には isFallback が立っている', () => {
  it.each(CROWDINGS)('%s', (crowding) => {
    expect(fallbackHandoff(crowding).isFallback).toBe(true);
  });
});
