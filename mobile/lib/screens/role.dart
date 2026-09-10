import 'package:flutter/material.dart';

import '../profile.dart';
import '../ui.dart';
import 'comparison.dart';

/// 役割選択（設計書 §3.3）。初回だけ通る。選んだ役割は保存し、以降は設定で変えるまで維持する。
/// 「譲る／譲られる」のような施す側と施される側を作る語は使わない（FR-02）。
///
/// 最下部の一行が §1.5.1 の制約（同一OS間のみ）の UI 明示にあたる（AGENTS.md §5）。
/// その下のデモ制約も同じ理由で画面に出す。
class RoleScreen extends StatelessWidget {
  const RoleScreen({super.key, required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) => Sheet(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 48),
            const Lead('あなたは、どちらですか'),
            const SizedBox(height: 28),
            for (final r in Role.values) ...[
              OutlinedButton(onPressed: () => profile.setRole(r), child: Text(r.label)),
              const SizedBox(height: 20),
            ],
            const Note('あとから設定で変えられます'),
          ],
        ),
        footer: const ConstraintNotes(),
      );
}

/// 同一OS間の制約と、実機未検証であることの明示（AGENTS.md §5）。審査用の画面への入口も添える。
/// 役割選択は初回しか通らないので、これらを目にするのも初回だけになる
class ConstraintNotes extends StatelessWidget {
  const ConstraintNotes({super.key});

  @override
  Widget build(BuildContext context) => Column(
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
      );
}
