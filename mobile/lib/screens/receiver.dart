import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../ble.dart';
import '../profile.dart';
import '../types.dart';
import '../ui.dart';

/// 受け手の一連の画面（設計書 §3.1・§3.3）。
///
/// 需要の宣言 → Needs 確認 → 待機 → 申し出の受信 → お礼、を1つの状態機械で持つ。
/// BLE のイベントを受ける場所を1箇所にするため、画面を分けずに状態で描き分ける。
///
/// 需要の中身は、初めて発信するときに保存する（lib/profile.dart）。次からは要約と
/// ［ これで発信する ］だけの画面（ready）から始まり、4択も AI の待ち時間も通らない。
/// 発信は毎回本人が押して始める。この1タップが「いま席が要る」の意思表示を兼ねるので、
/// 常時設定の必要確認（FR-18）は置かない。中身を変えるのは設定画面の［ 変える ］から。
enum _Stage { declare, reading, confirm, ready, sealing, waiting, offered, askSeated, notFound, cancelled, done }

class ReceiverFlow extends StatefulWidget {
  const ReceiverFlow({super.key, required this.profile, this.api});

  final Profile profile;

  /// テストで AI サーバを差し替えるためだけにある。null なら本物へ繋ぐ
  final SottoApi? api;

  @override
  State<ReceiverFlow> createState() => _ReceiverFlowState();
}

class _ReceiverFlowState extends State<ReceiverFlow> {
  static const _choices = [
    'つわり・めまいがある',
    '立っているのがつらい',
    '足や腰が痛む',
    '見た目には分からない不調がある',
  ];

  /// お礼のタップが無いときに「座れましたか」を出すまでの時間（設計書 §2.5、FR-10）
  static const _seatedAskAfter = Duration(seconds: 90);

  late final SottoApi _api = widget.api ?? SottoApi();
  final _ble = SottoBle.instance;
  final _free = TextEditingController();

