import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';

/// A rule that locks a character's behavior boundaries to prevent
/// persona drift / cross-contamination between AI characters.
class PersonaRule {
  final String characterId;
  final double yanderePossession;
  final double socialAnxiety;
  final double extroversion;
  final double aggressionCap;
  final double warmthFloor;
  final double trustCeiling;
  final double restraintFloor;
  final List<String> behaviorBoundary;
  final Map<String, bool> socialPermissions;
  final DateTime lastUpdatedAt;

  const PersonaRule({
    required this.characterId,
    required this.yanderePossession,
    required this.socialAnxiety,
    required this.extroversion,
    required this.aggressionCap,
    required this.warmthFloor,
    required this.trustCeiling,
    required this.restraintFloor,
    required this.behaviorBoundary,
    required this.socialPermissions,
    required this.lastUpdatedAt,
  });

  Map<String, dynamic> toJson() => {
        'characterId': characterId,
        'yanderePossession': yanderePossession,
        'socialAnxiety': socialAnxiety,
        'extroversion': extroversion,
        'aggressionCap': aggressionCap,
        'warmthFloor': warmthFloor,
        'trustCeiling': trustCeiling,
        'restraintFloor': restraintFloor,
        'behaviorBoundary': behaviorBoundary,
        'socialPermissions': socialPermissions,
        'lastUpdatedAt': lastUpdatedAt.millisecondsSinceEpoch,
      };

  factory PersonaRule.fromJson(Map<String, dynamic> json) => PersonaRule(
        characterId: json['characterId'] as String,
        yanderePossession: (json['yanderePossession'] as num).toDouble(),
        socialAnxiety: (json['socialAnxiety'] as num).toDouble(),
        extroversion: (json['extroversion'] as num).toDouble(),
        aggressionCap: (json['aggressionCap'] as num).toDouble(),
        warmthFloor: (json['warmthFloor'] as num).toDouble(),
        trustCeiling: (json['trustCeiling'] as num).toDouble(),
        restraintFloor: (json['restraintFloor'] as num).toDouble(),
        behaviorBoundary:
            (json['behaviorBoundary'] as List<dynamic>).cast<String>(),
        socialPermissions:
            (json['socialPermissions'] as Map<String, dynamic>).cast<String, bool>(),
        lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(
            json['lastUpdatedAt'] as int),
      );
}

/// Registry that manages global persona rules for all AI characters.
///
/// Instantiated by CoreHub — NOT a singleton.
/// Persists rules to [SharedPreferences] under [PrefKeys.coreHubPersonaRules].
class PersonaRuleRegistry {
  final SharedPreferences _prefs;
  final Map<String, PersonaRule> _rules = {};

  PersonaRuleRegistry(this._prefs);

  /// Loads all persisted rules from SharedPreferences.
  Future<void> init() async {
    await _restore();
  }

  /// Returns the rule for [characterId], or `null` if none exists.
  PersonaRule? getRule(String characterId) => _rules[characterId];

  /// Upserts a rule and persists the entire registry.
  Future<void> setRule(PersonaRule rule) async {
    _rules[rule.characterId] = rule;
    await persist();
  }

  /// Deletes the rule for [characterId] and persists.
  Future<void> removeRule(String characterId) async {
    _rules.remove(characterId);
    await persist();
  }

  /// All currently registered rules.
  List<PersonaRule> get allRules => _rules.values.toList();

  /// Whether a specific social [action] is allowed for [characterId].
  ///
  /// Returns `false` if no rule exists or the action is not in the
  /// permissions map.
  bool isActionAllowed(String characterId, String action) {
    final rule = _rules[characterId];
    if (rule == null) return false;
    return rule.socialPermissions[action] ?? false;
  }

  /// Creates an initial [PersonaRule] from an AICharacter's data.
  ///
  /// Maps personality traits to behavioral thresholds and reads the
  /// `currentAnchor` JSON (aggressiveness, warmth, restraint, trust)
  /// to set boundary caps/floors. Social permissions default to all
  /// disabled; behavior boundary defaults to empty.
  PersonaRule generateFromCharacter(Map<String, dynamic> characterData) {
    final characterId = characterData['id'] as String;
    final personality = (characterData['personality'] as String?) ?? '';

    // Derive personality-trait thresholds from the personality text.
    final yanderePossession = _extractTrait(personality, [
      '病娇', '占有', '偏执', '独占',
    ]);
    final socialAnxiety = _extractTrait(personality, [
      '社恐', '内向', '回避', '孤僻', '害羞',
    ]);
    final extroversion = _extractTrait(personality, [
      '外向', '主动', '热情', '开朗', '健谈',
    ]);

    // Read currentAnchor dimensions with safe defaults.
    double anchorAggressiveness = 0.5;
    double anchorWarmth = 0.5;
    double anchorRestraint = 0.5;
    double anchorTrust = 0.5;

    final anchorJson = characterData['currentAnchor'] as String?;
    if (anchorJson != null && anchorJson.isNotEmpty) {
      try {
        final map = jsonDecode(anchorJson) as Map<String, dynamic>;
        anchorAggressiveness =
            (map['aggressiveness'] as num?)?.toDouble() ?? 0.5;
        anchorWarmth = (map['warmth'] as num?)?.toDouble() ?? 0.5;
        anchorRestraint = (map['restraint'] as num?)?.toDouble() ?? 0.5;
        anchorTrust = (map['trust'] as num?)?.toDouble() ?? 0.5;
      } catch (e) {
        debugPrint('PersonaRuleRegistry: failed to parse currentAnchor — $e');
      }
    }

    return PersonaRule(
      characterId: characterId,
      yanderePossession: yanderePossession,
      socialAnxiety: socialAnxiety,
      extroversion: extroversion,
      aggressionCap: anchorAggressiveness,
      warmthFloor: anchorWarmth,
      trustCeiling: anchorTrust,
      restraintFloor: anchorRestraint,
      behaviorBoundary: const [],
      socialPermissions: const {
        'social_visit': true,
        'social_friend_request': true,
        'social_private_chat': true,
        'social_moment': true,
        'social_moment_comment': true,
        'social_moment_like': true,
        'social_daily_activity': true,
      },
      lastUpdatedAt: DateTime.now(),
    );
  }

  /// Persists all rules to SharedPreferences.
  Future<void> persist() async {
    final encoded = _rules.map(
      (key, rule) => MapEntry(key, rule.toJson()),
    );
    await _prefs.setString(
      PrefKeys.coreHubPersonaRules,
      jsonEncode(encoded),
    );
  }

  /// Restores rules from SharedPreferences.
  Future<void> _restore() async {
    final raw = _prefs.getString(PrefKeys.coreHubPersonaRules);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _rules.clear();
      for (final entry in map.entries) {
        _rules[entry.key] =
            PersonaRule.fromJson(entry.value as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('PersonaRuleRegistry: restore failed — $e');
    }
  }

  /// Scans [text] for keywords and returns a 0.0–1.0 score.
  ///
  /// Returns 0.0 when none of the [keywords] appear, 0.7 when one
  /// matches, and 1.0 when two or more match.
  double _extractTrait(String text, List<String> keywords) {
    var hits = 0;
    for (final kw in keywords) {
      if (text.contains(kw)) hits++;
    }
    if (hits >= 2) return 1.0;
    if (hits == 1) return 0.7;
    return 0.0;
  }
}
