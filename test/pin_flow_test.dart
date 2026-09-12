import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/core/session_status.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/ui/screens/settings/set_pin_screen.dart';
import 'package:pinoy_pos/ui/widgets/pin_indicators.dart';
import 'package:pinoy_pos/ui/widgets/pin_keypad.dart';

class _FakeAuthService extends AuthService {
  String? lastPin;
  bool updateResult = true;

  @override
  Future<SessionStatus> restoreSession() async => SessionStatus.active;

  @override
  Future<bool> updateProfile({
    required int userId,
    required String fullName,
    String? username,
    String? pin,
    String? profileImagePath,
  }) async {
    lastPin = pin;
    final current = SessionManager().currentUser;
    if (current != null && pin != null && pin.isNotEmpty) {
      SessionManager().setCurrentUser(
        current.copyWith(pin: pin, pinLength: pin.length),
      );
    }
    return updateResult;
  }
}

Future<void> _pumpKeypad(
  WidgetTester tester, {
  ValueChanged<String>? onDigit,
  VoidCallback? onBackspace,
  VoidCallback? onNext,
  bool nextEnabled = false,
  bool enabled = true,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: PinKeypad(
            onDigitPressed: onDigit ?? (_) {},
            onBackspacePressed: onBackspace ?? () {},
            onNextPressed: onNext,
            nextEnabled: nextEnabled,
            enabled: enabled,
          ),
        ),
      ),
    ),
  );
}

Future<void> _tapDigits(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.text(d));
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PinKeypad', () {
    testWidgets('renders circular digit keys with letter hints',
        (tester) async {
      await _pumpKeypad(tester);

      for (var i = 0; i <= 9; i++) {
        expect(find.text('$i'), findsOneWidget);
      }
      for (final letters
          in ['ABC', 'DEF', 'GHI', 'JKL', 'MNO', 'PQRS', 'TUV', 'WXYZ']) {
        expect(find.text(letters), findsOneWidget);
      }
      expect(find.byIcon(Icons.backspace_outlined), findsOneWidget);
    });

    testWidgets('digit tap calls onDigitPressed', (tester) async {
      String? tapped;
      await _pumpKeypad(tester, onDigit: (d) => tapped = d);

      await tester.tap(find.text('5'));
      await tester.pump();
      expect(tapped, '5');
    });

    testWidgets('backspace tap calls onBackspacePressed', (tester) async {
      var tapped = false;
      await _pumpKeypad(tester, onBackspace: () => tapped = true);

      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('no check key when onNextPressed is null', (tester) async {
      await _pumpKeypad(tester);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
    });

    testWidgets('check key ignores taps while nextEnabled is false',
        (tester) async {
      var tapped = false;
      await _pumpKeypad(tester, onNext: () => tapped = true);

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();
      expect(tapped, isFalse);
    });

    testWidgets('check key calls onNextPressed when enabled',
        (tester) async {
      var tapped = false;
      await _pumpKeypad(
        tester,
        onNext: () => tapped = true,
        nextEnabled: true,
      );

      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('keys are inert when disabled', (tester) async {
      String? tapped;
      var backspaced = false;
      await _pumpKeypad(
        tester,
        onDigit: (d) => tapped = d,
        onBackspace: () => backspaced = true,
        enabled: false,
      );

      await tester.tap(find.text('7'));
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();
      expect(tapped, isNull);
      expect(backspaced, isFalse);
    });
  });

  group('PinIndicators', () {
    testWidgets('renders filled dots for entered digits, rings for empty',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PinIndicators(pinLength: 4, enteredCount: 2),
          ),
        ),
      );

      final containers =
          tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer));
      expect(containers.length, 4);
      final colors = containers.map(
        (c) => (c.decoration as BoxDecoration).color,
      );
      expect(colors.where((c) => c != Colors.transparent).length, 2);
      expect(colors.where((c) => c == Colors.transparent).length, 2);
    });

    testWidgets('error state colors filled dots with the error color',
        (tester) async {
      late ColorScheme cs;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              cs = Theme.of(context).colorScheme;
              return const Scaffold(
                body: PinIndicators(
                  pinLength: 4,
                  enteredCount: 4,
                  error: true,
                ),
              );
            },
          ),
        ),
      );

      final containers =
          tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer));
      for (final c in containers) {
        expect((c.decoration as BoxDecoration).color, cs.error);
      }
    });

    testWidgets('shake() runs the shake animation without errors',
        (tester) async {
      final key = GlobalKey<PinIndicatorsState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PinIndicators(
              key: key,
              pinLength: 4,
              enteredCount: 4,
              error: true,
            ),
          ),
        ),
      );

      key.currentState!.shake();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });
  });

  group('SetPinScreen', () {
    late _FakeAuthService fakeAuth;

    final testUser = User(
      id: 1,
      username: 'juan',
      passwordHash: 'test-hash',
      role: UserRole.staff,
      fullName: 'Juan Dela Cruz',
      createdAt: DateTime(2026, 1, 1),
    );

    setUp(() {
      SessionManager.resetForTest();
      SessionManager().setCurrentUser(testUser);
      fakeAuth = _FakeAuthService();
    });

    tearDown(() {
      SessionManager.resetForTest();
    });

    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWith((ref) => fakeAuth),
          ],
          child: const MaterialApp(home: SetPinScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('create → confirm saves the PIN', (tester) async {
      await pumpScreen(tester);

      // Step 1 — create. Check key stays inert below 4 digits.
      expect(find.text('Create your PIN'), findsOneWidget);
      expect(find.text('Step 1 of 2 — Create'), findsOneWidget);
      await _tapDigits(tester, '12');
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();
      expect(find.text('Create your PIN'), findsOneWidget);

      await _tapDigits(tester, '34');
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();

      // Step 2 — confirm with the same PIN.
      expect(find.text('Confirm your PIN'), findsOneWidget);
      expect(find.text('Step 2 of 2 — Confirm'), findsOneWidget);
      await _tapDigits(tester, '1234');
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(fakeAuth.lastPin, '1234');
      expect(find.text('PIN Updated'), findsOneWidget);
    });

    testWidgets('mismatched confirm shakes and restarts at step 1',
        (tester) async {
      await pumpScreen(tester);

      await _tapDigits(tester, '1234');
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();
      expect(find.text('Confirm your PIN'), findsOneWidget);

      await _tapDigits(tester, '9999');
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();

      expect(find.text('PINs didn\'t match — start over'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();

      expect(find.text('Create your PIN'), findsOneWidget);
      expect(find.text('Step 1 of 2 — Create'), findsOneWidget);
      expect(fakeAuth.lastPin, isNull);
    });

    testWidgets('entry is capped at 6 digits', (tester) async {
      await pumpScreen(tester);
      await _tapDigits(tester, '1234567');

      final containers = tester.widgetList<AnimatedContainer>(
        find.descendant(
          of: find.byType(PinIndicators),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(
        containers
            .where(
                (c) => (c.decoration as BoxDecoration).color != Colors.transparent)
            .length,
        6,
      );
    });
  });
}
