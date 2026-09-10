import 'package:flutter/material.dart';

import '../profile.dart';
import '../ui.dart';

/// 設定。保存しているもの（役割と、受け手の需要の中身）はここでだけ変える。
///
/// 同一OSの制約と実機未検証の注記、審査用画面への入口は置かない（役割選択の画面にだけある）。
/// 役割を変えると、下にある流れは Home が畳んで作り直し、そのとき発信・スキャンが止まる。
/// ［ 変える ］は需要を消して閉じる。Home が4択から始め直す
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.profile});

  final Profile profile;

  static const _heading = TextStyle(fontSize: 14, height: 1.5, color: faint);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: profile,
        builder: (context, _) {
          final role = profile.role;
          final needs = profile.needs;
          return Sheet(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Lead('設定'),
                const SizedBox(height: 28),
                const Text('いまの立場', style: _heading),
                const SizedBox(height: 12),
                for (final r in Role.values) ...[
                  r == role
                      ? FilledButton(onPressed: () {}, child: Text(r.label))
                      : OutlinedButton(onPressed: () => profile.setRole(r), child: Text(r.label)),
                  const SizedBox(height: 10),
                ],
                if (role == Role.seeker && needs != null) ...[
                  const SizedBox(height: 28),
                  const Text('席をさがすときの内容', style: _heading),
                  const SizedBox(height: 8),
                  Sub(needs.summary),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () async {
                        await profile.clearNeeds();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      child: const Text('変える'),
                    ),
                  ),
                ],
              ],
            ),
            onBack: () => Navigator.of(context).pop(),
          );
        },
      );
}
