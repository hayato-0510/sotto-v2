import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/ble.dart';
import 'package:sotto/types.dart';

void main() {
  const handoff = Handoff(
    request: '座れる場所があると助かります',
    action: '立って、座面に手を添えたまま待つ',
    reason: '混雑時は席が埋まりやすいためです',
    seconds: 20,
    physicalLoad: '低',
  );

  group('Handoff / Needs の JSON', () {
    test('Handoff は TypeScript 側と同じキーで往復する', () {
      final j = handoff.toJson();
      expect(j.keys.toSet(), {'request', 'action', 'reason', 'seconds', 'physicalLoad'});
      final back = Handoff.fromJson(j);
      expect(back.action, handoff.action);
      expect(back.isFallback, isFalse);
    });

    test('isFallback は true のときだけ載る', () {
      expect(Handoff.fromJson({...handoff.toJson(), 'isFallback': true}).isFallback, isTrue);
    });

    test('Needs に疾患名や位置情報のフィールドが無い', () {
      const needs = Needs(
        posture: '座位が必要',
        needsSupport: false,
        timeSensitive: false,
        luggage: '不明',
        avoid: [],
        summary: 's',
        confidence: 'high',
      );
      final keys = needs.toJson().keys.toSet();
      expect(keys.contains('diagnosis'), isFalse);
      expect(keys.contains('location'), isFalse);
      expect(keys, {'posture', 'needsSupport', 'timeSensitive', 'luggage', 'avoid', 'summary', 'confidence'});
    });
  });

  group('混雑度', () {
    test('UI の3択がサーバの値に対応する（「普通」は出さない）', () {
      expect(Crowding.values.map((c) => c.apiValue), ['空いている', '混雑', '超満員']);
      expect(Crowding.values.map((c) => c.label), ['空いている', '混んでいる', 'ぎゅうぎゅう']);
    });
  });

  group('端末間メッセージ', () {
    test('offer は Handoff ごと往復する', () {
      final m = PeerMessage.parse(const OfferMessage(handoff).encode());
      expect(m, isA<OfferMessage>());
      expect((m! as OfferMessage).handoff.reason, handoff.reason);
    });

    test('単純なメッセージが往復する', () {
      expect(PeerMessage.parse(const CancelMessage().encode()), isA<CancelMessage>());
      expect(PeerMessage.parse(const ThanksMessage().encode()), isA<ThanksMessage>());
      expect(PeerMessage.parse(const NotFoundMessage().encode()), isA<NotFoundMessage>());
      expect(PeerMessage.parse(const TakenMessage().encode()), isA<TakenMessage>());
    });

    test('壊れた JSON や未知の type は無視する', () {
      expect(PeerMessage.parse('not json'), isNull);
      expect(PeerMessage.parse('{"type":"unknown"}'), isNull);
      expect(PeerMessage.parse('{"type":"offer"}'), isNull);
    });
  });
}
