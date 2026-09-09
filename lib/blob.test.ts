import { describe, expect, it } from 'vitest';
import { seal, unseal, BlobError } from './blob';
import type { Needs } from './types';

const needs: Needs = {
  posture: '座位が必要',
  needsSupport: true,
  timeSensitive: false,
  luggage: '不明',
  avoid: ['長時間の立位'],
  summary: '本人確認用の文。外に出さない',
  confidence: 'high',
};

describe('seal / unseal', () => {
  it('往復で Needs（summary 抜き）と駅数・時刻が戻る', () => {
    const blob = seal(needs, 3, 1_700_000_000_000);
    const d = unseal(blob);
    expect(d.needs.posture).toBe('座位が必要');
    expect(d.needs.avoid).toEqual(['長時間の立位']);
    expect(d.stopsToAlight).toBe(3);
    expect(d.createdAt).toBe(1_700_000_000_000);
  });

  it('summary を封緘に含めない', () => {
    const blob = seal(needs, 3);
    expect('summary' in unseal(blob).needs).toBe(false);
  });

  it('封緘は base64url で、GATT に載る大きさに収まる', () => {
    const blob = seal(needs, 8);
    expect(blob).toMatch(/^[A-Za-z0-9_-]+$/);
    expect(blob.length).toBeLessThan(400);
  });

  it('同じ入力でも毎回違う封緘になる（IV がランダム）', () => {
    expect(seal(needs, 3, 1)).not.toBe(seal(needs, 3, 1));
  });

  it('改竄すると BlobError', () => {
    const blob = seal(needs, 3);
    const tampered = blob.slice(0, -2) + (blob.endsWith('AA') ? 'BB' : 'AA');
    expect(() => unseal(tampered)).toThrow(BlobError);
  });

  it('でたらめな文字列は BlobError', () => {
    expect(() => unseal('hello')).toThrow(BlobError);
    expect(() => unseal('')).toThrow(BlobError);
  });
});
