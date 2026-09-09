import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../ble.dart';
import '../types.dart';
import '../ui.dart';

/// 譲る側の一連の画面（設計書 §3.1・§3.3）。
///
/// プル型（§2.2）：この画面を開いている間だけスキャンする。通知は一切ない。
/// 相手の状態は一切出さない。「近くに必要な人がいる」だけを見せる。
/// 押さずに閉じれば何も起こらず、受け手はこの人が見たことすら知らない（FR-09）。
enum _Stage { scanning, preparing, action, thanks, taken, notFound, cancelled }

class GiverFlow extends StatefulWidget {
  const GiverFlow({super.key});

  @override
  State<GiverFlow> createState() => _GiverFlowState();
}

class _GiverFlowState extends State<GiverFlow> {
  final _api = SottoApi();
  final _ble = SottoBle.instance;

  _Stage _stage = _Stage.scanning;
  Crowding? _crowding;
  Handoff? _handoff;
  String? _error;

  /// 直近のスキャン結果。id → 最新
  final Map<String, ScanHit> _hits = {};

  StreamSubscription<ScanHit>? _scans;
  StreamSubscription<PeerMessage>? _messages;
  StreamSubscription<String>? _errors;
  StreamSubscription<void>? _drops;
  Timer? _prune;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scans = _ble.scans.listen((h) {
      final wasNear = _someoneNear;
      if (h.rssi < nearRssiDbm) {
        _hits.remove(h.id);
      } else {
        _hits[h.id] = h;
      }
      // スキャン結果は毎秒何十件も来る。見え方が変わるときだけ描き直す
      if (wasNear != _someoneNear && mounted) setState(() {});
    });
    _messages = _ble.messages.listen(_onMessage);
    _errors = _ble.errors.listen((m) {
      if (mounted) setState(() => _error = m);
    });
    _drops = _ble.disconnections.listen((_) {
      // 受け渡し中に相手が切れた。何も言わず探索に戻る
      if (_stage == _Stage.action || _stage == _Stage.preparing) _backToScan();
    });
    _prune = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_stage != _Stage.scanning) return;
      final now = DateTime.now();
      final wasNear = _someoneNear;
      _hits.removeWhere((_, h) => now.difference(h.at) > scanStaleness);
      if (wasNear != _someoneNear && mounted) setState(() {});
    });
    _startScan();
  }

  @override
  void dispose() {
    _prune?.cancel();
    _timer?.cancel();
    _scans?.cancel();
    _messages?.cancel();
    _errors?.cancel();
    _drops?.cancel();
    _ble.stopScan().catchError((_) {});
    _ble.disconnect().catchError((_) {});
    super.dispose();
  }

  Future<void> _startScan() async {
    try {
      if (!await _ble.requestPermissions()) {
        throw BleException('Bluetooth の権限が無いと近くの人を見つけられません');
      }
      if (!await _ble.isBluetoothOn()) {
        throw BleException('Bluetooth をオンにしてください');
      }
      await _ble.startScan();
    } on BleException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  bool get _someoneNear => _hits.isNotEmpty;

  ScanHit? get _nearest {
    if (_hits.isEmpty) return null;
    // 譲る側に選ばせない（設計書 §2.6）。もっとも近い1人にシステムが決める。
    // 設計書は「待ち時間の長い順」だが、このビルドでは電波の強い順で代用する。
    // 画面にもその旨を出している（AGENTS.md §5、_scanning の footer）
    return _hits.values.reduce((a, b) => a.rssi >= b.rssi ? a : b);
  }

  // ── 譲る ─────────────────────────────────────────

  Future<void> _offer() async {
    final crowding = _crowding;
    final target = _nearest;
    if (crowding == null || target == null) return;
    setState(() {
      _stage = _Stage.preparing;
      _error = null;
    });
    try {
      await _ble.stopScan();
      final blob = await _ble.connect(target.id);
      final handoff = await _api.generateHandoff(blob, crowding);
      await _ble.write(OfferMessage(handoff));
      if (!mounted) return;
      // 待っている間に taken や切断で決着していたら、そちらを優先する（先着1件、設計書 §2.6）
      if (_stage != _Stage.preparing) return;
      setState(() {
        _handoff = handoff;
        _stage = _Stage.action;
      });
    } on BleException catch (e) {
      _fail(e.message);
    } on ApiException catch (e) {
      _fail(e.message);
    }
  }

  void _fail(String message) {
    _timer?.cancel();
    _ble.disconnect().catchError((_) {});
    if (!mounted) return;
    if (_stage != _Stage.preparing) return;
    setState(() {
      _error = message;
      _stage = _Stage.scanning;
    });
    _startScan();
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    await _ble.write(const CancelMessage()).catchError((_) {});
    await _ble.disconnect().catchError((_) {});
    if (!mounted) return;
    setState(() => _stage = _Stage.cancelled);
    _timer = Timer(const Duration(milliseconds: 2500), _backToScan);
  }

  void _onMessage(PeerMessage m) {
    if (_stage != _Stage.action && _stage != _Stage.preparing) return;
    switch (m) {
      case ThanksMessage():
        _settle(_Stage.thanks);
      case TakenMessage():
        _settle(_Stage.taken);
      case NotFoundMessage():
        _settle(_Stage.notFound);
      default:
        break;
    }
  }

  void _settle(_Stage s) {
    _timer?.cancel();
    _ble.disconnect().catchError((_) {});
    if (!mounted) return;
    setState(() => _stage = s);
    _timer = Timer(const Duration(seconds: 4), _backToScan);
  }

  void _backToScan() {
    if (!mounted) return;
    _timer?.cancel();
    _ble.disconnect().catchError((_) {});
    setState(() {
      _stage = _Stage.scanning;
      _handoff = null;
      _crowding = null;
      _hits.clear();
    });
    _startScan();
  }

  // ── 描画 ─────────────────────────────────────────

  @override
  Widget build(BuildContext context) => switch (_stage) {
        _Stage.scanning => _scanning(),
        _Stage.preparing => Sheet(
            body: const Lead('動作を用意しています'),
            corner: TextButton(onPressed: _cancel, child: const Text('やめる')),
          ),
        _Stage.action => _action(),
        _Stage.thanks => const Sheet(body: Lead('そっと伝わりました', color: live)),
        _Stage.taken => const Sheet(body: Lead('他の方が席を譲りました。ありがとうございます')),
        _Stage.notFound => const Sheet(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Lead('相手が見つけられないようです'),
                SizedBox(height: 12),
                Sub('席に戻って大丈夫です'),
              ],
            ),
          ),
        _Stage.cancelled => const Sheet(body: Lead('席に戻って大丈夫です')),
      };

  Widget _scanning() {
    if (!_someoneNear) {
      // 「また見てみてください」は書かない。催促になる（設計書 §3.3）
      return Sheet(
        body: const Lead('いまは近くにいません'),
        corner: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('閉じる')),
        footer: _error == null ? null : Note(_error!),
      );
    }
    return Sheet(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Lead('すぐ近くに、席を必要としている人がいます'),
          const SizedBox(height: 36),
          const Sub('いまの車内は?'),
          const SizedBox(height: 12),
          for (final c in Crowding.values) ...[
            _crowding == c
                ? FilledButton(onPressed: () => setState(() => _crowding = null), child: Text(c.label))
                : OutlinedButton(onPressed: () => setState(() => _crowding = c), child: Text(c.label)),
            const SizedBox(height: 10),
          ],
          if (_error != null) ...[const SizedBox(height: 8), Note(_error!)],
        ],
      ),
      action: FilledButton(onPressed: _crowding == null ? null : _offer, child: const Text('譲る')),
      corner: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('閉じる')),
      footer: _hits.length < 2
          ? null
          : const Note(
              'デモ版：近くに複数の人がいるときは、本来は待ち時間の長い人からですが、'
              'このビルドでは電波の強い人から順になります',
            ),
    );
  }

  Widget _action() {
    final h = _handoff!;
    return Sheet(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Lead(h.action),
          const SizedBox(height: 28),
          Sub('およそ${h.seconds}秒 ／ ${h.reason}'),
        ],
      ),
      corner: TextButton(onPressed: _cancel, child: const Text('やめる')),
      footer: h.isFallback ? const Note('定型の案内を表示しています') : null,
    );
  }
}
