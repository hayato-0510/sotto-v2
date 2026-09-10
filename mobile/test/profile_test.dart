import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sotto/profile.dart';
import 'package:sotto/types.dart';

void main() {
  const needs = Needs(
    posture: '座位が必要',
    needsSupport: true,
    timeSensitive: false,
    luggage: 'なし',
    avoid: ['急な揺れ'],
    summary: '立っているとふらつきがあり、座って移動したい状態です。',
    confidence: 'high',
    isFallback: true,
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('何も保存されていなければ、役割も需要も無い', () async {
    final p = await Profile.load();
    expect(p.role, isNull);
    expect(p.needs, isNull);
  });

  test('選んだ役割は、次にアプリを開いたときも維持される', () async {
    await (await Profile.load()).setRole(Role.giver);
    expect((await Profile.load()).role, Role.giver);
  });

  test('需要の中身は、次にアプリを開いたときも同じ内容で読み出せる', () async {
    await (await Profile.load()).setNeeds(needs);
    final back = (await Profile.load()).needs!;
    expect(back.posture, '座位が必要');
    expect(back.needsSupport, isTrue);
    expect(back.avoid, ['急な揺れ']);
    expect(back.summary, '立っているとふらつきがあり、座って移動したい状態です。');
    // 定型文で代替された内容なら、次回もその旨を画面に出せるよう保つ（FR-12）
    expect(back.isFallback, isTrue);
  });

  test('需要を消しても役割は残る（設定の［ 変える ］）', () async {
    final p = await Profile.load();
    await p.setRole(Role.seeker);
    await p.setNeeds(needs);
    await p.clearNeeds();
    final again = await Profile.load();
    expect(again.role, Role.seeker);
    expect(again.needs, isNull);
  });

  group('保存値が壊れていても起動で落ちない', () {
    for (final (label, stored) in <(String, Map<String, Object>)>[
      ('需要が JSON でない', {Profile.needsKey: '{壊れた'}),
      ('需要の型が合わない', {Profile.needsKey: '{"posture": 1}'}),
      ('知らない役割', {Profile.roleKey: 'captain'}),
    ]) {
      test(label, () async {
        SharedPreferences.setMockInitialValues(stored);
        final p = await Profile.load();
        expect(p.role, isNull);
        expect(p.needs, isNull);
      });
    }
  });

  test('変更を画面へ知らせる', () async {
    final p = await Profile.load();
    var notified = 0;
    p.addListener(() => notified++);
    await p.setRole(Role.seeker);
    await p.setNeeds(needs);
    await p.clearNeeds();
    expect(notified, 3);
  });
}
