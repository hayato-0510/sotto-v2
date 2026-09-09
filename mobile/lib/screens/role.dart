import 'package:flutter/material.dart';

import '../ui.dart';
import 'comparison.dart';
import 'giver.dart';
import 'receiver.dart';

/// 起動・役割選択（設計書 §3.3）。「譲れる」のような善意を含意する語は使わない（FR-02）。
///
/// 最下部の一行が §1.5.1 の制約（同一OS間のみ）の UI 明示にあたる（AGENTS.md §5）。
/// その下のデモ制約も同じ理由で画面に出す。
class RoleScreen extends StatelessWidget {
  const RoleScreen({super.key});

  @override
  Widget build(BuildContext context) => Sheet(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 96),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ReceiverFlow()),
              ),
              child: const Text('席がほしい'),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const GiverFlow()),
              ),
              child: const Text('いま座っている'),
            ),
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
            // 審査用の画面は本編の導線と別の層に置く（POSTMORTEM 根本原因4）。
            // ここは色も大きさも落とし、押さなくても本編が成立する
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ComparisonScreen()),
                ),
                child: const Text('審査用：混み具合で動作がどう変わるか'),
              ),
            ),
          ],
        ),
      );
}
