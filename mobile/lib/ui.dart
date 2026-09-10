/// UI の部品。設計書 §3 の引き算のルールをここで縛る。
///
/// - カードを使わない。角丸パネルもコンテナも置かない
/// - 1画面＝1メッセージ＋最大1アクション（例外は画面上端の YouAre だけ）
/// - 階層は文字サイズだけで作る
/// - 「何も無い」状態は本当に何も出さない
/// - 色は状態だけを運ぶ
///
/// 反復できるコンポーネントは意図的に用意しない。ここにあるのは文字サイズと余白の約束だけ。
library;

import 'package:flutter/material.dart';

import 'profile.dart';

const Color ink = Color(0xFF1A1A1A);
const Color paper = Color(0xFFFAFAF7);
const Color faint = Color(0xFF8A8A85);

/// 状態を運ぶ唯一の色。申し出が届いた・伝わった、のときだけ使う
const Color live = Color(0xFF2F6F4F);

ThemeData sottoTheme() {
  final base = ThemeData(useMaterial3: true, brightness: Brightness.light);
  return base.copyWith(
    scaffoldBackgroundColor: paper,
    colorScheme: base.colorScheme.copyWith(primary: ink, surface: paper, onSurface: ink),
    textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ink,
        foregroundColor: paper,
        minimumSize: const Size(0, 56),
        padding: const EdgeInsets.symmetric(horizontal: 32),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        minimumSize: const Size(0, 52),
        side: const BorderSide(color: ink, width: 1),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        textStyle: const TextStyle(fontSize: 17),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: faint,
        textStyle: const TextStyle(fontSize: 15),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: UnderlineInputBorder(borderSide: BorderSide(color: ink)),
      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: ink, width: 1.5)),
      hintStyle: TextStyle(color: faint),
    ),
  );
}

/// 一文の見出し。画面に1つだけ
class Lead extends StatelessWidget {
  const Lead(this.text, {super.key, this.color = ink});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(fontSize: 26, height: 1.45, fontWeight: FontWeight.w500, color: color),
      );
}

/// 見出しに添える一文。無くてよいなら置かない
class Sub extends StatelessWidget {
  const Sub(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 17, height: 1.6, color: ink));
}

/// 隅に小さく置く注記。デモ簡略化の明示（AGENTS.md §5）や「定型の案内」にだけ使う
class Note extends StatelessWidget {
  const Note(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 13, height: 1.5, color: faint));
}

/// 画面の骨。上に文、下にアクション。囲みは無い
class Sheet extends StatelessWidget {
  const Sheet({super.key, required this.body, this.action, this.corner, this.footer, this.onBack});

  /// 文（見出しと添え文）
  final Widget body;

  /// 主アクション。最大1つ
  final Widget? action;

  /// 隅の小さな逃げ道（やめる など）
  final Widget? corner;

  /// 最下部の注記
  final Widget? footer;

  /// 前の画面へ戻る。設定のように上に積んだ画面でだけ使う。
  /// 隅の corner（やめる など）とは役目が違うので、Android の標準の位置（左上）に、
  /// 本文と同じ濃さで「もどる」と文字も添えて置く。矢印だけでは伝わらない人がいる
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (onBack != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 0, 0),
                  child: TextButton.icon(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back, size: 24),
                    label: const Text('もどる'),
                    style: TextButton.styleFrom(
                      foregroundColor: ink,
                      minimumSize: const Size(0, 48),
                      textStyle: const TextStyle(fontSize: 17),
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(28, onBack == null ? 48 : 16, 28, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: SingleChildScrollView(child: body)),
                      if (action != null) ...[const SizedBox(height: 24), action!],
                      if (corner != null) ...[
                        const SizedBox(height: 8),
                        Align(alignment: Alignment.centerRight, child: corner),
                      ],
                      if (footer != null) ...[const SizedBox(height: 16), footer!],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

/// いまの立場の常時表示。1画面＝1メッセージの唯一の例外（設計書 §3）。
///
/// 画面上の他の文はすべて相手のこと（「すぐ近くに、席を必要としている人がいます」）なので、
/// ここだけ主語を「あなた」と明示し、自分の話だと取り違えないようにする。
/// アイコンは姿勢で分ける。両方を「席」の絵にすると左右の区別がつかない
class YouAre extends StatelessWidget {
  const YouAre({super.key, required this.role, required this.onSettings});

  final Role role;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Material(
        color: paper,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 4, 12, 0),
          child: Row(
            children: [
              Icon(
                switch (role) {
                  Role.seeker => Icons.accessibility_new,
                  Role.giver => Icons.airline_seat_recline_normal,
                },
                size: 22,
                color: ink,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('あなた ／ ${role.label}', style: const TextStyle(fontSize: 15, color: ink)),
              ),
              IconButton(
                onPressed: onSettings,
                tooltip: '設定',
                icon: const Icon(Icons.settings_outlined, color: faint),
              ),
            ],
          ),
        ),
      );
}
