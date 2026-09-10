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

/// UX指摘.md 2-2・2-5・2-6 の回帰。

late List<MethodCall> ble;
late bool bluetoothOn;
late bool permissionGranted;

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

SottoApi okApi() => SottoApi(
      client: MockClient((req) async {
        final body = switch (req.url.path) {
          '/api/needs' => savedNeeds.toJson(),
          '/api/demands' => {'blob': 'b'},
          _ => throw StateError(req.url.path),
        };
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
      }),
    );

SottoApi downApi() => SottoApi(
      client: MockClient((_) async => http.Response('nope', 500)),
    );

Future<Profile> profile({Role? role, Needs? needs}) async {
  SharedPreferences.setMockInitialValues({});
  final p = await Profile.load();
  if (role != null) await p.setRole(role);
  if (needs != null) await p.setNeeds(needs);
  return p;
}

void main() {
  setUp(() {
    ble = [];
    bluetoothOn = true;
    permissionGranted = true;
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('dev.sotto/ble'), (call) async {
      ble.add(call);
      return switch (call.method) {
        'requestPermissions' => permissionGranted,
        'isBluetoothOn' => bluetoothOn,
        _ => null,
      };
    });
    m.setMockMethodCallHandler(const MethodChannel('dev.sotto/ble/events'), (_) async => null);
  });

  group('2-2 スキャンできない原因が主メッセージに出る', () {
    testWidgets('Bluetooth がオフのとき、大きい文字が「いまは近くにいません」と言わない', (tester) async {
      bluetoothOn = false;
      await tester.pumpWidget(SottoApp(profile: await profile(role: Role.giver), api: okApi()));
      await tester.pumpAndSettle();

      expect(find.text('いまは近くにいません'), findsNothing);
      expect(find.textContaining('Bluetooth'), findsWidgets);
    });

    testWidgets('権限が無いとき、大きい文字が「いまは近くにいません」と言わない', (tester) async {
      permissionGranted = false;
      await tester.pumpWidget(SottoApp(profile: await profile(role: Role.giver), api: okApi()));
      await tester.pumpAndSettle();

      expect(find.text('いまは近くにいません'), findsNothing);
    });

    testWidgets('原因が解けたら「いまは近くにいません」に戻る', (tester) async {
      bluetoothOn = false;
      await tester.pumpWidget(SottoApp(profile: await profile(role: Role.giver), api: okApi()));
      await tester.pumpAndSettle();

      bluetoothOn = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('いまは近くにいません'), findsOneWidget);
    });
  });

  group('2-5 単一選択は選び直しだけ。解除で詰まない', () {
    testWidgets('受け手：選んだ4択をもう一度押しても選択は外れない', (tester) async {
      await tester.pumpWidget(SottoApp(profile: await profile(role: Role.seeker), api: okApi()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('立っているのがつらい'));
      await tester.pump();
      await tester.tap(find.text('立っているのがつらい'));
      await tester.pump();

      final cont = tester.widget<FilledButton>(
        find.ancestor(of: find.text('つづける'), matching: find.byType(FilledButton)),
      );
      expect(cont.onPressed, isNotNull);
    });
  });

  group('2-6 無効な主ボタンは理由を言う', () {
    testWidgets('受け手：何も選んでいないとき［ つづける ］の下に理由が出る', (tester) async {
      await tester.pumpWidget(SottoApp(profile: await profile(role: Role.seeker), api: okApi()));
      await tester.pumpAndSettle();

      expect(find.text('どれか一つ選んでください'), findsOneWidget);
    });
  });
}
