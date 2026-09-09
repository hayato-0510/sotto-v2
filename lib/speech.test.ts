import { describe, expect, it } from 'vitest';
import { containsSpeech, findSpeechTerms } from './speech';

/**
 * 設計書 §13.3「安全性：action に発話系の語が入らない」に対応する回帰テスト。
 *
 * このテストが落ちるということは、生成物に「声をかけろ」という指示が
 * 混入しうるということであり、プロダクトの前提そのものが崩れる。
 */

describe('無言動作として通すべきもの', () => {
  const allowed = [
    '立って、ドア横へ2歩',
    '通路側に一歩寄る',
    '荷物を膝にのせる',
    '手すりのスペースを空ける',
    '席を立ち、離れた位置へ移動する',
    '足元のカバンを自分側に寄せる',
    '座ったまま奥へ詰める',
    // 「手伝う」は発話ではない。伝 単体で弾くと誤検出になる
    '荷物を手伝って持ち上げる',
  ];

  it.each(allowed)('通す: %s', (action) => {
    expect(containsSpeech(action)).toBe(false);
  });
});

describe('発話として弾くべきもの', () => {
  const rejected = [
    '声をかけて席を譲る',
    'お声がけしてから立つ',
    'すみませんと言って立つ',
    '挨拶してから移動する',
    '一言添えて席を立つ',
    '話しかけて確認する',
    '相手に話す',
    '空いたことを伝える',
    '呼びかけて誘導する',
    '声を出さずに、と言う',
  ];

  it.each(rejected)('弾く: %s', (action) => {
    expect(containsSpeech(action)).toBe(true);
  });
});

describe('findSpeechTerms', () => {
  it('検出した語を返す', () => {
    expect(findSpeechTerms('声をかけて挨拶する')).toEqual(
      expect.arrayContaining(['声', '挨拶']),
    );
  });

  it('無言動作なら空配列', () => {
    expect(findSpeechTerms('立って、ドア横へ2歩')).toEqual([]);
  });
});
