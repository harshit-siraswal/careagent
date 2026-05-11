import 'package:careagent/main.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps disabled Firebase provider auth error to setup guidance', () {
    expect(
      careAgentAuthErrorMessage(
        firebase_auth.FirebaseAuthException(code: 'operation-not-allowed'),
      ),
      'This sign-in method is not enabled in Firebase Auth.',
    );
  });

  testWidgets('shows safety notice before the home shell', (tester) async {
    await tester.pumpWidget(
      CareAgentApp(
        authController: CareAgentAuthController.previewUnconfigured(),
      ),
    );

    expect(find.text('CareAgent safety notice'), findsOneWidget);
    expect(find.text('CareAgent MVP Shell'), findsNothing);
    expect(find.text('I understand'), findsOneWidget);
  });

  testWidgets('opens login after safety acknowledgement', (tester) async {
    await tester.pumpWidget(
      CareAgentApp(
        authController: CareAgentAuthController.previewUnconfigured(),
      ),
    );

    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();

    expect(find.text('CareAgent safety notice'), findsNothing);
    expect(find.text('Sign in to CareAgent'), findsOneWidget);
    expect(find.text('Firebase configuration required'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('navigates to core placeholder surfaces', (tester) async {
    await tester.pumpWidget(
      CareAgentApp(
        authController: CareAgentAuthController.previewSignedIn(
          email: 'patient@example.com',
        ),
      ),
    );
    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();

    expect(find.text('patient@example.com'), findsOneWidget);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consent'));
    await tester.pumpAndSettle();
    expect(find.text('Consent Center'), findsOneWidget);
    expect(find.text('No consent has been granted'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.emergency_outlined).first);
    await tester.pumpAndSettle();
    expect(
      find.text('This screen does not call emergency services'),
      findsOneWidget,
    );
  });
}
