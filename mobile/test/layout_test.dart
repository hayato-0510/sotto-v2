/// 画面のレイアウトが、生成文の長さや小さい端末で崩れないかを見る。
///
/// Flutter のテストは RenderFlex のはみ出しを失敗として扱うので、
/// 実機やエミュレータが無くても「文字が入りきらない」を検出できる。
/// AI の出力は長さが決まらないため、想定される最長の文で確かめる。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/ui.dart';

/// 確認する画面の大きさ。小さい方は Android の実機で今も広く使われる 360x640 相当
const _sizes = <String, Size>{
  '360x640（小さめの端末）': Size(360, 640),
  '411x731（Pixel 相当）': Size(411, 731),
};

Future<void> _pump(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: sottoTheme(), home: child));
  await tester.pumpAndSettle();
}

void main() {
  // 設計書 §3.3 の例文と、実際に Gemini が返した文のうち長いもの
  const longAction = '立って、座面に手を添えたまま。相手が座るまでそこで待ってください';
  const longReason = '混雑時は立つだけでは入れないため、相手が入れる経路を作る必要があるためです';

  _sizes.forEach((label, size) {
    group(label, () {
      testWidgets('譲る側：動作の提示（長い生成文）がはみ出さない', (tester) async {
        await _pump(
          tester,
          size,
          Sheet(
            body: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Lead(longAction),
                SizedBox(height: 28),
                Sub('およそ25秒 ／ $longReason'),
              ],
            ),
            corner: TextButton(onPressed: () {}, child: const Text('やめる')),
            footer: const Note('定型の案内を表示しています'),
          ),
        );
        expect(find.text(longAction), findsOneWidget);
      });

      testWidgets('譲る側：需要の提示（混み具合3択＋デモ注記）がはみ出さない', (tester) async {
        await _pump(
          tester,
          size,
          Sheet(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Lead('すぐ近くに、席を必要としている人がいます'),
                const SizedBox(height: 36),
                const Sub('いまの車内は?'),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: () {}, child: const Text('空いている')),
                const SizedBox(height: 10),
                OutlinedButton(onPressed: () {}, child: const Text('混んでいる')),
                const SizedBox(height: 10),
                OutlinedButton(onPressed: () {}, child: const Text('ぎゅうぎゅう')),
              ],
            ),
            action: FilledButton(onPressed: () {}, child: const Text('譲る')),
            corner: TextButton(onPressed: () {}, child: const Text('閉じる')),
            footer: const Note(
              'デモ版：近くに複数の人がいるときは、本来は待ち時間の長い人からですが、'
              'このビルドでは電波の強い人から順になります',
            ),
          ),
        );
        expect(find.text('譲る'), findsOneWidget);
      });

      testWidgets('起動・役割選択（注記2つと審査用リンク）がはみ出さない', (tester) async {
        await _pump(
          tester,
          size,
          Sheet(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 96),
                OutlinedButton(onPressed: () {}, child: const Text('席がほしい')),
                const SizedBox(height: 20),
                OutlinedButton(onPressed: () {}, child: const Text('いま座っている')),
              ],
            ),
            footer: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Sub('いまは Android どうしでのみつながります'),
                const SizedBox(height: 12),
                const Note(
                  'このビルドは実機での近接検知を検証する前のものです。'
                  '数mの判定と電車の移動の検知は暫定で、検証の結果で変わります',
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(onPressed: () {}, child: const Text('審査用：混み具合で動作がどう変わるか')),
                ),
              ],
            ),
          ),
        );
        expect(find.text('席がほしい'), findsOneWidget);
      });

      testWidgets('受け手：待機（デモ注記つき）がはみ出さない', (tester) async {
        await _pump(
          tester,
          size,
          Sheet(
            body: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Lead('席がほしい、と発信しています'),
                SizedBox(height: 12),
                Sub('見つかったら画面が変わります'),
              ],
            ),
            corner: TextButton(onPressed: () {}, child: const Text('やめる')),
            footer: const Note(
              'デモ版：本来は電車の移動を検知している間だけ発信しますが、'
              'このビルドではその検知を省き、やめるまで発信を続けます',
            ),
          ),
        );
        expect(find.text('席がほしい、と発信しています'), findsOneWidget);
      });
    });
  });
}
