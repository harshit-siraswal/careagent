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
      'This sign-in method is not available.',
    );
  });

  testWidgets('shows safety notice before the home shell', (tester) async {
    await tester.pumpWidget(
      CareAgentApp(
        authController: CareAgentAuthController.previewUnconfigured(),
        safetyNoticeStore: MemorySafetyNoticeStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CareAgent safety notice'), findsOneWidget);
    expect(find.text('CareAgent safety notice'), findsOneWidget);
    expect(find.text('I understand'), findsOneWidget);
  });

  testWidgets('opens login after safety acknowledgement', (tester) async {
    await tester.pumpWidget(
      CareAgentApp(
        authController: CareAgentAuthController.previewUnconfigured(),
        safetyNoticeStore: MemorySafetyNoticeStore(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('I understand'));
    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();

    expect(find.text('CareAgent safety notice'), findsNothing);
    expect(find.text('Sign in to CareAgent'), findsOneWidget);
    expect(find.text('Sign-in unavailable'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('keeps safety notice accepted after app restart', (tester) async {
    final store = MemorySafetyNoticeStore();

    await tester.pumpWidget(
      CareAgentApp(
        authController: CareAgentAuthController.previewUnconfigured(),
        safetyNoticeStore: store,
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('I understand'));
    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();

    expect(find.text('CareAgent safety notice'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      CareAgentApp(
        authController: CareAgentAuthController.previewUnconfigured(),
        safetyNoticeStore: store,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CareAgent safety notice'), findsNothing);
    expect(find.text('Sign in to CareAgent'), findsOneWidget);
  });

  testWidgets('navigates to core feature surfaces', (tester) async {
    await tester.pumpWidget(
      CareAgentApp(
        authController: CareAgentAuthController.previewSignedIn(
          email: 'patient@example.com',
        ),
        safetyNoticeStore: MemorySafetyNoticeStore(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('I understand'));
    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();

    expect(find.text('patient@example.com'), findsOneWidget);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(NavigationDrawerDestination, 'Consent'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Consent Center'), findsOneWidget);
    expect(find.text('Consent is separated by purpose'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.emergency_outlined).first);
    await tester.pumpAndSettle();
    expect(
      find.text('This screen does not call emergency services'),
      findsOneWidget,
    );
  });

  testWidgets('signed-in care features update local care state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      CareAgentApp(
        authController: CareAgentAuthController.previewSignedIn(
          email: 'patient@example.com',
        ),
        safetyNoticeStore: MemorySafetyNoticeStore(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('I understand'));
    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(NavigationDrawerDestination, 'Vitals'),
    );
    await tester.pumpAndSettle();
    expect(find.text('heart_rate: 132 bpm'), findsOneWidget);
    await tester.tap(find.text('Add Manual Reading'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDrawerDestination, 'Chat'));
    await tester.pumpAndSettle();
    final sendButton = find.text('Send');
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(sendButton);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('You: What is my latest vital?'),
      findsOneWidget,
    );
    expect(find.textContaining('Latest heart_rate is 132 bpm'), findsOneWidget);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDrawerDestination, 'SOS'));
    await tester.pumpAndSettle();
    final startSimulationButton = find.text('Start drill');
    await tester.ensureVisible(startSimulationButton);
    await tester.pumpAndSettle();
    await tester.tap(startSimulationButton);
    await tester.pumpAndSettle();
    expect(find.text('Drill started'), findsOneWidget);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(NavigationDrawerDestination, 'Alerts'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Heart rate needs review'), findsOneWidget);
    expect(
      find.text('Multi-channel escalation awaiting acknowledgement'),
      findsOneWidget,
    );
  });
}
