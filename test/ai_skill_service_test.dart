import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/services/ai_skill_service.dart';
import 'package:pinoy_pos/services/business_intelligence_service.dart';

void main() {
  group('AISkillService.parseSkillFile', () {
    const sample = '''---
name: stop-slop
description: Remove AI writing patterns from prose.
metadata:
  trigger: Writing prose, editing drafts
---

# Stop Slop

Eliminate predictable AI writing patterns from prose.

## Core Rules

1. **Cut filler phrases.** Remove throat-clearing openers.
2. See [references/phrases.md](references/phrases.md) for details.

```dart
final x = 1;
```

Use `AskUserQuestion` to pick a mode.
''';

    test('extracts name, description and triggers from frontmatter', () {
      final skill = AISkillService.parseSkillFile(
        'assets/Skill/General/stop-slop.md',
        sample,
      );
      expect(skill.name, 'stop-slop');
      expect(skill.description, contains('AI writing patterns'));
      expect(skill.triggers, contains('Writing prose'));
      expect(skill.triggers, contains('editing drafts'));
    });

    test('body strips code fences and agent-only references', () {
      final skill = AISkillService.parseSkillFile(
        'assets/Skill/General/stop-slop.md',
        sample,
      );
      expect(skill.body, contains('Cut filler phrases'));
      expect(skill.body, isNot(contains('final x = 1')));
      expect(skill.body, isNot(contains('references/')));
      expect(skill.body, isNot(contains('AskUserQuestion')));
    });

    test('falls back to file name when frontmatter has no name', () {
      final skill = AISkillService.parseSkillFile(
        'assets/Skill/marketing/pricing.md',
        '# Pricing\n\nNo frontmatter here.',
      );
      expect(skill.name, 'pricing');
    });

    test('handles file with no frontmatter at all', () {
      final skill = AISkillService.parseSkillFile(
        'assets/Skill/General/x.md',
        'Just a plain body.',
      );
      expect(skill.body, contains('Just a plain body.'));
    });
  });

  group('AISkillService.selectSkillNames', () {
    test('always includes the stop-slop tone skill for all roles', () {
      for (final role in UserRole.values) {
        final names = AISkillService.selectSkillNames(
          'hello',
          BusinessIntent.general,
          role,
        );
        expect(names.first, 'stop-slop');
      }
    });

    test('owner sales intents route to analytics', () {
      final names = AISkillService.selectSkillNames(
        'how are my sales today',
        BusinessIntent.todaySales,
        UserRole.owner,
      );
      expect(names, contains('analytics'));
    });

    test('audit-style questions route to the-fool', () {
      final names = AISkillService.selectSkillNames(
        'why did sales drop',
        BusinessIntent.trendAnalysis,
        UserRole.owner,
      );
      expect(names, contains('the-fool'));
    });

    test('restock questions route to marketing-psychology for owner', () {
      final names = AISkillService.selectSkillNames(
        'what should i restock',
        BusinessIntent.restockRecommendation,
        UserRole.owner,
      );
      expect(names, contains('marketing-psychology'));
    });

    test('admin ops intents route to monitoring-expert', () {
      final names = AISkillService.selectSkillNames(
        'show me system status',
        BusinessIntent.systemStatusSummary,
        UserRole.admin,
      );
      expect(names, contains('monitoring-expert'));
    });

    test('admin diagnostic questions route to debugging-wizard', () {
      final names = AISkillService.selectSkillNames(
        'any unusual failed activity',
        BusinessIntent.recentActivity,
        UserRole.admin,
      );
      expect(names, contains('debugging-wizard'));
    });

    test('staff never gets admin or owner-only skills', () {
      final names = AISkillService.selectSkillNames(
        'what should i restock',
        BusinessIntent.restockRecommendation,
        UserRole.staff,
      );
      expect(names, isNot(contains('marketing-psychology')));
      expect(names, isNot(contains('monitoring-expert')));
      expect(names, isNot(contains('debugging-wizard')));
    });

    test('null role returns no skills', () {
      expect(
        AISkillService.selectSkillNames('hi', BusinessIntent.general, null),
        isEmpty,
      );
    });

    test('never injects more than two skills', () {
      final names = AISkillService.selectSkillNames(
        'why are sales unusual today',
        BusinessIntent.trendAnalysis,
        UserRole.owner,
      );
      expect(names.length, lessThanOrEqualTo(2));
    });
  });
}
