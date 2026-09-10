/// 端末に保存する本人の設定。役割と、受け手の需要の中身の2つだけ。
///
/// 席を必要とする人（高齢・妊娠など）も、席を空けたい人も、その立場は乗るたびに変わらない。
/// 毎回選ばせず、一度選んだら設定で変えるまで維持する。
///
/// **発信の状態は保存しない。** 保存した需要があっても、発信は毎回本人が
/// ［ これで発信する ］を押して始める。開いただけで発信が始まると「隠れて発信しない」
/// （AGENTS.md §4）に反し、その日は席が要らない人のために誰かが立つことになる。
///
/// 需要の中身は本人の端末のアプリ専用領域にだけ置き、ここから外へは送らない。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'types.dart';

/// いまの立場。「譲る／譲られる」は施す側と施される側を作るので使わない。
/// 両方とも動作で書き、アプリを開いた時点で意思はあるものとして扱う
enum Role {
  seeker('席をさがす'),
  giver('席を空ける');

  const Role(this.label);
  final String label;
}

class Profile extends ChangeNotifier {
  Profile._(this._prefs) {
    _role = _readRole();
    _needs = _readNeeds();
  }

  static const roleKey = 'sotto.role';
  static const needsKey = 'sotto.needs';

  static Future<Profile> load() async => Profile._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;
  Role? _role;
  Needs? _needs;

  Role? get role => _role;
  Needs? get needs => _needs;

  Future<void> setRole(Role role) async {
    _role = role;
    await _prefs.setString(roleKey, role.name);
    notifyListeners();
  }

  Future<void> setNeeds(Needs needs) async {
    _needs = needs;
    await _prefs.setString(needsKey, jsonEncode(needs.toJson()));
    notifyListeners();
  }

  Future<void> clearNeeds() async {
    _needs = null;
    await _prefs.remove(needsKey);
    notifyListeners();
  }

  // 保存値が壊れていても起動は止めない。無いものとして最初から選び直してもらう
  Role? _readRole() {
    final name = _prefs.getString(roleKey);
    return Role.values.where((r) => r.name == name).firstOrNull;
  }

  Needs? _readNeeds() {
    final raw = _prefs.getString(needsKey);
    if (raw == null) return null;
    try {
      return Needs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
