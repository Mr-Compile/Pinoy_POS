import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/services/ai_response_policy.dart';

/// Unit tests for the AI response sanitizer and validator.
///
/// These tests verify the exact inputs and outputs specified in the
/// humanized-AI response policy.
void main() {
  group('AiResponsePolicy', () {
    test('TEST 1: removes bold markers from sales summary', () {
      const input = '**Today\'s Sales**\n'
          '**Total:** ₱8,500\n'
          '**Transactions:** 32';
      const expected = 'Today\'s Sales\n'
          'Total: ₱8,500\n'
          'Transactions: 32';

      final result = AiResponsePolicy.sanitizeAndValidate(input);
      expect(result, expected);
      expect(AiResponsePolicy.isHumanized(result), isTrue);
    });

    test('TEST 2: removes heading and horizontal rule', () {
      const input = '## Sales Summary\n'
          '\n'
          '---\n'
          '\n'
          'Your sales today are ₱8,500.';
      const expected = 'Sales Summary\n'
          '\n'
          'Your sales today are ₱8,500.';

      final result = AiResponsePolicy.sanitizeAndValidate(input);
      expect(result, expected);
      expect(AiResponsePolicy.isHumanized(result), isTrue);
    });

    test('TEST 3: removes heading and bullet list markers', () {
      const input = '### Top Products\n'
          '- Chicken Adobo\n'
          '- Sinigang\n'
          '- Fried Chicken';
      const expected = 'Top Products\n'
          'Chicken Adobo\n'
          'Sinigang\n'
          'Fried Chicken';

      final result = AiResponsePolicy.sanitizeAndValidate(input);
      expect(result, expected);
      expect(AiResponsePolicy.isHumanized(result), isTrue);
    });

    test('TEST 4: does not remove legitimate hyphens in ranges', () {
      const input = 'Your sales increased from ₱5,000-₱7,000.';
      const expected = input;

      final result = AiResponsePolicy.sanitizeAndValidate(input);
      expect(result, expected);
      expect(AiResponsePolicy.isHumanized(result), isTrue);
    });

    test('TEST 5: preserves hyphens inside product names', () {
      const input = '**Chicken-Adobo** sold 15 units.';
      const expected = 'Chicken-Adobo sold 15 units.';

      final result = AiResponsePolicy.sanitizeAndValidate(input);
      expect(result, expected);
      expect(AiResponsePolicy.isHumanized(result), isTrue);
    });

    test('TEST 6: removes code fences while keeping content', () {
      const input = '```text\n'
          'Sales: ₱5,000\n'
          'Transactions: 20\n'
          '````';
      const expected = 'Sales: ₱5,000\n'
          'Transactions: 20';

      final result = AiResponsePolicy.sanitizeAndValidate(input);
      expect(result, expected);
      expect(AiResponsePolicy.isHumanized(result), isTrue);
    });

    test('TEST 7: removes bold around labels and values', () {
      const input = '**Summary:** Your sales are **₱5,000**.';
      const expected = 'Summary: Your sales are ₱5,000.';

      final result = AiResponsePolicy.sanitizeAndValidate(input);
      expect(result, expected);
      expect(AiResponsePolicy.isHumanized(result), isTrue);
    });

    test('TEST 8: removes multiple formatting markers in one response', () {
      const input = '## What needs attention?\n'
          '\n'
          '**GCash sales** are lower than yesterday.\n'
          '\n'
          '---\n'
          '\n'
          'You may want to check the payment records.';
      const expected = 'What needs attention?\n'
          '\n'
          'GCash sales are lower than yesterday.\n'
          '\n'
          'You may want to check the payment records.';

      final result = AiResponsePolicy.sanitizeAndValidate(input);
      expect(result, expected);
      expect(AiResponsePolicy.isHumanized(result), isTrue);
    });

    test('preserves currency, dates, product names, IDs and ranges', () {
      const input = 'Coke-Zero (INV-2026-001) sold 10-20 units on 2026-08-28. '
          'Negative value: -₱500. GCash payment accepted.';
      const expected = input;

      final result = AiResponsePolicy.sanitizeAndValidate(input);
      expect(result, expected);
      expect(AiResponsePolicy.isHumanized(result), isTrue);
    });

    test('removes italic markers', () {
      const input = 'Your *sales* are _growing_ this week.';
      const expected = 'Your sales are growing this week.';

      final result = AiResponsePolicy.sanitizeAndValidate(input);
      expect(result, expected);
      expect(AiResponsePolicy.isHumanized(result), isTrue);
    });

    test('removes strikethrough and inline backticks', () {
      const input = '~~Old total~~ is `₱5,000`.';
      const expected = 'Old total is ₱5,000.';

      final result = AiResponsePolicy.sanitizeAndValidate(input);
      expect(result, expected);
      expect(AiResponsePolicy.isHumanized(result), isTrue);
    });
  });
}
