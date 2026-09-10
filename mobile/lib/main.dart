import 'package:flutter/material.dart';

import 'api.dart';
import 'profile.dart';
import 'screens/giver.dart';
import 'screens/receiver.dart';
import 'screens/role.dart';
import 'screens/settings.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(SottoApp(profile: await Profile.load()));
}

class SottoApp extends StatelessWidget {
  const SottoApp({super.key, required this.profile, this.api});

  final Profile profile;

  /// AI サーバの接続先。テストで差し替えるためだけにある。null なら本物へ繋ぐ
  final SottoApi? api;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Sotto',
        debugShowCheckedModeBanner: false,
        theme: sottoTheme(),
        home: Home(profile: profile, api: api),
      );
}

/// 保存された役割で最初の画面を決める。役割が無ければ初回なので選んでもらう。
///
/// 役割を変えたとき、需要を消したとき（設定の［ 変える ］）は、いまの流れを畳んで作り直す。
/// 畳むと各フローの dispose が発信・スキャンを止める。画面に出ていない発信を残さない
/// （AGENTS.md §4「隠れて発信しない」）。
class Home extends StatefulWidget {
  const Home({super.key, required this.profile, this.api});

  final Profile profile;
  final SottoApi? api;

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int _resets = 0;
  late bool _hadNeeds;

  @override
  void initState() {
    super.initState();
    // 起動時点の値を取る。遅延初期化にすると最初の通知の時点で読まれ、
    // それが［ 変える ］の消去だと「もともと無かった」ことになって作り直しが漏れる
    _hadNeeds = widget.profile.needs != null;
    widget.profile.addListener(_onProfile);
  }

  @override
  void dispose() {
    widget.profile.removeListener(_onProfile);
    super.dispose();
  }

  void _onProfile() {
    final hasNeeds = widget.profile.needs != null;
    if (_hadNeeds && !hasNeeds) _resets++;
    _hadNeeds = hasNeeds;
    setState(() {});
  }

  void _openSettings() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => SettingsScreen(profile: widget.profile)),
      );

  @override
  Widget build(BuildContext context) {
    final role = widget.profile.role;
    if (role == null) return RoleScreen(profile: widget.profile);

    final key = ValueKey('${role.name}#$_resets');
    return ColoredBox(
      color: paper,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            YouAre(role: role, onSettings: _openSettings),
            Expanded(
              child: switch (role) {
                Role.seeker => ReceiverFlow(key: key, profile: widget.profile, api: widget.api),
                Role.giver => GiverFlow(key: key, api: widget.api),
              },
            ),
          ],
        ),
      ),
    );
  }
}
