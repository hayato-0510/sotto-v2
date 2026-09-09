/// 自作プラットフォームチャネル越しの BLE（設計書 §7.1）。実装は android/…/MainActivity.kt。
///
/// 汎用の BLE ライブラリは使わない。トークンを出し、拾い、封緘と Handoff を渡すだけ。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'types.dart';

/// 譲る側が「すぐ近く」とみなす RSSI（dBm）。Kotlin 側 Gatt.NEAR_RSSI_DBM と揃える。
/// 【実機未検証】暫定値。スパイク1（docs/スパイク手順書.md）の結果で確定する
const int nearRssiDbm = -75;

/// スキャン結果がこの時間更新されなければ「近くにいない」に戻す
const Duration scanStaleness = Duration(seconds: 6);

class BleException implements Exception {
  BleException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 譲る側⇄受け手の間で GATT に載せるメッセージ
sealed class PeerMessage {
  const PeerMessage();

  static PeerMessage? parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    switch (decoded['type']) {
      case 'offer':
        final h = decoded['handoff'];
        if (h is! Map<String, dynamic>) return null;
        return OfferMessage(Handoff.fromJson(h));
      case 'cancel':
        return const CancelMessage();
      case 'thanks':
        return const ThanksMessage();
      case 'not_found':
        return const NotFoundMessage();
      case 'taken':
        return const TakenMessage();
    }
    return null;
  }

  String encode();
}

class OfferMessage extends PeerMessage {
  const OfferMessage(this.handoff);
  final Handoff handoff;
  @override
  String encode() => jsonEncode({'type': 'offer', 'handoff': handoff.toJson()});
}

class CancelMessage extends PeerMessage {
  const CancelMessage();
  @override
  String encode() => '{"type":"cancel"}';
}

class ThanksMessage extends PeerMessage {
  const ThanksMessage();
  @override
  String encode() => '{"type":"thanks"}';
}

class NotFoundMessage extends PeerMessage {
  const NotFoundMessage();
  @override
  String encode() => '{"type":"not_found"}';
}

class TakenMessage extends PeerMessage {
  const TakenMessage();
  @override
  String encode() => '{"type":"taken"}';
}

class ScanHit {
  const ScanHit({required this.id, required this.token, required this.rssi, required this.at});
  final String id;
  final String token;
  final int rssi;
  final DateTime at;
}

class SottoBle {
  SottoBle._();
  static final SottoBle instance = SottoBle._();

  static const _method = MethodChannel('dev.sotto/ble');
  static const _events = EventChannel('dev.sotto/ble/events');

  Stream<Map<String, dynamic>>? _stream;

  Stream<Map<String, dynamic>> get events => _stream ??= _events
      .receiveBroadcastStream()
      .map((e) => Map<String, dynamic>.from(e as Map))
      .asBroadcastStream();

  Stream<ScanHit> get scans => events.where((e) => e['type'] == 'scan').map(
        (e) => ScanHit(
          id: e['id'] as String,
          token: (e['token'] as String?) ?? '',
          rssi: (e['rssi'] as num).toInt(),
          at: DateTime.now(),
        ),
      );

  Stream<PeerMessage> get messages => events
      .where((e) => e['type'] == 'message')
      .map((e) => PeerMessage.parse(e['json'] as String))
      .where((m) => m != null)
      .cast<PeerMessage>();

  Stream<String> get errors =>
      events.where((e) => e['type'] == 'error').map((e) => e['message'] as String);

  Stream<void> get disconnections => events.where((e) => e['type'] == 'disconnected');

  Future<T> _call<T>(String method, [Map<String, dynamic>? args]) async {
    try {
      return await _method.invokeMethod<T>(method, args) as T;
    } on PlatformException catch (e) {
      throw BleException(e.message ?? e.code);
    } on MissingPluginException {
      throw BleException('この環境では BLE を使えません（Android 実機で動かしてください）');
    }
  }

  Future<bool> requestPermissions() => _call<bool>('requestPermissions');
  Future<bool> isBluetoothOn() => _call<bool>('isBluetoothOn');

  // 受け手
  Future<void> startDemand(String blob) => _call<void>('startDemand', {'blob': blob});
  Future<void> stopDemand() => _call<void>('stopDemand');
  Future<void> demandReply(PeerMessage m) => _call<void>('demandReply', {'json': m.encode()});
  Future<void> demandRelease() => _call<void>('demandRelease');

  // 譲る側
  Future<void> startScan() => _call<void>('startScan');
  Future<void> stopScan() => _call<void>('stopScan');
  Future<String> connect(String id) => _call<String>('connect', {'id': id});
  Future<void> write(PeerMessage m) => _call<void>('write', {'json': m.encode()});
  Future<void> disconnect() => _call<void>('disconnect');
}
