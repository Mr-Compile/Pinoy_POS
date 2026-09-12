import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/services/business_intelligence_service.dart';

/// A single advisor-usable skill loaded from `assets/Skill/**.md`.
///
/// Only the fields needed for routing and prompt injection are kept:
/// the frontmatter `name`, `description`, and `triggers`, plus a cleaned
/// excerpt of the body (code fences, file references, and agent-only
/// instructions are stripped).
class AdvisorSkill {
  final String name;
  final String path;
  final String description;
  final List<String> triggers;
  final String body;

  const AdvisorSkill({
    required this.name,
    required this.path,
    required this.description,
    required this.triggers,
    required this.body,
  });
}

/// Loads the curated skill set bundled under `assets/Skill/` and injects
/// the best-matching skill guidance into the AI Advisor's system prompt.
///
/// Design notes:
/// - The bundle contains 100+ skills written for coding/marketing agents.
///   Most are irrelevant (or actively harmful) for a POS business advisor,
///   so a strict allowlist decides which skills may be injected.
/// - At most [_maxInjectedSkills] skill bodies are injected per query:
///   one tone skill (always `stop-slop`) plus one domain skill selected
///   by the detected [BusinessIntent] and the user's role.
/// - Skill bodies are sanitized before injection: fenced code blocks,
///   references to external files, and agent-tool instructions are removed
///   so the model only sees transferable principles.
/// - If the asset bundle is unavailable (e.g. unit tests), every method
///   degrades gracefully and returns empty guidance.
class AISkillService {
  static const String _assetRoot = 'assets/Skill/';

  /// Maximum number of skill bodies injected into one prompt.
  static const int _maxInjectedSkills = 2;

  /// Per-skill body excerpt limit (keeps the prompt compact).
  static const int _maxBodyChars = 1400;

  /// Skills eligible for injection, keyed by skill `name` in frontmatter.
  ///
  /// - `stop-slop` — always-on humanized-writing tone for every role.
  /// - `analytics` — measurement/decision framing for owner sales data.
  /// - `marketing-psychology` — recommendation framing for owner advice.
  /// - `the-fool` — audit/critical-reasoning stance for anomaly answers.
  /// - `monitoring-expert` — health/alerting framing for admin intents.
  /// - `debugging-wizard` — root-cause framing for admin "what went
  ///   wrong" questions.
  static const Map<String, Set<UserRole>> _allowlist = {
    'stop-slop': {UserRole.owner, UserRole.admin, UserRole.staff},
    'analytics': {UserRole.owner, UserRole.staff},
    'marketing-psychology': {UserRole.owner},
    'the-fool': {UserRole.owner, UserRole.staff},
    'monitoring-expert': {UserRole.admin},
    'debugging-wizard': {UserRole.admin},
  };

  /// Asset path for each allowlisted skill name.
  static const Map<String, String> _allowlistPaths = {
    'stop-slop': '${_assetRoot}General/stop-slop.md',
    'analytics': '${_assetRoot}marketing/analytics.md',
    'marketing-psychology':
        '${_assetRoot}marketing/marketing-psychology.md',
    'the-fool': '${_assetRoot}fullstack/the-fool.md',
    'monitoring-expert': '${_assetRoot}fullstack/monitoring-expert.md',
    'debugging-wizard': '${_assetRoot}fullstack/debugging-wizard.md',
  };

  /// Intents where an audit/critical-reasoning stance fits best.
  static const Set<BusinessIntent> _auditIntents = {
    BusinessIntent.trendAnalysis,
    BusinessIntent.salesComparison,
    BusinessIntent.lowSellingProducts,
    BusinessIntent.businessSummary,
    BusinessIntent.myWorkSummary,
  };

