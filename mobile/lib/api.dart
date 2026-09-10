/// AI サーバ（Next.js Route Handler）の呼び出し。API キーはサーバにしか無い（AGENTS.md §1）。
///
/// 接続先はビルド時に差し替えられる：
///   flutter build apk --dart-define=SOTTO_API_BASE=https://example.vercel.app
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'types.dart';

const String apiBase = String.fromEnvironment(
  'SOTTO_API_BASE',
  defaultValue: 'https://sotto-v2.vercel.app',
);

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SottoApi {
  SottoApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  /// 生成の待ち時間。サーバ側のタイムアウト（20秒＋1回リトライ）より長く取る
  static const _timeout = Duration(seconds: 45);

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('$apiBase$path'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } catch (e) {
      throw ApiException('サーバに接続できません（$apiBase）');
    }
    if (res.statusCode != 200) {
      throw ApiException('サーバがエラーを返しました（${res.statusCode}）');
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  /// ステップ1：状態テキスト → Needs
  Future<Needs> extractNeeds(String text) async =>
      Needs.fromJson(await _post('/api/needs', {'text': text}));

  /// 需要の宣言：Needs を封緘して受け取る。端末はこの封緘を BLE で譲る側へ渡す
  Future<String> sealDemand(Needs needs) async {
    final j = await _post('/api/demands', {'needs': needs.toJson()});
    return j['blob'] as String;
  }

  /// ステップ2：封緘 ＋ 混雑度 → Handoff
  Future<Handoff> generateHandoff(String blob, Crowding crowding) async =>
      Handoff.fromJson(await _post('/api/handoff', {'blob': blob, 'crowding': crowding.apiValue}));
}
