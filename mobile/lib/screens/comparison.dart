import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../types.dart';
import '../ui.dart';

/// 混雑度対比（審査用、FR-13）。製品の導線には現れない。
///
/// ライブ生成にしない。撮影中にレート制限へ当たるリスクを負う価値がない（設計書 §3.1）。
/// `scripts/pregenerate.mjs` が生成した `assets/comparison.json` を読むだけ。
class ComparisonScreen extends StatelessWidget {
  const ComparisonScreen({super.key});

  Future<Map<String, dynamic>> _load() async =>
      jsonDecode(await rootBundle.loadString('assets/comparison.json')) as Map<String, dynamic>;

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: _load(),
        builder: (context, snap) {
          final data = snap.data;
          final items = (data?['items'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>()
              .map((e) => (label: e['label'] as String, handoff: Handoff.fromJson(e['handoff'] as Map<String, dynamic>)))
              .toList();
          final anyFallback = items.any((e) => e.handoff.isFallback);
          return Sheet(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Lead('同じ状態でも、混み具合で動作が変わります'),
                const SizedBox(height: 12),
                if (data != null) Note('状態：${data['condition']}'),
                const SizedBox(height: 32),
                for (final e in items) ...[
                  Note(e.label),
                  const SizedBox(height: 6),
                  Text(e.handoff.action, style: const TextStyle(fontSize: 20, height: 1.5)),
                  const SizedBox(height: 6),
                  Sub('およそ${e.handoff.seconds}秒 ／ ${e.handoff.reason}'),
                  const SizedBox(height: 28),
                ],
              ],
            ),
            onBack: () => Navigator.of(context).pop(),
            footer: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (anyFallback) ...[
                  const Note('未生成のため、定型文を表示しています（scripts/pregenerate.mjs で生成できます）'),
                  const SizedBox(height: 8),
                ],
                const Note('これは審査用の画面です。製品の導線には現れません'),
              ],
            ),
          );
        },
      );
}