  /// Intents where measurement/analytics framing fits best.
  static const Set<BusinessIntent> _analyticsIntents = {
    BusinessIntent.todaySales,
    BusinessIntent.yesterdaySales,
    BusinessIntent.dateRangeSales,
    BusinessIntent.weeklySales,
    BusinessIntent.monthlySales,
    BusinessIntent.topProducts,
    BusinessIntent.productPerformance,
    BusinessIntent.categoryPerformance,
    BusinessIntent.busiestPeriod,
    BusinessIntent.myTodaySales,
    BusinessIntent.myDateRangeSales,
    BusinessIntent.myRecentSales,
    BusinessIntent.myTopSoldProducts,
    BusinessIntent.myActivitySummary,
  };

  /// Intents where recommendation/psychology framing fits best.
  static const Set<BusinessIntent> _recommendationIntents = {
    BusinessIntent.lowStock,
    BusinessIntent.restockRecommendation,
    BusinessIntent.inventoryStatus,
    BusinessIntent.productInformation,
    BusinessIntent.categoryInformation,
  };

  /// Admin intents mapped to a monitoring/health framing.
  static const Set<BusinessIntent> _adminOpsIntents = {
    BusinessIntent.activeUserSummary,
    BusinessIntent.userStatusSummary,
    BusinessIntent.backupSummary,
    BusinessIntent.exportSummary,
    BusinessIntent.systemStatusSummary,
    BusinessIntent.adminSummary,
  };

  /// Admin intents mapped to root-cause/diagnostic framing.
  static const Set<BusinessIntent> _adminDiagnosticIntents = {
    BusinessIntent.systemActivitySummary,
    BusinessIntent.recentActivity,
  };

  Map<String, AdvisorSkill>? _index;
  Future<Map<String, AdvisorSkill>>? _loading;

  /// Creates the service. When [seededIndex] is provided, the asset
  /// bundle is never touched and [ensureLoaded] returns it directly —
  /// used by tests where `assets/Skill/` is not bundled.
  AISkillService({Map<String, AdvisorSkill>? seededIndex})
      : _index = seededIndex;

  /// Parses a skill markdown file into an [AdvisorSkill].
  ///
  /// Static and pure so it can be unit-tested without the asset bundle.
  static AdvisorSkill parseSkillFile(String path, String content) {
    var name = '';
    var description = '';
    final triggers = <String>[];

    // Frontmatter lives between the first two '---' lines.
    final fmMatch =
        RegExp(r'^---\s*\n(.*?)\n---\s*\n', dotAll: true).firstMatch(content);
    var body = content;
    if (fmMatch != null) {
      final fm = fmMatch.group(1)!;
      body = content.substring(fmMatch.end);
      for (final line in fm.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('name:')) {
          name = _unquote(trimmed.substring(5).trim());
        } else if (trimmed.startsWith('description:')) {
          description = _unquote(trimmed.substring(12).trim());
        } else if (trimmed.startsWith('triggers:') ||
            trimmed.startsWith('trigger:')) {
          final raw = trimmed.substring(trimmed.indexOf(':') + 1);
          triggers.addAll(raw
              .split(',')
              .map((t) => _unquote(t.trim()))
              .where((t) => t.isNotEmpty));
        }
      }
    }

    if (name.isEmpty) {
      // Fall back to the file name without extension.
      name = path.split('/').last.replaceAll(RegExp(r'\.md$'), '');
    }