  late Needs? _needs = widget.profile.needs;
  late _Stage _stage = _needs == null ? _Stage.declare : _Stage.ready;
  int? _choice;
  String? _error;
  StreamSubscription<PeerMessage>? _messages;
  StreamSubscription<String>? _errors;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _messages = _ble.messages.listen(_onMessage);
    _errors = _ble.errors.listen((m) {
      if (mounted) setState(() => _error = m);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _messages?.cancel();
    _errors?.cancel();
    _free.dispose();
    // 画面を離れたら発信も止める。隠れて発信しない（設計書 §1.4）
    _ble.stopDemand().catchError((_) {});
    super.dispose();
  }

  // ── 遷移 ─────────────────────────────────────────

  Future<void> _read() async {
    final parts = <String>[
      if (_choice != null) _choices[_choice!],
      if (_free.text.trim().isNotEmpty) _free.text.trim(),
    ];
    if (parts.isEmpty) return;
    setState(() {
      _stage = _Stage.reading;
      _error = null;
    });
    try {
      final needs = await _api.extractNeeds(parts.join('。'));
      if (!mounted) return;
      setState(() {
        _needs = needs;
        _stage = _Stage.confirm;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _stage = _Stage.declare;
      });
    }
  }

  Future<void> _startDemand() async {
    final needs = _needs;
    if (needs == null) return;
    // 失敗したら押す前の画面（初回は確認、2回目以降は ready）に戻す
    final back = _stage;
    await widget.profile.setNeeds(needs);
    if (!mounted) return;
    setState(() {
      _stage = _Stage.sealing;
      _error = null;
    });
    try {
      if (!await _ble.requestPermissions()) {
        throw BleException('Bluetooth の権限が無いと発信できません');
      }
      if (!await _ble.isBluetoothOn()) {
        throw BleException('Bluetooth をオンにしてください');
      }
      final blob = await _api.sealDemand(needs);
      await _ble.startDemand(blob);
      if (!mounted) return;
      setState(() => _stage = _Stage.waiting);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _stage = back;
      });
    } on BleException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _stage = back;
      });
    }
  }

  /// 発信を止めて ready に戻る。需要の中身は保存済みなので、次は1タップで再開できる
  Future<void> _stop() async {
    _timer?.cancel();
    await _ble.stopDemand().catchError((_) {});
    if (mounted) _toReady();
  }

  void _toReady() => setState(() {
        _stage = _Stage.ready;
        _error = null;
      });

  void _onMessage(PeerMessage m) {
    switch (m) {
      case OfferMessage():
        _timer?.cancel();
        _timer = Timer(_seatedAskAfter, () {
          if (mounted && _stage == _Stage.offered) setState(() => _stage = _Stage.askSeated);
        });
        setState(() => _stage = _Stage.offered);
      case CancelMessage():
        // 譲る側が取り消した。理由は出さない。「まだ探していますね」だけ（設計書 §2.4）
        if (_stage == _Stage.offered || _stage == _Stage.askSeated) {
          _timer?.cancel();
          setState(() => _stage = _Stage.cancelled);
          _timer = Timer(const Duration(milliseconds: 2500), () {
            if (mounted) setState(() => _stage = _Stage.waiting);
          });
        }
      default:
        break;
    }
  }

  Future<void> _thanks() async {
    _timer?.cancel();
    await _ble.demandReply(const ThanksMessage()).catchError((_) {});
    await _ble.demandRelease().catchError((_) {});
    await _ble.stopDemand().catchError((_) {});
    if (mounted) setState(() => _stage = _Stage.done);
  }

  Future<void> _notFound() async {
    _timer?.cancel();
    await _ble.demandReply(const NotFoundMessage()).catchError((_) {});
    await _ble.demandRelease().catchError((_) {});
    if (mounted) setState(() => _stage = _Stage.notFound);
  }

  // ── 描画 ─────────────────────────────────────────

  @override
  Widget build(BuildContext context) => switch (_stage) {
        _Stage.declare => _declare(),
        _Stage.reading => const Sheet(body: Lead('読み取っています')),
        _Stage.confirm => _confirm(),
        _Stage.ready => _ready(),
        _Stage.sealing => const Sheet(body: Lead('発信の準備をしています')),
        _Stage.waiting => _waiting(),
        _Stage.offered => _offered(),
        _Stage.askSeated => _askSeated(),
        _Stage.notFound => _notFoundPage(),
        _Stage.cancelled => const Sheet(body: Lead('まだ探していますね')),
        _Stage.done => _done(),
      };

  Widget _errorNote() => _error == null ? const SizedBox.shrink() : Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Sub(_error!),
      );

  Widget _declare() => Sheet(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Lead('どれが近いですか'),
            const SizedBox(height: 28),
            for (var i = 0; i < _choices.length; i++) ...[
              _choice == i
                  ? FilledButton(onPressed: () {}, child: Text(_choices[i]))
                  : OutlinedButton(onPressed: () => setState(() => _choice = i), child: Text(_choices[i])),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 20),
            const Sub('ほかにあれば（100字まで）'),
            TextField(
              controller: _free,
              maxLength: 100,
              maxLines: 2,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: '例：貧血気味で立っているとふらつく'),
            ),
            const SizedBox(height: 8),
            _errorNote(),
          ],
        ),
        action: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_choice == null && _free.text.trim().isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Note('どれか一つ選んでください'),
              ),
            FilledButton(
              onPressed: (_choice != null || _free.text.trim().isNotEmpty) ? _read : null,
              child: const Text('つづける'),
            ),
          ],
        ),
      );

  Widget _confirm() {
    final needs = _needs!;
    return Sheet(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Lead('こう受け取りました'),
          const SizedBox(height: 28),
          Sub(needs.summary),
          const SizedBox(height: 16),
          if (needs.isFallback) const Note('自動の読み取りに失敗したため、定型の内容になっています'),
          _errorNote(),
        ],
      ),
      action: FilledButton(onPressed: _startDemand, child: const Text('これで発信する')),
      corner: TextButton(
        onPressed: () => setState(() {
          _stage = _Stage.declare;
          _error = null;
        }),
        child: const Text('書き直す'),
      ),
    );
  }

  /// 2回目以降の最初の画面。保存した要約を本人にだけ見せ、押せば発信する
  Widget _ready() {
    final needs = _needs!;
    return Sheet(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Lead('こう受け取っています'),
          const SizedBox(height: 28),
          Sub(needs.summary),
          const SizedBox(height: 16),
          if (needs.isFallback) const Note('自動の読み取りに失敗したため、定型の内容になっています'),
          _errorNote(),
        ],
      ),
      action: FilledButton(onPressed: _startDemand, child: const Text('これで発信する')),
    );
  }

  Widget _waiting() => Sheet(
        body: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Lead('席がほしい、と発信しています'),
            SizedBox(height: 12),
            Sub('見つかったら画面が変わります'),
          ],
        ),
        corner: TextButton(onPressed: _stop, child: const Text('やめる')),
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[Note(_error!), const SizedBox(height: 8)],
            const Note(
              'デモ版：本来は電車の移動を検知している間だけ発信しますが、'
              'このビルドではその検知を省き、やめるまで発信を続けます',
            ),
          ],
        ),
      );

  Widget _offered() => Sheet(
        body: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Lead('ごく近くの人が席を空けます', color: live),
            SizedBox(height: 12),
            Sub('立ち上がる人がいます'),
          ],
        ),
        action: FilledButton(onPressed: _thanks, child: const Text('ありがとう')),
        corner: TextButton(onPressed: _notFound, child: const Text('見つからない')),
      );

  Widget _askSeated() => Sheet(
        body: const Lead('座れましたか'),
        action: FilledButton(onPressed: _thanks, child: const Text('座れた')),
        corner: TextButton(onPressed: _notFound, child: const Text('座れなかった')),
      );

  Widget _notFoundPage() => Sheet(
        body: const Lead('近くで見つかりませんでした'),
        action: FilledButton(
          onPressed: () => setState(() => _stage = _Stage.waiting),
          child: const Text('待つ'),
        ),
        corner: TextButton(onPressed: _stop, child: const Text('やめる')),
      );

  Widget _done() => Sheet(
        body: const Lead('伝えました', color: live),
        action: FilledButton(onPressed: _toReady, child: const Text('閉じる')),
      );
}
