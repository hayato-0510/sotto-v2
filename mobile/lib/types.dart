/// AI サーバとの契約（lib/types.ts・lib/contracts.ts と同じ形）。
/// **変更時は TypeScript 側も直す**（設計書 §4）。
///
/// 疾患名・障害名・氏名・顔写真・位置情報はいずれの型にも持たせない（AGENTS.md §3）。
library;

/// 混雑度。UI の3択（空いている／混んでいる／ぎゅうぎゅう）を
/// サーバの4値のうち 空いている／混雑／超満員 に対応させる（設計書 §3.3）。「普通」は UI から出さない。
enum Crowding {
  empty('空いている', '空いている'),
  crowded('混雑', '混んでいる'),
  packed('超満員', 'ぎゅうぎゅう');

  const Crowding(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

class Needs {
  const Needs({
    required this.posture,
    required this.needsSupport,
    required this.timeSensitive,
    required this.luggage,
    required this.avoid,
    required this.summary,
    required this.confidence,
    this.isFallback = false,
  });

  final String posture;
  final bool needsSupport;
  final bool timeSensitive;
  final String luggage;
  final List<String> avoid;

  /// 本人が読んで確認するための一文。他人には見せない
  final String summary;
  final String confidence;

  /// 生成に失敗して固定文で代替した場合 true。画面で明示する（FR-12）
  final bool isFallback;

  factory Needs.fromJson(Map<String, dynamic> j) => Needs(
        posture: j['posture'] as String,
        needsSupport: j['needsSupport'] as bool,
        timeSensitive: j['timeSensitive'] as bool,
        luggage: j['luggage'] as String,
        avoid: (j['avoid'] as List<dynamic>).cast<String>(),
        summary: j['summary'] as String,
        confidence: j['confidence'] as String,
        isFallback: j['isFallback'] == true,
      );

  Map<String, dynamic> toJson() => {
        'posture': posture,
        'needsSupport': needsSupport,
        'timeSensitive': timeSensitive,
        'luggage': luggage,
        'avoid': avoid,
        'summary': summary,
        'confidence': confidence,
        if (isFallback) 'isFallback': true,
      };
}

class Handoff {
  const Handoff({
    required this.request,
    required this.action,
    required this.reason,
    required this.seconds,
    required this.physicalLoad,
    this.isFallback = false,
  });

  final String request;

  /// 譲る側の動作。発話を含まないことはサーバ側で検証済み（FR-12）
  final String action;
  final String reason;
  final int seconds;
  final String physicalLoad;
  final bool isFallback;

  factory Handoff.fromJson(Map<String, dynamic> j) => Handoff(
        request: j['request'] as String,
        action: j['action'] as String,
        reason: j['reason'] as String,
        seconds: (j['seconds'] as num).toInt(),
        physicalLoad: j['physicalLoad'] as String,
        isFallback: j['isFallback'] == true,
      );

  Map<String, dynamic> toJson() => {
        'request': request,
        'action': action,
        'reason': reason,
        'seconds': seconds,
        'physicalLoad': physicalLoad,
        if (isFallback) 'isFallback': true,
      };
}