    return AdvisorSkill(
      name: name,
      path: path,
      description: description,
      triggers: triggers,
      body: _cleanBody(body),
    );
  }

  /// Returns the names of skills selected for [query]/[intent]/[role],
  /// in injection order. Pure routing logic — unit-testable without the
  /// asset bundle.
  static List<String> selectSkillNames(
    String query,
    BusinessIntent intent,
    UserRole? role,
  ) {
    if (role == null) return const [];

    final selected = <String>['stop-slop'];
    final lowerQuery = query.toLowerCase();

    // Domain skill by intent.
    String? domain;
    if (role == UserRole.admin) {
      if (_adminDiagnosticIntents.contains(intent) ||
          lowerQuery.contains('why') ||
          lowerQuery.contains('wrong') ||
          lowerQuery.contains('unusual') ||
          lowerQuery.contains('failed')) {
        domain = 'debugging-wizard';
      } else if (_adminOpsIntents.contains(intent)) {
        domain = 'monitoring-expert';
      }
    } else {
      if (_auditIntents.contains(intent) ||
          lowerQuery.contains('why') ||
          lowerQuery.contains('unusual') ||
          lowerQuery.contains('dropped') ||
          lowerQuery.contains('audit')) {
        domain = 'the-fool';
      } else if (_analyticsIntents.contains(intent)) {
        domain = 'analytics';
      } else if (_recommendationIntents.contains(intent) &&
          role == UserRole.owner) {
        domain = 'marketing-psychology';
      }
    }

    if (domain != null && (_allowlist[domain]?.contains(role) ?? false)) {
      selected.add(domain);
    }

    return selected.take(_maxInjectedSkills).toList();
  }

  /// Loads (once) the allowlisted skills from the asset bundle.
  Future<Map<String, AdvisorSkill>> ensureLoaded() {
    if (_index != null) return Future.value(_index);
    return _loading ??= _loadIndex().then((idx) => _index = idx);
  }

  /// Builds the `SKILL GUIDANCE:` block for the system prompt.
  ///
  /// Returns an empty string when no skills match or the bundle is
  /// unavailable — the prompt remains valid without it.
  Future<String> buildGuidance(
    String query,
    BusinessIntent intent,
    UserRole? role,
  ) async {
    try {
      final index = await ensureLoaded();
      if (index.isEmpty) return '';

      final names = selectSkillNames(query, intent, role);
      final skills = names
          .map((n) => index[n])
          .whereType<AdvisorSkill>()
          .take(_maxInjectedSkills)
          .toList();
      if (skills.isEmpty) return '';

      final buf = StringBuffer();
      buf.writeln('SKILL GUIDANCE (apply these principles to HOW you '
          'reason and write; ignore any mention of tools, files, or code '
          'execution — you cannot use them):');
      for (final skill in skills) {
        buf.writeln('');
        buf.writeln('[Skill: ${skill.name}]');
        buf.writeln(skill.body.length > _maxBodyChars
            ? skill.body.substring(0, _maxBodyChars)
            : skill.body);
      }
      return buf.toString().trim();
    } catch (e) {
      _log('buildGuidance failed: $e');
      return '';
    }
  }

  /// Resets the cached index. Intended for tests.
  @visibleForTesting
  void reset() {
    _index = null;
    _loading = null;
  }

  // ── Internals ────────────────────────────────────────────────────────

  Future<Map<String, AdvisorSkill>> _loadIndex() async {
    final index = <String, AdvisorSkill>{};
    for (final entry in _allowlistPaths.entries) {
      try {
        final content = await rootBundle.loadString(entry.value);
        index[entry.key] = parseSkillFile(entry.value, content);
      } catch (e) {
        _log('Skill "${entry.key}" unavailable at ${entry.value}: $e');
      }
    }
    _log('Skill index loaded: ${index.keys.join(', ')}');
    return index;
  }

  /// Removes agent-only material from a skill body: fenced code blocks,
  /// references to auxiliary files, and mentions of agent tools. Keeps
  /// prose principles the model can apply directly.
  static String _cleanBody(String body) {
    final lines = body.split('\n');
    final kept = <String>[];
    var inFence = false;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
        inFence = !inFence;
        continue;
      }
      if (inFence) continue;
      if (trimmed.contains('references/') ||
          trimmed.contains('AskUserQuestion') ||
          trimmed.contains('.agents/') ||
          trimmed.contains('.claude/') ||
          trimmed.contains('rootBundle')) {
        continue;
      }
      kept.add(line);
    }

    return kept
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static String _unquote(String value) {
    if (value.length >= 2) {
      final first = value[0];
      final last = value[value.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        return value.substring(1, value.length - 1);
      }
    }
    return value;
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[AISkillService] $message');
    }
  }
}
