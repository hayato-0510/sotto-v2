import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sotto/api.dart';
import 'package:sotto/main.dart';
import 'package:sotto/profile.dart';
import 'package:sotto/types.dart';

/// BLE チャネルへの呼び出しを記録する。実機の代わりに、何を頼んだかだけを見る
late List<MethodCall> ble;

List<String> get bleMethods => ble.map((c) => c.method).toList();

const summary = '立っているとふらつきがあり、座って移動したい状態です。';

const savedNeeds = Needs(
  posture: '座位が必要',
  needsSupport: false,
  timeSensitive: false,
  luggage: 'なし',
  avoid: [],
  summary: summary,
  confidence: 'high',
);

/// AI サーバの代わり。/api/needs は上の要約を、/api/demands は封緘を返す
SottoApi fakeApi() => SottoApi(
      client: MockClient((req) async {
        final body = switch (req.url.path) {
          '/api/needs' => savedNeeds.toJson(),
          '/api/demands' => {'blob': 'sealed-blob'},
          _ => throw StateError('想定外の呼び出し: ${req.url.path}'),
        };
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
      }),
    );

Future<Profile> profileWith({Role? role, Needs? needs}) async {
  SharedPreferences.setMockInitialValues({});
  final p = await Profile.load();
  if (role != null) await p.setRole(role);
  if (needs != null) await p.setNeeds(needs);
  return p;
}

Future<void> open(WidgetTester tester, Profile profile) async {
  await tester.pumpWidget(SottoApp(profile: profile, api: fakeApi()));
  await tester.pumpAndSettle();
}

Future<void> startAdvertising(WidgetTester tester) async {
  await tester.tap(find.text('これで発信する'));
  await tester.pumpAndSettle();
  expect(find.text('席がほしい、と発信しています'), findsOneWidget);
}

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('設定'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    ble = [];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('dev.sotto/ble'), (call) async {
      ble.add(call);
      return switch (call.method) {
        'requestPermissions' || 'isBluetoothOn' => true,
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(const MethodChannel('dev.sotto/ble/events'), (_) async => null);
  });

  testWidgets('初回は役割を選び、選んだ役割が保存される', (tester) async {
    final profile = await profileWith();
    await open(tester, profile);

    await tester.tap(find.text('席をさがす'));
    await tester.pumpAndSettle();

    expect(find.text('どれが近いですか'), findsOneWidget);
    expect(find.text('あなた ／ 席をさがす'), findsOneWidget);
    expect((await Profile.load()).role, Role.seeker);
  });

  testWidgets('保存した需要があれば、開いたときに要約と［ これで発信する ］だけが出る', (tester) async {
    await open(tester, await profileWith(role: Role.seeker, needs: savedNeeds));

    expect(find.text(summary), findsOneWidget);
    expect(find.text('これで発信する'), findsOneWidget);
    expect(find.text('どれが近いですか'), findsNothing);
  });

  testWidgets('開いただけでは発信しない。本人が押すまで始めない（AGENTS.md §4）', (tester) async {
    await open(tester, await profileWith(role: Role.seeker, needs: savedNeeds));

    expect(bleMethods, isNot(contains('startDemand')));
  });

  testWidgets('席を空ける側で開くと、譲る側の画面になりスキャンが始まる', (tester) async {
    await open(tester, await profileWith(role: Role.giver));

    expect(find.text('いまは近くにいません'), findsOneWidget);
    expect(find.text('あなた ／ 席を空ける'), findsOneWidget);
    expect(bleMethods, contains('startScan'));
  });

  testWidgets('席を空ける側は、アプリを離れるとスキャンを止め、戻ると再開する', (tester) async {
    await open(tester, await profileWith(role: Role.giver));
    ble.clear();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(bleMethods, ['stopScan']);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(bleMethods.last, 'startScan');
    expect(find.text('閉じる'), findsNothing);
  });

  testWidgets('初めて発信したとき、需要の中身が保存される', (tester) async {
    final profile = await profileWith(role: Role.seeker);
    await open(tester, profile);

    await tester.tap(find.text('立っているのがつらい'));
    await tester.pump();
    await tester.tap(find.text('つづける'));
    await tester.pumpAndSettle();
    await startAdvertising(tester);

    expect((await Profile.load()).needs?.summary, summary);
    final start = ble.singleWhere((c) => c.method == 'startDemand');
    expect(start.arguments, {'blob': 'sealed-blob'});
  });

  testWidgets('発信中に役割を変えると、発信が止まる', (tester) async {
    await open(tester, await profileWith(role: Role.seeker, needs: savedNeeds));
    await startAdvertising(tester);
    await openSettings(tester);

    await tester.tap(find.text('席を空ける'));
    await tester.pumpAndSettle();

    expect(bleMethods.lastIndexOf('stopDemand'), greaterThan(bleMethods.indexOf('startDemand')));
    expect((await Profile.load()).role, Role.giver);
  });

  testWidgets('発信中に需要を［ 変える ］と、発信が止まり4択からやり直す', (tester) async {
    await open(tester, await profileWith(role: Role.seeker, needs: savedNeeds));
    await startAdvertising(tester);
    await openSettings(tester);

    // 設定画面はテストの画面（800x600）より縦に長い。実機でも小さい端末ではスクロールする
    await tester.ensureVisible(find.text('変える'));
    await tester.tap(find.text('変える'));
    await tester.pumpAndSettle();

    expect(find.text('どれが近いですか'), findsOneWidget);
    expect(bleMethods.lastIndexOf('stopDemand'), greaterThan(bleMethods.indexOf('startDemand')));
    expect((await Profile.load()).needs, isNull);
  });

  testWidgets('発信する前に［ 変える ］を押しても、古い要約は残らず4択からやり直す', (tester) async {
    await open(tester, await profileWith(role: Role.seeker, needs: savedNeeds));
    await openSettings(tester);

    await tester.ensureVisible(find.text('変える'));
    await tester.tap(find.text('変える'));
    await tester.pumpAndSettle();

    expect(find.text('どれが近いですか'), findsOneWidget);
    expect(find.text(summary), findsNothing);
  });

  testWidgets('［ やめる ］で発信を止めると、要約の画面に戻る', (tester) async {
    await open(tester, await profileWith(role: Role.seeker, needs: savedNeeds));
    await startAdvertising(tester);

    await tester.tap(find.text('やめる'));
    await tester.pumpAndSettle();

    expect(bleMethods.last, 'stopDemand');
    expect(find.text('これで発信する'), findsOneWidget);
  });
}
