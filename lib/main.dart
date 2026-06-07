import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_config.dart';
import 'config/firebase_options.dart';
import 'core/careagent_api.dart';
import 'design_system/care_motion.dart';
import 'design_system/care_theme.dart';
import 'mascot/caro_companion.dart';
import 'mascot/caro_state.dart';

/// Current safety notice copy version stored after acknowledgement.
const String careAgentSafetyNoticeVersion = 'pilot-v1';

/// Demo and sandbox controls stay out of normal patient/caretaker screens.
const bool careAgentShowDemoTools = bool.fromEnvironment(
  'CAREAGENT_SHOW_DEMO_TOOLS',
);

bool get _careAgentRunningInWidgetTest {
  var running = false;
  assert(() {
    running = WidgetsBinding.instance.runtimeType.toString().contains(
      'AutomatedTest',
    );
    return true;
  }());
  return running;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(CareAgentApp(authController: await CareAgentAuthController.create()));
}

/// Authentication state shown by the app shell.
enum CareAgentAuthStatus {
  unconfigured,
  signedOut,
  signingIn,
  signedIn,
  needsEmailVerification,
  error,
}

/// User-facing account type selected before authentication.
enum CareAgentUserRole {
  patient,
  caretaker;

  String get wireName => switch (this) {
    CareAgentUserRole.patient => 'patient',
    CareAgentUserRole.caretaker => 'caretaker',
  };

  String get label => switch (this) {
    CareAgentUserRole.patient => 'Patient',
    CareAgentUserRole.caretaker => 'Caretaker',
  };

  String get loginTitle => switch (this) {
    CareAgentUserRole.patient => 'Patient login',
    CareAgentUserRole.caretaker => 'Caretaker login',
  };

  String get loginSubtitle => switch (this) {
    CareAgentUserRole.patient =>
      'For daily medicines, vitals, records, Caro chat, and emergency policy.',
    CareAgentUserRole.caretaker =>
      'For patient queues, urgent alerts, acknowledgements, and care-team coordination.',
  };

  String get dashboardTitle => switch (this) {
    CareAgentUserRole.patient => 'Care status',
    CareAgentUserRole.caretaker => 'Caretaker command',
  };

  String get companionTitle => switch (this) {
    CareAgentUserRole.patient => 'Caro keeps your care day organized',
    CareAgentUserRole.caretaker => 'Caro triages what needs your attention',
  };

  IconData get icon => switch (this) {
    CareAgentUserRole.patient => Icons.favorite_outline,
    CareAgentUserRole.caretaker => Icons.volunteer_activism_outlined,
  };
}

/// Persists the selected account type between app launches.
abstract final class CareAgentRolePreferences {
  static const _roleKey = 'careagent.login_role';

  static Future<CareAgentUserRole> load() async {
    final preferences = await SharedPreferences.getInstance();
    final wireName = preferences.getString(_roleKey);
    return CareAgentUserRole.values.firstWhere(
      (role) => role.wireName == wireName,
      orElse: () => CareAgentUserRole.patient,
    );
  }

  static Future<void> save(CareAgentUserRole role) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_roleKey, role.wireName);
  }
}

/// Persists whether the current safety notice version was acknowledged.
abstract class SafetyNoticeStore {
  /// Returns whether [version] has already been accepted.
  Future<bool> isAccepted({String version = careAgentSafetyNoticeVersion});

  /// Stores acceptance for [version].
  Future<void> accept({String version = careAgentSafetyNoticeVersion});
}

/// Safety notice store backed by platform preferences.
class SharedPreferencesSafetyNoticeStore implements SafetyNoticeStore {
  /// Creates a shared-preferences backed safety notice store.
  const SharedPreferencesSafetyNoticeStore();

  static const _acceptedVersionKey = 'careagent.safety_notice.accepted_version';
  static const _acceptedAtKey = 'careagent.safety_notice.accepted_at';

  @override
  Future<bool> isAccepted({
    String version = careAgentSafetyNoticeVersion,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_acceptedVersionKey) == version;
  }

  @override
  Future<void> accept({String version = careAgentSafetyNoticeVersion}) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_acceptedVersionKey, version);
    await preferences.setString(
      _acceptedAtKey,
      DateTime.now().toUtc().toIso8601String(),
    );
  }
}

/// In-memory safety notice store for tests and previews.
class MemorySafetyNoticeStore implements SafetyNoticeStore {
  /// Creates an in-memory safety notice store.
  MemorySafetyNoticeStore({bool accepted = false})
    : _acceptedVersion = accepted ? careAgentSafetyNoticeVersion : null;

  String? _acceptedVersion;

  @override
  Future<bool> isAccepted({
    String version = careAgentSafetyNoticeVersion,
  }) async {
    return _acceptedVersion == version;
  }

  @override
  Future<void> accept({String version = careAgentSafetyNoticeVersion}) async {
    _acceptedVersion = version;
  }
}

/// Small Firebase Auth wrapper used by the Flutter shell.
class CareAgentAuthController extends ChangeNotifier {
  /// Creates a controller after initializing Firebase for the current platform.
  static Future<CareAgentAuthController> create() async {
    try {
      if (kIsWeb) {
        if (!DefaultFirebaseOptions.hasRequiredWebOptions) {
          return CareAgentAuthController.previewUnconfigured(
            message: 'Sign-in is not ready on this app build.',
          );
        }
        await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
      } else {
        await Firebase.initializeApp();
      }

      return CareAgentAuthController.firebase();
    } catch (error) {
      return CareAgentAuthController.previewUnconfigured(
        message: careAgentAuthErrorMessage(error),
      );
    }
  }

  /// Creates an auth controller backed by Firebase Auth.
  CareAgentAuthController.firebase()
    : _auth = firebase_auth.FirebaseAuth.instance,
      _googleSignIn = kIsWeb
          ? null
          : GoogleSignIn(scopes: const <String>['email', 'profile']) {
    final auth = _auth!;
    _applyUser(auth.currentUser);
    _subscription = auth.authStateChanges().listen((user) {
      _applyUser(user);
      notifyListeners();
    });
  }

  CareAgentAuthController._preview({
    required CareAgentAuthStatus status,
    String? email,
    String? errorMessage,
  }) : _auth = null,
       _googleSignIn = null,
       _status = status,
       _userEmail = email,
       _errorMessage = errorMessage;

  /// Creates a deterministic signed-in controller for widget tests.
  CareAgentAuthController.previewSignedIn({String? email})
    : this._preview(status: CareAgentAuthStatus.signedIn, email: email);

  /// Creates a deterministic unconfigured controller for widget tests.
  CareAgentAuthController.previewUnconfigured({String? message})
    : this._preview(
        status: CareAgentAuthStatus.unconfigured,
        errorMessage: message,
      );

  final firebase_auth.FirebaseAuth? _auth;
  final GoogleSignIn? _googleSignIn;
  StreamSubscription<firebase_auth.User?>? _subscription;
  CareAgentAuthStatus _status = CareAgentAuthStatus.signedOut;
  String? _userEmail;
  String? _errorMessage;

  /// Current auth state.
  CareAgentAuthStatus get status => _status;

  /// Whether Firebase Auth is ready for user actions.
  bool get isConfigured => _auth != null;

  /// Signed-in user's email when Firebase exposes it.
  String? get userEmail => _userEmail;

  /// Last safe user-facing auth error.
  String? get errorMessage => _errorMessage;

  /// Starts Google sign-in through Firebase Auth.
  Future<void> signInWithGoogle() async {
    final auth = _auth;
    if (auth == null) {
      _setUnconfiguredError();
      return;
    }

    _status = CareAgentAuthStatus.signingIn;
    _errorMessage = null;
    notifyListeners();

    try {
      if (kIsWeb) {
        final provider = firebase_auth.GoogleAuthProvider()
          ..addScope('email')
          ..addScope('profile');
        final credential = await auth.signInWithPopup(provider);
        _applyUser(credential.user);
      } else {
        final googleSignIn = _googleSignIn;
        if (googleSignIn == null) {
          throw StateError('Google sign-in is not available on this platform.');
        }

        final googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          _status = CareAgentAuthStatus.signedOut;
          _errorMessage = 'Google sign-in was cancelled.';
          notifyListeners();
          return;
        }

        final googleAuth = await googleUser.authentication;
        final credential = firebase_auth.GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        final userCredential = await auth.signInWithCredential(credential);
        _applyUser(userCredential.user);
      }
    } catch (error) {
      _status = CareAgentAuthStatus.error;
      _errorMessage = careAgentAuthErrorMessage(error);
    }

    notifyListeners();
  }

  /// Signs in with a Firebase email/password account.
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final auth = _auth;
    if (auth == null) {
      _setUnconfiguredError();
      return;
    }

    _status = CareAgentAuthStatus.signingIn;
    _errorMessage = null;
    notifyListeners();

    try {
      final credential = await auth.signInWithEmailAndPassword(
        email: _normalizeEmail(email),
        password: password,
      );
      _applyUser(credential.user);
    } catch (error) {
      _status = CareAgentAuthStatus.error;
      _errorMessage = careAgentAuthErrorMessage(error);
    }

    notifyListeners();
  }

  /// Creates a Firebase email/password account and sends verification email.
  Future<void> createAccountWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final auth = _auth;
    if (auth == null) {
      _setUnconfiguredError();
      return;
    }

    _status = CareAgentAuthStatus.signingIn;
    _errorMessage = null;
    notifyListeners();

    try {
      final credential = await auth.createUserWithEmailAndPassword(
        email: _normalizeEmail(email),
        password: password,
      );
      final user = credential.user;
      final normalizedName = displayName.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (user != null && normalizedName.isNotEmpty) {
        await user.updateDisplayName(normalizedName);
      }
      await user?.sendEmailVerification();
      _applyUser(auth.currentUser ?? user);
    } catch (error) {
      _status = CareAgentAuthStatus.error;
      _errorMessage = careAgentAuthErrorMessage(error);
    }

    notifyListeners();
  }

  /// Sends a Firebase password reset email.
  Future<void> sendPasswordResetEmail(String email) async {
    final auth = _auth;
    if (auth == null) {
      _setUnconfiguredError();
      return;
    }

    await auth.sendPasswordResetEmail(email: _normalizeEmail(email));
  }

  /// Sends another verification email for the current Firebase user.
  Future<void> resendVerificationEmail() async {
    final user = _auth?.currentUser;
    if (user == null) {
      _status = CareAgentAuthStatus.signedOut;
      _errorMessage = 'Please sign in before requesting verification email.';
      notifyListeners();
      return;
    }

    await user.sendEmailVerification();
  }

  /// Returns a fresh Firebase ID token for backend API calls.
  Future<String?> idToken() async => _auth?.currentUser?.getIdToken();

  /// Reloads the Firebase user and returns whether email verification passed.
  Future<bool> refreshEmailVerification() async {
    final auth = _auth;
    final user = auth?.currentUser;
    if (user == null) {
      _status = CareAgentAuthStatus.signedOut;
      _userEmail = null;
      _errorMessage = 'Please sign in again.';
      notifyListeners();
      return false;
    }

    await user.reload();
    _applyUser(auth!.currentUser);
    notifyListeners();
    return _status == CareAgentAuthStatus.signedIn;
  }

  /// Signs out of Firebase Auth and Google Sign-In.
  Future<void> signOut() async {
    try {
      if (!kIsWeb) {
        try {
          await _googleSignIn?.signOut();
        } catch (_) {
          // Firebase remains the source of truth for session teardown.
        }
      }
      await _auth?.signOut();
      _applyUser(null);
    } catch (error) {
      _status = CareAgentAuthStatus.error;
      _errorMessage = careAgentAuthErrorMessage(error);
    }

    notifyListeners();
  }

  bool _requiresEmailVerification(firebase_auth.User user) {
    final hasPasswordProvider = user.providerData.any(
      (provider) => provider.providerId == 'password',
    );
    return hasPasswordProvider && !user.emailVerified;
  }

  void _applyUser(firebase_auth.User? user) {
    if (user == null) {
      _status = CareAgentAuthStatus.signedOut;
      _userEmail = null;
      return;
    }

    _userEmail = user.email;
    _status = _requiresEmailVerification(user)
        ? CareAgentAuthStatus.needsEmailVerification
        : CareAgentAuthStatus.signedIn;
    _errorMessage = null;
  }

  void _setUnconfiguredError() {
    _status = CareAgentAuthStatus.unconfigured;
    _errorMessage = 'Sign-in is not ready on this app build.';
    notifyListeners();
  }

  String _normalizeEmail(String email) => email.trim().toLowerCase();

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// Returns a safe message for Firebase Auth failures shown in the login UI.
String careAgentAuthErrorMessage(Object error) {
  if (error is firebase_auth.FirebaseAuthException) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'Email is already registered.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'weak-password':
        return 'Password must be at least 12 characters and include upper-case, lower-case, and a number.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'operation-not-allowed':
        return 'This sign-in method is not available.';
      default:
        final message = error.message?.trim();
        return message == null || message.isEmpty
            ? 'Authentication failed.'
            : message;
    }
  }

  if (error is PlatformException) {
    final message = '${error.code} ${error.message ?? ''}'.toLowerCase();
    if (_looksLikeGoogleConfigIssue(message)) {
      return 'Google sign-in is not ready for this app build.';
    }
    if (message.contains('sign_in_canceled') || message.contains('canceled')) {
      return 'Google sign-in was cancelled.';
    }
    return error.message ?? 'Google sign-in failed.';
  }

  final message = error.toString().replaceFirst('Exception: ', '').trim();
  if (_looksLikeGoogleConfigIssue(message.toLowerCase())) {
    return 'Google sign-in is not ready for this app build.';
  }
  return message.isEmpty ? 'Authentication failed.' : message;
}

bool _looksLikeGoogleConfigIssue(String message) {
  return message.contains('developer_error') ||
      message.contains('status code 10') ||
      message.contains('configuration');
}

/// Root widget for the Android-first CareAgent MVP shell.
class CareAgentApp extends StatelessWidget {
  /// Creates the CareAgent application.
  CareAgentApp({
    required this.authController,
    CareAgentApiClient? apiClient,
    SafetyNoticeStore? safetyNoticeStore,
    super.key,
  }) : apiClient =
           apiClient ??
           CareAgentApiClient(
             config: AppConfig.fromEnvironment(),
             idTokenProvider: authController.idToken,
           ),
       safetyNoticeStore =
           safetyNoticeStore ?? const SharedPreferencesSafetyNoticeStore();

  /// Auth controller used to gate the protected app shell.
  final CareAgentAuthController authController;

  /// Backend API client used by pilot flows.
  final CareAgentApiClient apiClient;

  /// Store used to persist safety notice acknowledgement.
  final SafetyNoticeStore safetyNoticeStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CareAgent',
      debugShowCheckedModeBanner: false,
      theme: CareTheme.light(),
      darkTheme: CareTheme.dark(),
      themeMode: ThemeMode.system,
      home: _SafetyGate(
        authController: authController,
        apiClient: apiClient,
        safetyNoticeStore: safetyNoticeStore,
      ),
    );
  }
}

class _SafetyGate extends StatefulWidget {
  const _SafetyGate({
    required this.authController,
    required this.apiClient,
    required this.safetyNoticeStore,
  });

  final CareAgentAuthController authController;
  final CareAgentApiClient apiClient;
  final SafetyNoticeStore safetyNoticeStore;

  @override
  State<_SafetyGate> createState() => _SafetyGateState();
}

class _SafetyGateState extends State<_SafetyGate> {
  bool _loadingSafetyNotice = true;
  bool _acceptedSafetyNotice = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSafetyNotice());
  }

  Future<void> _loadSafetyNotice() async {
    var accepted = false;
    try {
      accepted = await widget.safetyNoticeStore.isAccepted();
    } catch (_) {
      accepted = false;
    }
    if (!mounted) return;
    setState(() {
      _acceptedSafetyNotice = accepted;
      _loadingSafetyNotice = false;
    });
  }

  Future<void> _acceptSafetyNotice() async {
    if (!mounted) return;
    setState(() {
      _acceptedSafetyNotice = true;
    });
    try {
      await widget.safetyNoticeStore.accept();
    } catch (_) {
      // Acceptance should not trap users on the notice if persistence is
      // temporarily unavailable in a browser or embedded preview.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingSafetyNotice) {
      return const _SafetyNoticeLoadingScreen();
    }

    return AnimatedSwitcher(
      duration: CareMotion.guided,
      switchInCurve: CareMotion.guidedCurve,
      switchOutCurve: CareMotion.quickCurve,
      child: _acceptedSafetyNotice
          ? _AuthGate(
              key: const ValueKey('auth-gate'),
              authController: widget.authController,
              apiClient: widget.apiClient,
            )
          : _SafetyNoticeScreen(
              key: const ValueKey('safety-notice'),
              onAccepted: () => unawaited(_acceptSafetyNotice()),
            ),
    );
  }
}

class _SafetyNoticeLoadingScreen extends StatelessWidget {
  const _SafetyNoticeLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const _PremiumStage(
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate({
    required this.authController,
    required this.apiClient,
    super.key,
  });

  final CareAgentAuthController authController;
  final CareAgentApiClient apiClient;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  CareAgentUserRole _selectedRole = CareAgentUserRole.patient;

  @override
  void initState() {
    super.initState();
    widget.apiClient.careAgentRole = _selectedRole.wireName;
    unawaited(_loadRole());
  }

  Future<void> _loadRole() async {
    final role = await CareAgentRolePreferences.load();
    if (!mounted) return;
    _applyRole(role, persist: false);
  }

  void _applyRole(CareAgentUserRole role, {bool persist = true}) {
    widget.apiClient.careAgentRole = role.wireName;
    setState(() {
      _selectedRole = role;
    });
    if (persist) {
      unawaited(CareAgentRolePreferences.save(role));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.authController,
      builder: (context, _) {
        if (widget.authController.status == CareAgentAuthStatus.signedIn) {
          return _CareAgentShell(
            apiClient: widget.apiClient,
            loginRole: _selectedRole,
            userEmail: widget.authController.userEmail,
            onSignOut: widget.authController.signOut,
          );
        }

        return _LoginScreen(
          authController: widget.authController,
          selectedRole: _selectedRole,
          onRoleChanged: _applyRole,
        );
      },
    );
  }
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen({
    required this.authController,
    required this.selectedRole,
    required this.onRoleChanged,
  });

  final CareAgentAuthController authController;
  final CareAgentUserRole selectedRole;
  final ValueChanged<CareAgentUserRole> onRoleChanged;

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isLogin = true;
  bool _obscurePassword = true;
  bool _isResettingPassword = false;
  bool _isResendingVerification = false;
  bool _isCheckingVerification = false;

  CareAgentAuthController get authController => widget.authController;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isLogin = !_isLogin;
      _formKey.currentState?.reset();
    });
  }

  Future<void> _signInWithGoogle() async {
    await authController.signInWithGoogle();
    if (!mounted) return;
    final message = authController.errorMessage;
    if (message != null &&
        authController.status != CareAgentAuthStatus.signedIn &&
        authController.status != CareAgentAuthStatus.needsEmailVerification) {
      _showError(message);
    }
  }

  Future<void> _submitEmail() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isLogin) {
      await authController.signInWithEmail(
        email: _emailController.text,
        password: _passwordController.text,
      );
    } else {
      await authController.createAccountWithEmail(
        email: _emailController.text,
        password: _passwordController.text,
        displayName: _nameController.text,
      );
    }

    if (!mounted) return;
    final message = authController.errorMessage;
    if (message != null && authController.status == CareAgentAuthStatus.error) {
      _showError(message);
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showError('Enter your email address first.');
      return;
    }

    setState(() => _isResettingPassword = true);
    try {
      await authController.sendPasswordResetEmail(email);
      if (mounted) {
        _showSuccess('Password reset email sent.');
      }
    } catch (error) {
      if (mounted) {
        _showError(careAgentAuthErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isResettingPassword = false);
      }
    }
  }

  Future<void> _resendVerificationEmail() async {
    setState(() => _isResendingVerification = true);
    try {
      await authController.resendVerificationEmail();
      if (mounted) {
        _showSuccess('Verification email sent.');
      }
    } catch (error) {
      if (mounted) {
        _showError(careAgentAuthErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isResendingVerification = false);
      }
    }
  }

  Future<void> _checkEmailVerification() async {
    setState(() => _isCheckingVerification = true);
    try {
      final verified = await authController.refreshEmailVerification();
      if (mounted && !verified) {
        _showError('Email is not verified yet.');
      }
    } catch (error) {
      if (mounted) {
        _showError(careAgentAuthErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingVerification = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email.';
    final emailPattern = RegExp(
      r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
    );
    if (!emailPattern.hasMatch(email)) return 'Enter a valid email.';
    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Enter your password.';
    if (password.length > 128) return 'Password is too long.';
    if (!_isLogin) {
      final hasUppercase = RegExp(r'[A-Z]').hasMatch(password);
      final hasLowercase = RegExp(r'[a-z]').hasMatch(password);
      final hasDigit = RegExp(r'\d').hasMatch(password);
      if (password.length < 12 || !hasUppercase || !hasLowercase || !hasDigit) {
        return 'Use 12+ chars with upper-case, lower-case, and a number.';
      }
    }
    return null;
  }

  String? _validateName(String? value) {
    final normalized = value?.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
    if (normalized.isEmpty) return 'Enter your name.';
    if (normalized.length < 2) return 'Name must be at least 2 characters.';
    if (normalized.length > 80) return 'Name must be 80 characters or fewer.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (authController.status == CareAgentAuthStatus.needsEmailVerification) {
      return _buildEmailVerificationScreen();
    }

    final isConfigured = authController.isConfigured;
    final isSigningIn = authController.status == CareAgentAuthStatus.signingIn;
    final isBusy = isSigningIn || _isResettingPassword;
    final role = widget.selectedRole;

    return _PremiumStage(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            final horizontal = wide ? 40.0 : 18.0;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: _LoginHeroPanel(role: role)),
                            const SizedBox(width: 28),
                            SizedBox(
                              width: 520,
                              child: _GlassPanel(
                                child: _buildLoginForm(
                                  context,
                                  role: role,
                                  isConfigured: isConfigured,
                                  isSigningIn: isSigningIn,
                                  isBusy: isBusy,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _LoginHeroPanel(role: role, compact: true),
                            const SizedBox(height: 18),
                            _GlassPanel(
                              child: _buildLoginForm(
                                context,
                                role: role,
                                isConfigured: isConfigured,
                                isSigningIn: isSigningIn,
                                isBusy: isBusy,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoginForm(
    BuildContext context, {
    required CareAgentUserRole role,
    required bool isConfigured,
    required bool isSigningIn,
    required bool isBusy,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RoleSelector(
          selectedRole: role,
          onChanged: isBusy ? null : widget.onRoleChanged,
        ),
        const SizedBox(height: 22),
        Text(
          'Sign in to CareAgent',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        Text(role.loginTitle, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 10),
        Text(role.loginSubtitle, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 20),
        if (!isConfigured)
          _SafetyBanner(
            title: 'Sign-in unavailable',
            message:
                'CareAgent sign-in is not ready on this build. Please use a configured app build.',
          ),
        if (authController.errorMessage != null) ...[
          const SizedBox(height: 12),
          _SafetyBanner(
            title: 'Sign-in issue',
            message: authController.errorMessage!,
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: isConfigured && !isBusy ? _signInWithGoogle : null,
            icon: isSigningIn
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: Text(isSigningIn ? 'Signing in' : 'Continue with Google'),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or use email', style: theme.textTheme.bodySmall),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 20),
        Form(
          key: _formKey,
          child: Column(
            children: [
              if (!_isLogin) ...[
                _LoginTextField(
                  controller: _nameController,
                  label: 'Full name',
                  icon: Icons.person_outline,
                  validator: _validateName,
                  enabled: isConfigured && !isBusy,
                ),
                const SizedBox(height: 12),
              ],
              _LoginTextField(
                controller: _emailController,
                label: 'Email',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: _validateEmail,
                enabled: isConfigured && !isBusy,
              ),
              const SizedBox(height: 12),
              _LoginTextField(
                controller: _passwordController,
                label: 'Password',
                icon: Icons.lock_outline,
                obscureText: _obscurePassword,
                validator: _validatePassword,
                enabled: isConfigured && !isBusy,
                suffix: IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  onPressed: isBusy
                      ? null
                      : () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              if (_isLogin)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: isConfigured && !isBusy
                        ? _sendPasswordReset
                        : null,
                    child: const Text('Forgot password?'),
                  ),
                )
              else
                const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isConfigured && !isBusy ? _submitEmail : null,
                  child: Text(_isLogin ? 'Sign in' : 'Create account'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: isBusy ? null : _toggleMode,
            child: Text(
              _isLogin
                  ? 'Create a new account'
                  : 'Sign in to an existing account',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailVerificationScreen() {
    final theme = Theme.of(context);
    final email = authController.userEmail ?? _emailController.text.trim();
    final isBusy = _isCheckingVerification || _isResendingVerification;

    return _PremiumStage(
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: _GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CaroCompanion(
                      state: CaroState.concerned,
                      title: 'One more step before health workflows',
                      message:
                          'Email verification protects access before records, '
                          'consent, and care-team actions become available.',
                    ),
                    const SizedBox(height: 24),
                    Icon(
                      Icons.mark_email_read_outlined,
                      size: 56,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Verify your email',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Open the verification link sent to $email, then return '
                      'to CareAgent.',
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 20),
                    _SafetyBanner(
                      title: 'Email verification required',
                      message:
                          'Email/password accounts must be verified before '
                          'CareAgent unlocks protected health workflows.',
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: isBusy ? null : _checkEmailVerification,
                        icon: _isCheckingVerification
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.verified_outlined),
                        label: const Text('I verified my email'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: isBusy ? null : _resendVerificationEmail,
                        icon: _isResendingVerification
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.outgoing_mail),
                        label: const Text('Resend email'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        onPressed: isBusy ? null : authController.signOut,
                        child: const Text('Use a different account'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PremiumStage extends StatelessWidget {
  const _PremiumStage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: _PremiumBackdrop(child: child));
  }
}

class _PremiumBackdrop extends StatefulWidget {
  const _PremiumBackdrop({required this.child});

  final Widget child;

  @override
  State<_PremiumBackdrop> createState() => _PremiumBackdropState();
}

class _PremiumBackdropState extends State<_PremiumBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
    if (!_careAgentRunningInWidgetTest) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if ((reduceMotion || _careAgentRunningInWidgetTest) &&
        _controller.isAnimating) {
      _controller.stop();
    } else if (!reduceMotion &&
        !_careAgentRunningInWidgetTest &&
        !_controller.isAnimating) {
      _controller.repeat();
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _CareBackdropPainter(
            progress: reduceMotion ? 0 : _controller.value,
            dark: Theme.of(context).brightness == Brightness.dark,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _CareBackdropPainter extends CustomPainter {
  const _CareBackdropPainter({required this.progress, required this.dark});

  final double progress;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, size.height),
        dark
            ? const [Color(0xFF071817), Color(0xFF101A28)]
            : const [Color(0xFFF9FDFF), Color(0xFFEFF6F8)],
      );
    canvas.drawRect(rect, base);

    _paintRibbon(
      canvas,
      size,
      y: size.height * 0.18,
      height: size.height * 0.22,
      color: dark ? const Color(0xFF1D4E5B) : const Color(0xFFBFEAF0),
      phase: progress,
      alpha: dark ? 0.34 : 0.52,
    );
    _paintRibbon(
      canvas,
      size,
      y: size.height * 0.62,
      height: size.height * 0.18,
      color: dark ? const Color(0xFF533D61) : const Color(0xFFE6D8FF),
      phase: progress + 0.34,
      alpha: dark ? 0.24 : 0.42,
    );
    _paintRibbon(
      canvas,
      size,
      y: size.height * 0.82,
      height: size.height * 0.16,
      color: dark ? const Color(0xFF5C2630) : const Color(0xFFFFD9DF),
      phase: progress + 0.62,
      alpha: dark ? 0.22 : 0.36,
    );

    final linePaint = Paint()
      ..color = (dark ? Colors.white : const Color(0xFF2E4750)).withValues(
        alpha: dark ? 0.035 : 0.045,
      )
      ..strokeWidth = 1;
    for (var x = -size.height; x < size.width; x += 54) {
      canvas.drawLine(
        Offset(x.toDouble(), size.height),
        Offset(x + size.height * 0.62, 0),
        linePaint,
      );
    }
  }

  void _paintRibbon(
    Canvas canvas,
    Size size, {
    required double y,
    required double height,
    required Color color,
    required double phase,
    required double alpha,
  }) {
    final wave = math.sin(phase * math.pi * 2) * 18;
    final path = Path()
      ..moveTo(-40, y + wave)
      ..cubicTo(
        size.width * 0.25,
        y - height * 0.42,
        size.width * 0.62,
        y + height * 0.42,
        size.width + 40,
        y - wave,
      )
      ..lineTo(size.width + 40, y + height)
      ..cubicTo(
        size.width * 0.68,
        y + height * 1.24,
        size.width * 0.26,
        y + height * 0.58,
        -40,
        y + height * 0.96,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: alpha));
  }

  @override
  bool shouldRepaint(covariant _CareBackdropPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.dark != dark;
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(28)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: (dark ? const Color(0xFF172321) : Colors.white).withValues(
              alpha: dark ? 0.70 : 0.74,
            ),
            borderRadius: const BorderRadius.all(Radius.circular(28)),
            border: Border.all(
              color: (dark ? Colors.white : const Color(0xFF31565D)).withValues(
                alpha: dark ? 0.08 : 0.11,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.24 : 0.08),
                blurRadius: 36,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _RoleSelector extends StatelessWidget {
  const _RoleSelector({required this.selectedRole, required this.onChanged});

  final CareAgentUserRole selectedRole;
  final ValueChanged<CareAgentUserRole>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Choose account type',
      child: Row(
        children: [
          for (final role in CareAgentUserRole.values) ...[
            Expanded(
              child: _RoleChoiceCard(
                role: role,
                selected: role == selectedRole,
                onTap: onChanged == null ? null : () => onChanged!(role),
              ),
            ),
            if (role != CareAgentUserRole.values.last)
              const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

class _RoleChoiceCard extends StatelessWidget {
  const _RoleChoiceCard({
    required this.role,
    required this.selected,
    required this.onTap,
  });

  final CareAgentUserRole role;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.56);

    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(18)),
      child: AnimatedContainer(
        duration: CareMotion.standard,
        curve: CareMotion.standardCurve,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : theme.colorScheme.surface.withValues(alpha: 0.56),
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.55),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(role.icon, color: color),
            const SizedBox(height: 10),
            Text(
              role.label,
              style: theme.textTheme.titleSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginHeroPanel extends StatelessWidget {
  const _LoginHeroPanel({required this.role, this.compact = false});

  final CareAgentUserRole role;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caroState = role == CareAgentUserRole.caretaker
        ? CaroState.handoff
        : CaroState.greeting;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 0 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: compact ? Alignment.center : Alignment.centerLeft,
            child: Hero(
              tag: 'caro-login-character',
              child: CaroCharacter(state: caroState, size: compact ? 116 : 176),
            ),
          ),
          SizedBox(height: compact ? 10 : 18),
          Text(
            role.companionTitle,
            style: theme.textTheme.displayLarge?.copyWith(
              fontSize: compact ? 28 : 38,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            role == CareAgentUserRole.patient
                ? 'Medicines, vitals, records, and safe escalation in one calm workspace.'
                : 'A focused queue for alerts, evidence, calls, and acknowledgements.',
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.66),
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.50),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: theme.colorScheme.primary),
            const SizedBox(width: 7),
            Text(label, style: theme.textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}

class _LiveSignalBadge extends StatefulWidget {
  const _LiveSignalBadge();

  @override
  State<_LiveSignalBadge> createState() => _LiveSignalBadgeState();
}

class _LiveSignalBadgeState extends State<_LiveSignalBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (!_careAgentRunningInWidgetTest) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if ((reduceMotion || _careAgentRunningInWidgetTest) &&
        _controller.isAnimating) {
      _controller.stop();
    } else if (!reduceMotion &&
        !_careAgentRunningInWidgetTest &&
        !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = reduceMotion ? 0.0 : _controller.value;
        return Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.10),
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(
                alpha: 0.20 + value * 0.20,
              ),
            ),
          ),
          child: Icon(
            Icons.monitor_heart_outlined,
            color: theme.colorScheme.primary.withValues(
              alpha: 0.72 + value * 0.28,
            ),
          ),
        );
      },
    );
  }
}

class _LoginTextField extends StatelessWidget {
  const _LoginTextField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.enabled,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool enabled;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: suffix,
      ),
    );
  }
}

class _SafetyNoticeScreen extends StatelessWidget {
  const _SafetyNoticeScreen({required this.onAccepted, super.key});

  final VoidCallback onAccepted;

  @override
  Widget build(BuildContext context) {
    return _PremiumStage(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 920;
            final horizontal = wide ? 48.0 : 24.0;

            if (wide) {
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontal,
                  vertical: 24,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Expanded(child: _SafetyIdentityPanel()),
                        const SizedBox(width: 56),
                        SizedBox(
                          width: 520,
                          child: _SafetyNoticeContent(onAccepted: onAccepted),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: horizontal,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _SafetyIdentityPanel(compact: true),
                        const SizedBox(height: 28),
                        _SafetyNoticeContent(onAccepted: onAccepted),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SafetyIdentityPanel extends StatelessWidget {
  const _SafetyIdentityPanel({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CaroCompanion(
          state: CaroState.greeting,
          title: 'Caro is your care guide',
          message:
              'I will help you understand setup, consent, health records, '
              'and emergency drills without replacing a clinician.',
          compact: compact,
        ),
        if (!compact) ...[
          const SizedBox(height: 32),
          Text(
            'Soft, guided care coordination.',
            style: theme.textTheme.displayLarge,
          ),
          const SizedBox(height: 12),
          Text(
            'CareAgent keeps health workflows understandable: what is known, '
            'what is stale, what is consented, and what safe next step is '
            'available.',
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ],
    );
  }
}

class _SafetyNoticeContent extends StatelessWidget {
  const _SafetyNoticeContent({required this.onAccepted});

  final VoidCallback onAccepted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _GlassPanel(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.health_and_safety_outlined,
            size: 48,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 20),
          Text('CareAgent safety notice', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          Text(
            'CareAgent is a health coordination shell for reminders, records, '
            'consent, and care-team workflows. It does not diagnose, '
            'prescribe, or replace a clinician.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          Text(
            'In an emergency or for severe symptoms, contact local emergency '
            'services or a qualified medical professional directly. '
            'Escalation, calls, messages, and location sharing must be '
            'explicitly configured before use.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onAccepted,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('I understand'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CareAgentShell extends StatefulWidget {
  const _CareAgentShell({
    required this.apiClient,
    required this.loginRole,
    required this.userEmail,
    required this.onSignOut,
  });

  final CareAgentApiClient apiClient;
  final CareAgentUserRole loginRole;
  final String? userEmail;
  final Future<void> Function() onSignOut;

  @override
  State<_CareAgentShell> createState() => _CareAgentShellState();
}

class _CareAgentShellState extends State<_CareAgentShell> {
  late int _selectedIndex;
  late final _LocalCareState _localCareState;

  _Section get _selectedSection => _sections[_selectedIndex];

  @override
  void initState() {
    super.initState();
    _selectedIndex = 0;
    widget.apiClient.careAgentRole = widget.loginRole.wireName;
    _localCareState = _LocalCareState();
  }

  @override
  void didUpdateWidget(covariant _CareAgentShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.apiClient.careAgentRole = widget.loginRole.wireName;
  }

  @override
  void dispose() {
    _localCareState.dispose();
    super.dispose();
  }

  void _selectSection(int index) {
    setState(() {
      _selectedIndex = index;
    });
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final selectedSection = _selectedSection;
    final width = MediaQuery.sizeOf(context).width;
    final useBottomTabs = width < 720;
    final showUserIdentity = width >= 720;
    final compactFab = width < 480;
    final bottomTabs = _bottomTabsForRole(widget.loginRole);
    final body = AnimatedSwitcher(
      duration: CareMotion.guided,
      switchInCurve: CareMotion.guidedCurve,
      child: _selectedIndex == 0
          ? _HomeScreen(
              key: ValueKey('home-${widget.loginRole.wireName}'),
              apiClient: widget.apiClient,
              loginRole: widget.loginRole,
              localCareState: _localCareState,
              onSelectSection: _selectSection,
            )
          : _CareFeatureScreen(
              key: ValueKey(selectedSection.title),
              section: selectedSection,
              careState: _localCareState,
            ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          _selectedIndex == 0
              ? widget.loginRole.dashboardTitle
              : selectedSection.title,
        ),
        actions: [
          if (showUserIdentity)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Text(
                  widget.userEmail ?? 'Signed in',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      drawer: NavigationDrawer(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectSection,
        children: [
          _DrawerHeader(role: widget.loginRole, userEmail: widget.userEmail),
          for (final section in _sections)
            NavigationDrawerDestination(
              icon: Icon(section.icon),
              selectedIcon: Icon(section.selectedIcon),
              label: Text(section.title),
            ),
        ],
      ),
      body: _PremiumBackdrop(
        child: Padding(
          padding: EdgeInsets.only(bottom: useBottomTabs ? 94 : 0),
          child: body,
        ),
      ),
      bottomNavigationBar: useBottomTabs
          ? _CareBottomTabBar(
              selectedSectionIndex: _selectedIndex,
              tabs: bottomTabs,
              onSelected: _selectSection,
            )
          : null,
      floatingActionButton: useBottomTabs || _selectedIndex == _sosIndex
          ? null
          : compactFab
          ? FloatingActionButton(
              tooltip: 'SOS',
              onPressed: () => _selectSection(_sosIndex),
              child: const Icon(Icons.emergency_outlined),
            )
          : FloatingActionButton.extended(
              onPressed: () => _selectSection(_sosIndex),
              icon: const Icon(Icons.emergency_outlined),
              label: const Text('SOS'),
            ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.role, required this.userEmail});

  final CareAgentUserRole role;
  final String? userEmail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CaroCharacter(state: CaroState.neutral, size: 68),
          const SizedBox(height: 12),
          Text(
            'CareAgent',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text('${role.label} workspace', style: theme.textTheme.bodyMedium),
          if (userEmail != null) ...[
            const SizedBox(height: 8),
            Text(
              userEmail!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _CareBottomTabBar extends StatelessWidget {
  const _CareBottomTabBar({
    required this.selectedSectionIndex,
    required this.tabs,
    required this.onSelected,
  });

  final int selectedSectionIndex;
  final List<_BottomTab> tabs;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(28)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: (dark ? const Color(0xFF13211F) : Colors.white)
                    .withValues(alpha: dark ? 0.78 : 0.84),
                borderRadius: const BorderRadius.all(Radius.circular(28)),
                border: Border.all(
                  color: (dark ? Colors.white : const Color(0xFF2B585B))
                      .withValues(alpha: dark ? 0.10 : 0.13),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.30 : 0.12),
                    blurRadius: 30,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    for (final tab in tabs)
                      Expanded(
                        child: _CareBottomTabButton(
                          tab: tab,
                          selected: tab.sectionIndex == selectedSectionIndex,
                          onTap: () => onSelected(tab.sectionIndex),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CareBottomTabButton extends StatelessWidget {
  const _CareBottomTabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _BottomTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final foreground = selected ? primary : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      selected: selected,
      button: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(22)),
          onTap: onTap,
          child: AnimatedContainer(
            duration: CareMotion.standard,
            curve: CareMotion.guidedCurve,
            constraints: const BoxConstraints(minHeight: 58),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: const BorderRadius.all(Radius.circular(22)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: selected ? 1.08 : 1,
                  duration: CareMotion.standard,
                  curve: CareMotion.guidedCurve,
                  child: Icon(
                    selected ? tab.selectedIcon : tab.icon,
                    color: foreground,
                    size: 23,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tab.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen({
    required this.apiClient,
    required this.loginRole,
    required this.localCareState,
    required this.onSelectSection,
    super.key,
  });

  final CareAgentApiClient apiClient;
  final CareAgentUserRole loginRole;
  final _LocalCareState localCareState;
  final ValueChanged<int> onSelectSection;

  @override
  Widget build(BuildContext context) {
    if (loginRole == CareAgentUserRole.caretaker) {
      return _CaretakerHomeScreen(
        careState: localCareState,
        onSelectSection: onSelectSection,
      );
    }

    return _ScreenFrame(
      title: 'Care status',
      subtitle:
          'A guided CareAgent workspace for setup, consent, vitals, and '
          'safe escalation.',
      children: [
        _PatientTodayPanel(careState: localCareState),
        _CareShortcutGrid(
          shortcuts: [
            _CareShortcut(
              icon: Icons.monitor_heart_outlined,
              title: 'Vitals',
              body:
                  '${localCareState.vitals.first.value} ${localCareState.vitals.first.unit} latest',
              onTap: () => onSelectSection(_vitalsIndex),
            ),
            _CareShortcut(
              icon: Icons.medication_outlined,
              title: 'Medicines',
              body: '${localCareState.medicines.length} scheduled',
              onTap: () => onSelectSection(_medicinesIndex),
            ),
            _CareShortcut(
              icon: Icons.chat_bubble_outline,
              title: 'Ask Caro',
              body: 'Reviewed answers',
              onTap: () => onSelectSection(_chatIndex),
            ),
            _CareShortcut(
              icon: Icons.emergency_outlined,
              title: 'SOS',
              body: 'Emergency drill',
              onTap: () => onSelectSection(_sosIndex),
            ),
          ],
        ),
        if (careAgentShowDemoTools)
          _AdvancedToolsSection(
            apiClient: apiClient,
            careState: localCareState,
            onSelectSection: onSelectSection,
          ),
      ],
    );
  }
}

class _PatientTodayPanel extends StatelessWidget {
  const _PatientTodayPanel({required this.careState});

  final _LocalCareState careState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = careState.vitals.first;
    final nextMedicine = careState.medicines.first;

    return _GlassPanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final art = CaroCharacter(state: CaroState.neutral, size: 118);
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${careState.patientName.split(' ').first} today',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'One calm view for the next medicine, recent vitals, and safe escalation.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _SignalMetric(
                    label: latest.metric,
                    value: '${latest.value} ${latest.unit}',
                    icon: Icons.monitor_heart_outlined,
                  ),
                  _SignalMetric(
                    label: 'Open alerts',
                    value: careState.openAlertCount.toString(),
                    icon: Icons.notification_important_outlined,
                  ),
                  _SignalMetric(
                    label: 'Next dose',
                    value: nextMedicine.schedule,
                    icon: Icons.medication_outlined,
                  ),
                ],
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: art),
                const SizedBox(height: 12),
                copy,
              ],
            );
          }

          return Row(
            children: [
              art,
              const SizedBox(width: 20),
              Expanded(child: copy),
            ],
          );
        },
      ),
    );
  }
}

class _AdvancedToolsSection extends StatelessWidget {
  const _AdvancedToolsSection({
    required this.apiClient,
    required this.careState,
    required this.onSelectSection,
  });

  final CareAgentApiClient apiClient;
  final _LocalCareState careState;
  final ValueChanged<int> onSelectSection;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        leading: const Icon(Icons.tune_outlined),
        title: const Text('Advanced tools'),
        subtitle: const Text('Internal actions and setup map'),
        children: [
          _LocalCareSnapshot(careState: careState),
          const SizedBox(height: 12),
          _CareScenarioPanel(careState: careState),
          const SizedBox(height: 12),
          _PilotWorkspace(apiClient: apiClient),
          const SizedBox(height: 12),
          _CareShortcutGrid(
            shortcuts: [
              for (var index = 1; index < _sections.length; index++)
                _CareShortcut(
                  icon: _sections[index].icon,
                  title: _sections[index].title,
                  body: _sections[index].shortLabel,
                  onTap: () => onSelectSection(index),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CaretakerHomeScreen extends StatelessWidget {
  const _CaretakerHomeScreen({
    required this.careState,
    required this.onSelectSection,
  });

  final _LocalCareState careState;
  final ValueChanged<int> onSelectSection;

  @override
  Widget build(BuildContext context) {
    return _ScreenFrame(
      title: 'Caretaker command',
      subtitle:
          'Risk-ranked patients, urgent evidence, and acknowledgement-ready '
          'care actions.',
      children: [
        _CaretakerCommandPanel(careState: careState),
        _PatientQueuePanel(careState: careState),
        _SafetyBanner(
          title: 'Caretaker access requires patient consent',
          message:
              'This view shows only the synthetic granted patient. Production '
              'caretaker access must be backed by active patient grants, '
              'purpose-specific permissions, and audit logs.',
        ),
        _CareShortcutGrid(
          shortcuts: [
            _CareShortcut(
              icon: Icons.notification_important_outlined,
              title: 'Alert inbox',
              body: '${careState.openAlertCount} open alert(s)',
              onTap: () => onSelectSection(_alertsIndex),
            ),
            _CareShortcut(
              icon: Icons.contact_phone_outlined,
              title: 'Care team',
              body: '${careState.contacts.length} verified contacts',
              onTap: () => onSelectSection(_caretakerIndex),
            ),
            _CareShortcut(
              icon: Icons.emergency_outlined,
              title: 'SOS protocol',
              body: careState.sosRunning ? 'Drill active' : 'Ready to run',
              onTap: () => onSelectSection(_sosIndex),
            ),
          ],
        ),
      ],
    );
  }
}

class _CaretakerCommandPanel extends StatelessWidget {
  const _CaretakerCommandPanel({required this.careState});

  final _LocalCareState careState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _GlassPanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final art = CaroCharacter(
            state: careState.openAlertCount > 0
                ? CaroState.concerned
                : CaroState.confirming,
            size: compact ? 118 : 156,
          );
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Meera, start with Ravi', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Recent vitals and the evening medicine window need review. '
                'Caro keeps the evidence and safe next action together.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _SignalMetric(
                    label: 'Open alerts',
                    value: careState.openAlertCount.toString(),
                    icon: Icons.priority_high_outlined,
                  ),
                  _SignalMetric(
                    label: 'Primary patient',
                    value: '1',
                    icon: Icons.person_pin_circle_outlined,
                  ),
                  _SignalMetric(
                    label: 'Channels',
                    value: '4',
                    icon: Icons.settings_input_antenna_outlined,
                  ),
                ],
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: art),
                const SizedBox(height: 14),
                copy,
              ],
            );
          }

          return Row(
            children: [
              art,
              const SizedBox(width: 22),
              Expanded(child: copy),
            ],
          );
        },
      ),
    );
  }
}

class _PatientQueuePanel extends StatelessWidget {
  const _PatientQueuePanel({required this.careState});

  final _LocalCareState careState;

  @override
  Widget build(BuildContext context) {
    final latest = careState.vitals.first;

    return _GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Patient queue', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _PatientQueueRow(
            name: careState.patientName,
            detail: careState.careGoal,
            risk: latest.status,
            evidence: '${latest.metric} ${latest.value} ${latest.unit}',
            action: careState.openAlertCount > 0
                ? 'Acknowledge or escalate'
                : 'Daily summary ready',
          ),
          const SizedBox(height: 10),
          const _PatientQueueRow(
            name: 'Anita Rao',
            detail: 'Weekly diabetes summary only',
            risk: 'stable',
            evidence: 'No urgent events',
            action: 'Send weekly update',
            dimmed: true,
          ),
        ],
      ),
    );
  }
}

class _PatientQueueRow extends StatelessWidget {
  const _PatientQueueRow({
    required this.name,
    required this.detail,
    required this.risk,
    required this.evidence,
    required this.action,
    this.dimmed = false,
  });

  final String name;
  final String detail;
  final String risk;
  final String evidence;
  final String action;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = dimmed ? theme.colorScheme.primary : theme.colorScheme.error;

    return AnimatedContainer(
      duration: CareMotion.standard,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(
          alpha: dimmed ? 0.46 : 0.82,
        ),
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PersonMedallion(label: name, urgent: !dimmed),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(detail, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatusPill(icon: Icons.speed_outlined, label: risk),
                    _StatusPill(
                      icon: Icons.monitor_heart_outlined,
                      label: evidence,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(onPressed: () {}, child: Text(action)),
        ],
      ),
    );
  }
}

class _PersonMedallion extends StatelessWidget {
  const _PersonMedallion({required this.label, required this.urgent});

  final String label;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final initials = label
        .split(' ')
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0])
        .join();
    final theme = Theme.of(context);

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: urgent
              ? const [Color(0xFFFF6A7A), Color(0xFFFFC0A6)]
              : const [Color(0xFF58C7BE), Color(0xFFA8E6CF)],
        ),
        borderRadius: const BorderRadius.all(Radius.circular(18)),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: theme.textTheme.titleSmall?.copyWith(color: Colors.white),
      ),
    );
  }
}

class _SignalMetric extends StatelessWidget {
  const _SignalMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 132,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.70),
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(height: 10),
          Text(value, style: theme.textTheme.titleLarge),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _CareShortcut {
  const _CareShortcut({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;
}

class _CareShortcutGrid extends StatelessWidget {
  const _CareShortcutGrid({required this.shortcuts});

  final List<_CareShortcut> shortcuts;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 760
            ? (constraints.maxWidth - 24) / 3
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final shortcut in shortcuts)
              SizedBox(
                width: width,
                child: _ShortcutTile(shortcut: shortcut),
              ),
          ],
        );
      },
    );
  }
}

class _ShortcutTile extends StatefulWidget {
  const _ShortcutTile({required this.shortcut});

  final _CareShortcut shortcut;

  @override
  State<_ShortcutTile> createState() => _ShortcutTileState();
}

class _ShortcutTileState extends State<_ShortcutTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final scale = reduceMotion || !_hovered ? 1.0 : 1.015;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: scale,
        duration: CareMotion.quick,
        curve: Curves.easeOutCubic,
        child: InkWell(
          onTap: widget.shortcut.onTap,
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          child: AnimatedContainer(
            duration: CareMotion.standard,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(
                alpha: _hovered ? 0.86 : 0.72,
              ),
              borderRadius: const BorderRadius.all(Radius.circular(20)),
              border: Border.all(
                color:
                    (_hovered
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline)
                        .withValues(alpha: _hovered ? 0.36 : 0.45),
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(
                    alpha: _hovered ? 0.12 : 0,
                  ),
                  blurRadius: 22,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(widget.shortcut.icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.shortcut.title,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.shortcut.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PilotWorkspace extends StatefulWidget {
  const _PilotWorkspace({required this.apiClient});

  final CareAgentApiClient apiClient;

  @override
  State<_PilotWorkspace> createState() => _PilotWorkspaceState();
}

class _PilotWorkspaceState extends State<_PilotWorkspace> {
  static const _pilotConsentType = 'pilot_mvp';

  final _nameController = TextEditingController(text: 'Pilot Patient');
  final _metricController = TextEditingController(text: 'heart_rate');
  final _valueController = TextEditingController(text: '132');
  final _unitController = TextEditingController(text: 'bpm');
  final _riskReasonController = TextEditingController(
    text: 'Manual pilot check requires caretaker review.',
  );

  bool _busy = false;
  String? _status;
  Map<String, dynamic>? _patient;
  Map<String, dynamic>? _riskEvent;
  Map<String, dynamic>? _policy;
  Map<String, dynamic>? _escalationRun;
  Map<String, dynamic>? _document;
  List<Map<String, dynamic>> _consents = const [];
  List<Map<String, dynamic>> _vitals = const [];
  List<Map<String, dynamic>> _alerts = const [];
  List<Map<String, dynamic>> _auditLogs = const [];

  CareAgentApiClient get _api => widget.apiClient;
  String? get _patientId => _patient?['id']?.toString();
  Map<String, dynamic>? get _activePilotConsent {
    for (final consent in _consents) {
      if (consent['consent_type'] == _pilotConsentType &&
          consent['status'] == 'active') {
        return consent;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _metricController.dispose();
    _valueController.dispose();
    _unitController.dispose();
    _riskReasonController.dispose();
    super.dispose();
  }

  Future<void> _loadOrCreatePatient() async {
    await _run('Patient profile ready.', () async {
      final patients = await _api.listPatients();
      _patient = patients.isNotEmpty
          ? patients.first
          : await _api.createPatient(fullName: _nameController.text.trim());
      await _refreshConsents();
    });
  }

  Future<void> _grantPilotConsent() async {
    final patientId = _requirePatient();
    await _run('Pilot consent granted.', () async {
      await _api.grantConsent(
        patientId: patientId,
        consentType: _pilotConsentType,
        scope: {
          'health_data': true,
          'audit': true,
          'emergency_simulation': true,
        },
      );
      await _refreshConsents();
    });
  }

  Future<void> _revokePilotConsent() async {
    final patientId = _requirePatient();
    final consentId = _activePilotConsent?['id']?.toString();
    if (consentId == null) {
      setState(() => _status = 'No active pilot consent to revoke.');
      return;
    }
    await _run('Pilot consent revoked.', () async {
      await _api.revokeConsent(
        patientId: patientId,
        consentId: consentId,
        reason: 'patient withdrew pilot consent',
      );
      await _refreshConsents();
    });
  }

  Future<void> _refreshConsents() async {
    final patientId = _requirePatient();
    _consents = await _api.listConsents(patientId);
  }

  Future<void> _submitVital() async {
    final patientId = _requirePatient();
    final value = num.tryParse(_valueController.text.trim());
    if (value == null) {
      setState(() => _status = 'Enter a numeric vital value.');
      return;
    }
    await _run('Vital submitted and evaluated.', () async {
      final response = await _api.submitManualVital(
        patientId: patientId,
        metricCode: _metricController.text.trim(),
        value: value,
        unit: _unitController.text.trim(),
      );
      _vitals = await _api.latestVitals(patientId);
      final generatedRiskEvent = _firstMap(response['risk_events']);
      if (generatedRiskEvent != null) {
        _riskEvent = generatedRiskEvent;
        _alerts = await _api.listAlerts(patientId);
      }
    });
  }

  Future<void> _createRiskAndAlert() async {
    final patientId = _requirePatient();
    await _run('Risk event and alert created.', () async {
      _riskEvent = await _api.createRiskEvent(
        patientId: patientId,
        reason: _riskReasonController.text.trim(),
      );
      _alerts = await _api.listAlerts(patientId);
    });
  }

  Future<void> _startSimulation() async {
    final patientId = _requirePatient();
    final riskEventId = _riskEvent?['id']?.toString();
    if (riskEventId == null) {
      setState(() => _status = 'Create a risk event before simulation.');
      return;
    }
    await _run('SOS simulation started.', () async {
      _policy ??= await _api.createSimulationPolicy(patientId);
      _escalationRun = await _api.startSimulationEscalation(
        riskEventId: riskEventId,
        patientId: patientId,
        policyId: _policy!['id'].toString(),
      );
    });
  }

  Future<void> _acknowledgeSimulation() async {
    final patientId = _requirePatient();
    final runId = _escalationRun?['id']?.toString();
    if (runId == null) {
      setState(() => _status = 'Start a simulation before acknowledgement.');
      return;
    }
    await _run('SOS simulation acknowledged.', () async {
      _escalationRun = await _api.acknowledgeEscalation(
        escalationRunId: runId,
        patientId: patientId,
      );
    });
  }

  Future<void> _initDocument() async {
    final patientId = _requirePatient();
    await _run('Test document record created.', () async {
      final response = await _api.initDocumentUpload(patientId);
      _document = response['document'] as Map<String, dynamic>?;
    });
  }

  Future<void> _loadAudit() async {
    final patientId = _requirePatient();
    await _run('Audit loaded.', () async {
      _auditLogs = await _api.auditLogs(patientId);
    });
  }

  Future<void> _run(String success, Future<void> Function() action) async {
    if (!_api.isConfigured) {
      setState(
        () => _status = 'Set CAREAGENT_API_BASE_URL to use pilot flows.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await action();
      if (mounted) {
        setState(() => _status = success);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _status = careAgentAuthErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _requirePatient() {
    final patientId = _patientId;
    if (patientId == null) {
      throw const CareAgentApiException('Create or load a patient first.');
    }
    return patientId;
  }

  Map<String, dynamic>? _firstMap(Object? value) {
    if (value is! List) return null;
    for (final item in value) {
      if (item is Map) {
        return item.map((key, value) => MapEntry(key.toString(), value));
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud_sync_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Integration workspace',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_busy)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_status != null)
              _SafetyBanner(title: 'Sandbox status', message: _status!),
            _PilotTextField(
              controller: _nameController,
              label: 'Patient name',
              icon: Icons.person_outline,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _loadOrCreatePatient,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Load/Create Patient'),
                ),
                FilledButton.tonalIcon(
                  onPressed:
                      _busy || _patientId == null || _activePilotConsent != null
                      ? null
                      : _grantPilotConsent,
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text('Grant Consent'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || _activePilotConsent == null
                      ? null
                      : _revokePilotConsent,
                  icon: const Icon(Icons.remove_circle_outline),
                  label: const Text('Revoke Consent'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy || _patientId == null ? null : _initDocument,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Create Test Document'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _PilotConsentStatus(consents: _consents),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 180,
                  child: _PilotTextField(
                    controller: _metricController,
                    label: 'Metric',
                    icon: Icons.monitor_heart_outlined,
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: _PilotTextField(
                    controller: _valueController,
                    label: 'Value',
                    icon: Icons.speed_outlined,
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: _PilotTextField(
                    controller: _unitController,
                    label: 'Unit',
                    icon: Icons.straighten_outlined,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _busy || _patientId == null ? null : _submitVital,
                  icon: const Icon(Icons.add_chart_outlined),
                  label: const Text('Submit + Evaluate'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _PilotTextField(
              controller: _riskReasonController,
              label: 'Risk reason',
              icon: Icons.warning_amber_outlined,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _busy || _patientId == null
                      ? null
                      : _createRiskAndAlert,
                  icon: const Icon(Icons.notification_important_outlined),
                  label: const Text('Create Alert'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy || _patientId == null
                      ? null
                      : _startSimulation,
                  icon: const Icon(Icons.emergency_outlined),
                  label: const Text('Start SOS Simulation'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy || _patientId == null
                      ? null
                      : _acknowledgeSimulation,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Acknowledge'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || _patientId == null ? null : _loadAudit,
                  icon: const Icon(Icons.history_outlined),
                  label: const Text('Load Audit'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _PilotSummary(
              patient: _patient,
              consents: _consents,
              vitals: _vitals,
              alerts: _alerts,
              riskEvent: _riskEvent,
              escalationRun: _escalationRun,
              document: _document,
              auditLogs: _auditLogs,
            ),
          ],
        ),
      ),
    );
  }
}

class _PilotTextField extends StatelessWidget {
  const _PilotTextField({
    required this.controller,
    required this.label,
    required this.icon,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    );
  }
}

class _PilotConsentStatus extends StatelessWidget {
  const _PilotConsentStatus({required this.consents});

  final List<Map<String, dynamic>> consents;

  bool get _hasActivePilotConsent {
    return consents.any(
      (consent) =>
          consent['consent_type'] == _PilotWorkspaceState._pilotConsentType &&
          consent['status'] == 'active',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _hasActivePilotConsent
        ? 'Pilot consent active'
        : 'Pilot consent not active';
    final message = _hasActivePilotConsent
        ? 'Backend consent is persisted and can be revoked.'
        : 'Grant consent before testing vitals, documents, audit, and simulation.';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _hasActivePilotConsent
                  ? Icons.verified_user_outlined
                  : Icons.privacy_tip_outlined,
              color: _hasActivePilotConsent
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(message, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PilotSummary extends StatelessWidget {
  const _PilotSummary({
    required this.patient,
    required this.consents,
    required this.vitals,
    required this.alerts,
    required this.riskEvent,
    required this.escalationRun,
    required this.document,
    required this.auditLogs,
  });

  final Map<String, dynamic>? patient;
  final List<Map<String, dynamic>> consents;
  final List<Map<String, dynamic>> vitals;
  final List<Map<String, dynamic>> alerts;
  final Map<String, dynamic>? riskEvent;
  final Map<String, dynamic>? escalationRun;
  final Map<String, dynamic>? document;
  final List<Map<String, dynamic>> auditLogs;

  @override
  Widget build(BuildContext context) {
    final rows = <String>[
      if (patient != null)
        'Patient: ${patient!['full_name']} (${patient!['id']})',
      if (consents.isNotEmpty)
        'Consents: ${consents.where((item) => item['status'] == 'active').length} active of ${consents.length}',
      if (vitals.isNotEmpty)
        'Vitals: ${vitals.map((item) => '${item['metric_code']} ${item['value']} ${item['unit']}').join(', ')}',
      if (alerts.isNotEmpty)
        'Alerts: ${alerts.length} latest ${alerts.first['status']}',
      if (riskEvent != null)
        'Risk: ${riskEvent!['severity']} ${riskEvent!['status']}',
      if (escalationRun != null)
        'Simulation: ${escalationRun!['status']} with ${(escalationRun!['actions'] as List?)?.length ?? 0} action(s)',
      if (document != null)
        'Document: ${document!['original_filename']} ${document!['review_status']}',
      if (auditLogs.isNotEmpty) 'Audit events: ${auditLogs.length}',
    ];
    if (rows.isEmpty) {
      return const Text('Run the pilot actions to populate this summary.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(row)),
      ],
    );
  }
}

class _LocalCareState extends ChangeNotifier {
  String patientName = 'Ravi Sharma';
  String language = 'Hindi + English';
  String ageAndLocation = '68 years, Noida Sector 62';
  String careGoal =
      'Diabetes and hypertension support with caretaker escalation.';
  String emergencyAddress = 'Tower B, Sunrise Residency, Sector 62, Noida, UP';
  String conditions = 'Type 2 diabetes, hypertension, post-stent follow-up';
  String allergies = 'Penicillin';
  String caretakerName = 'Meera Sharma';
  String caretakerPhone = '+91 98765 43210';
  final Map<String, bool> consents = {
    'Health data': true,
    'Documents': true,
    'Caretaker access': true,
    'WhatsApp alerts': true,
    'Telegram alerts': true,
    'Voice calls': true,
    'Location sharing': false,
    'Emergency automation': false,
    'Simulation-only SOS': true,
  };
  final List<_LocalVital> vitals = [
    _LocalVital(
      metric: 'heart_rate',
      value: '132',
      unit: 'bpm',
      source: 'Watch BLE simulator',
      observedAt: DateTime.now().subtract(const Duration(minutes: 3)),
      freshness: 'fresh',
      status: 'critical',
    ),
    _LocalVital(
      metric: 'spo2',
      value: '91',
      unit: '%',
      source: 'Pulse oximeter',
      observedAt: DateTime.now().subtract(const Duration(minutes: 4)),
      freshness: 'fresh',
      status: 'high',
    ),
    _LocalVital(
      metric: 'blood_pressure',
      value: '165/98',
      unit: 'mmHg',
      source: 'Manual cuff',
      observedAt: DateTime.now().subtract(const Duration(minutes: 18)),
      freshness: 'fresh',
      status: 'high',
    ),
    _LocalVital(
      metric: 'glucose',
      value: '188',
      unit: 'mg/dL',
      source: 'Prescription OCR fallback',
      observedAt: DateTime.now().subtract(const Duration(hours: 2)),
      freshness: 'reviewed',
      status: 'moderate',
    ),
  ];
  final List<_LocalMedicine> medicines = [
    _LocalMedicine(
      name: 'Metformin',
      dose: '500 mg',
      schedule: 'After breakfast',
      status: 'taken',
      source: 'Reviewed prescription',
    ),
    _LocalMedicine(
      name: 'Telmisartan',
      dose: '40 mg',
      schedule: '9:00 PM',
      status: 'due in 38 min',
      source: 'Reviewed prescription',
    ),
    _LocalMedicine(
      name: 'Atorvastatin',
      dose: '20 mg',
      schedule: '10:00 PM',
      status: 'scheduled',
      source: 'Doctor discharge note',
    ),
    _LocalMedicine(
      name: 'Aspirin',
      dose: '75 mg',
      schedule: 'After dinner',
      status: 'caregiver review',
      source: 'Low-confidence OCR',
    ),
  ];
  final List<_LocalDocument> documents = [
    _LocalDocument(
      name: 'Cardiology prescription - May 2026.pdf',
      kind: 'Prescription',
      status: 'reviewed',
      source: 'Uploaded in app',
      extractedFacts: [
        'Metformin 500 mg after breakfast',
        'Telmisartan 40 mg at night',
        'Follow-up in 14 days',
      ],
    ),
    _LocalDocument(
      name: 'WhatsApp lab report photo.jpg',
      kind: 'Lab report',
      status: 'needs review',
      source: 'WhatsApp channel upload',
      extractedFacts: ['HbA1c 7.8%', 'Creatinine 1.1 mg/dL', 'LDL 112 mg/dL'],
    ),
    _LocalDocument(
      name: 'Discharge summary - stent follow-up.pdf',
      kind: 'Discharge summary',
      status: 'source-linked',
      source: 'Caretaker upload',
      extractedFacts: [
        'Stent follow-up completed',
        'Avoid missed BP medicine',
        'Call cardiologist if chest pain occurs',
      ],
    ),
  ];
  final List<_LocalMessage> messages = [
    _LocalMessage(
      author: 'Caro',
      body:
          'Care context loaded for Ravi Sharma. I can explain vitals, medicine schedule, reviewed documents, and caregiver alert steps.',
    ),
    _LocalMessage(
      author: 'Caro',
      body:
          'Critical alert: heart_rate 132 bpm and SpO2 91% are recent. CareAgent can notify verified contacts and will not call emergency services from this screen.',
    ),
  ];
  final List<_LocalContact> contacts = [
    _LocalContact(
      name: 'Meera Sharma',
      role: 'Primary caretaker',
      relation: 'Daughter',
      phone: '+91 98765 43210',
      priority: 1,
      channels: ['Push', 'WhatsApp', 'Voice'],
      verification: 'verified',
      consent: 'active',
      lastAction: 'Acknowledged medicine reminder 1h ago',
    ),
    _LocalContact(
      name: 'Amit Sharma',
      role: 'Secondary caretaker',
      relation: 'Son',
      phone: '+91 99887 77665',
      priority: 2,
      channels: ['Telegram', 'Voice'],
      verification: 'verified',
      consent: 'active',
      lastAction: 'Telegram linked for alerts',
    ),
    _LocalContact(
      name: 'Dr. Neha Verma',
      role: 'Cardiologist',
      relation: 'Doctor',
      phone: '+91 91234 56780',
      priority: 3,
      channels: ['WhatsApp', 'Voice'],
      verification: 'clinic verified',
      consent: 'minimum PHI',
      lastAction: 'Receives escalation summaries only',
    ),
    _LocalContact(
      name: 'CarePlus Ambulance Desk',
      role: 'Private ambulance',
      relation: 'Emergency service',
      phone: '+91 1800 555 221',
      priority: 4,
      channels: ['Voice'],
      verification: 'contract pending',
      consent: 'not enabled',
      lastAction: 'Requires explicit patient approval',
    ),
  ];
  final List<_LocalTimelineEvent> sosTimeline = [
    _LocalTimelineEvent(
      title: 'Critical vitals detected',
      body:
          'Watch BLE simulator reported heart_rate 132 bpm; pulse oximeter '
          'reported SpO2 91%. Evidence is recent and source-labelled.',
    ),
    _LocalTimelineEvent(
      title: 'Permissions checked',
      body:
          'Health data, caretaker, messaging, voice, and drill permissions are active. Real emergency calling is disabled.',
    ),
  ];
  final List<_LocalChannel> channels = [
    _LocalChannel(
      name: 'In-app push',
      provider: 'FCM/APNs',
      readiness: 'Ready',
      enabled: true,
      verified: true,
      contacts: 'Patient app + Meera device',
      mode: 'On',
      nextStep: 'No action needed.',
      template: 'urgent_vitals_alert_v1',
    ),
    _LocalChannel(
      name: 'WhatsApp',
      provider: 'Cloud API or approved BSP',
      readiness: 'Needs final approval',
      enabled: true,
      verified: true,
      contacts: 'Meera, Dr. Neha',
      mode: 'Drill only',
      nextStep: 'Confirm approved care-alert templates.',
      template: 'critical_escalation_caretaker_v1',
    ),
    _LocalChannel(
      name: 'Telegram',
      provider: 'Telegram Bot API',
      readiness: 'Linked contact',
      enabled: true,
      verified: true,
      contacts: 'Amit',
      mode: 'Drill only',
      nextStep: 'Confirm the contact before urgent alerts.',
      template: 'telegram_ack_callback_v1',
    ),
    _LocalChannel(
      name: 'Voice call',
      provider: 'Twilio / Exotel / Plivo decision',
      readiness: 'script approved',
      enabled: true,
      verified: true,
      contacts: 'Meera, Amit, Dr. Neha, private ambulance',
      mode: 'test-call only',
      nextStep: 'Choose provider and add caller ID, callback URLs, DTMF.',
      template: 'critical_caretaker_call_v1',
    ),
    _LocalChannel(
      name: 'SMS fallback',
      provider: 'Region-approved SMS gateway',
      readiness: 'policy draft',
      enabled: false,
      verified: false,
      contacts: 'Caretakers only',
      mode: 'disabled',
      nextStep: 'Confirm lawful SMS use and fallback copy.',
      template: 'urgent_vitals_sms_fallback_v1',
    ),
  ];
  final List<_LocalAlert> alerts = [
    _LocalAlert(
      title: 'Critical vitals escalation active',
      body:
          'Heart rate 132 bpm and SpO2 91% were detected in the last '
          '5 minutes. Caretaker escalation is active.',
      severity: 'critical',
      evidence: 'Watch BLE simulator + pulse oximeter',
      nextAction: 'Send WhatsApp and Telegram alert, then place test call.',
    ),
    _LocalAlert(
      title: 'Evening BP medicine due soon',
      body:
          'Telmisartan 40 mg is due at 9:00 PM. Missed-dose policy will '
          'notify Meera after 45 minutes if consent remains active.',
      severity: 'moderate',
      evidence: 'Reviewed prescription schedule',
      nextAction: 'Wait for patient confirmation or trigger reminder.',
    ),
  ];
  final List<_LocalEscalationAction> escalationActions = [
    _LocalEscalationAction(
      step: '1',
      channel: 'Push',
      target: 'Ravi Sharma',
      status: 'delivered',
      detail: 'Patient confirmation prompt delivered to app.',
      eta: 'now',
    ),
    _LocalEscalationAction(
      step: '2',
      channel: 'WhatsApp',
      target: 'Meera Sharma',
      status: 'ready',
      detail:
          'critical_escalation_caretaker_v1 with AI disclosure and ack link.',
      eta: '+1 min',
    ),
    _LocalEscalationAction(
      step: '3',
      channel: 'Telegram',
      target: 'Amit Sharma',
      status: 'ready',
      detail: 'Inline acknowledge buttons after verified bot link.',
      eta: '+2 min',
    ),
    _LocalEscalationAction(
      step: '4',
      channel: 'Voice',
      target: 'Meera Sharma',
      status: 'test-call planned',
      detail: 'critical_caretaker_call_v1 with DTMF 1 to acknowledge.',
      eta: '+4 min',
    ),
    _LocalEscalationAction(
      step: '5',
      channel: 'Voice',
      target: 'Dr. Neha Verma',
      status: 'fallback',
      detail: 'Minimum necessary PHI summary if caretaker does not respond.',
      eta: '+8 min',
    ),
    _LocalEscalationAction(
      step: '6',
      channel: 'Voice',
      target: 'CarePlus Ambulance Desk',
      status: 'disabled',
      detail: 'Private ambulance contact only after explicit policy approval.',
      eta: 'disabled',
    ),
  ];

  int get activeConsentCount =>
      consents.values.where((isActive) => isActive).length;

  int get openAlertCount =>
      alerts.where((alert) => alert.status == 'open').length;

  bool get sosRunning =>
      escalationActions.any((action) => action.status.contains('sent')) ||
      sosTimeline.any((event) => event.title == 'Drill started');

  void saveProfile({
    required String name,
    required String profileLanguage,
    required String goal,
    required String caretaker,
    required String phone,
  }) {
    patientName = name.trim().isEmpty ? patientName : name.trim();
    language = profileLanguage.trim().isEmpty
        ? language
        : profileLanguage.trim();
    careGoal = goal.trim().isEmpty ? careGoal : goal.trim();
    caretakerName = caretaker.trim().isEmpty ? caretakerName : caretaker.trim();
    caretakerPhone = phone.trim().isEmpty ? caretakerPhone : phone.trim();
    contacts[0].name = caretakerName;
    contacts[0].phone = caretakerPhone;
    notifyListeners();
  }

  void setConsent(String key, bool value) {
    consents[key] = value;
    notifyListeners();
  }

  void addVital(String metric, String value, String unit) {
    final vital = _LocalVital(
      metric: metric.trim().isEmpty ? 'heart_rate' : metric.trim(),
      value: value.trim().isEmpty ? '0' : value.trim(),
      unit: unit.trim().isEmpty ? 'unit' : unit.trim(),
      source: 'manual',
      observedAt: DateTime.now(),
      freshness: 'fresh',
      status: 'needs review',
    );
    vitals.insert(0, vital);
    final alert = _alertForVital(vital);
    if (alert != null) alerts.insert(0, alert);
    notifyListeners();
  }

  void addMedicine(String name, String schedule) {
    medicines.insert(
      0,
      _LocalMedicine(
        name: name.trim().isEmpty ? 'Medicine' : name.trim(),
        dose: 'manual entry',
        schedule: schedule.trim().isEmpty ? 'Today' : schedule.trim(),
        status: 'due',
        source: 'Manual add',
      ),
    );
    notifyListeners();
  }

  void markMedicineTaken(_LocalMedicine medicine) {
    medicine.status = 'taken';
    notifyListeners();
  }

  void addDocument(String name, String kind) {
    documents.insert(
      0,
      _LocalDocument(
        name: name.trim().isEmpty ? 'care-record.pdf' : name.trim(),
        kind: kind.trim().isEmpty ? 'Medical record' : kind.trim(),
        status: 'needs review',
        source: 'Manual add',
        extractedFacts: const ['Awaiting OCR and human review'],
      ),
    );
    notifyListeners();
  }

  void markDocumentReviewed(_LocalDocument document) {
    document.status = 'reviewed';
    notifyListeners();
  }

  void sendMessage(String body) {
    final text = body.trim();
    if (text.isEmpty) return;
    messages.add(_LocalMessage(author: 'You', body: text));
    messages.add(_LocalMessage(author: 'Caro', body: _replyFor(text)));
    notifyListeners();
  }

  void startSosSimulation() {
    for (final action in escalationActions) {
      action.status = switch (action.step) {
        '1' => 'delivered',
        '2' => 'sent',
        '3' => 'sent',
        '4' => 'ringing test call',
        '5' => 'queued fallback',
        _ => action.status,
      };
    }
    sosTimeline
      ..clear()
      ..add(
        _LocalTimelineEvent(
          title: 'Drill started',
          body:
              'Critical vitals drill started. No real emergency service or provider was contacted.',
        ),
      )
      ..add(
        _LocalTimelineEvent(
          title: 'WhatsApp and Telegram sent',
          body:
              'Meera receives WhatsApp template with ack link. Amit receives '
              'Telegram callback. Both messages are drill records.',
        ),
      )
      ..add(
        _LocalTimelineEvent(
          title: 'Voice test call ringing',
          body:
              'critical_caretaker_call_v1 discloses AI identity and asks '
              'the caretaker to press 1 to acknowledge.',
        ),
      );
    alerts.insert(
      0,
      _LocalAlert(
        title: 'Multi-channel escalation awaiting acknowledgement',
        body:
            'WhatsApp, Telegram, and voice test-call actions are in the incident timeline. This is a drill record only.',
        severity: 'critical',
        evidence: 'Emergency drill CRIT-HR-001',
        nextAction: 'Wait for caretaker ack or continue to doctor fallback.',
      ),
    );
    notifyListeners();
  }

  void acknowledgeSos() {
    for (final action in escalationActions) {
      if (action.target == caretakerName || action.target == 'Meera Sharma') {
        action.status = 'acknowledged';
      }
    }
    sosTimeline.add(
      _LocalTimelineEvent(
        title: 'Acknowledged',
        body:
            '$caretakerName acknowledged the drill from the WhatsApp link and voice keypad path.',
      ),
    );
    for (final alert in alerts) {
      if (alert.title.contains('escalation') ||
          alert.title.contains('Critical vitals')) {
        alert.status = 'acknowledged';
      }
    }
    notifyListeners();
  }

  void setChannelEnabled(_LocalChannel channel, bool enabled) {
    channel.enabled = enabled;
    if (enabled) channel.verified = true;
    notifyListeners();
  }

  void acknowledgeAlert(_LocalAlert alert) {
    alert.status = 'acknowledged';
    notifyListeners();
  }

  _LocalAlert? _alertForVital(_LocalVital vital) {
    final number = num.tryParse(vital.value);
    if (number == null) return null;
    if (vital.metric == 'heart_rate' && (number >= 130 || number <= 45)) {
      return _LocalAlert(
        title: 'Heart rate needs review',
        body: 'Manual heart_rate reading is ${vital.value} ${vital.unit}.',
        severity: 'high',
        evidence: vital.source,
        nextAction: 'Route to caretaker if still high after recheck.',
      );
    }
    if (vital.metric == 'spo2' && number <= 92) {
      return _LocalAlert(
        title: 'Low oxygen needs review',
        body: 'Manual SpO2 reading is ${vital.value}${vital.unit}.',
        severity: number <= 88 ? 'critical' : 'high',
        evidence: vital.source,
        nextAction: 'Prompt urgent recheck and caretaker escalation.',
      );
    }
    return null;
  }

  String _replyFor(String text) {
    final lowered = text.toLowerCase();
    if (lowered.contains('medicine')) {
      final due = medicines.where(
        (medicine) => medicine.status.contains('due'),
      );
      return 'I found ${medicines.length} medicines. ${due.length} item(s) '
          'need attention. Reminders can notify Meera only because caretaker '
          'access and WhatsApp consent are active.';
    }
    if (lowered.contains('vital') || lowered.contains('heart')) {
      final latest = vitals.isEmpty ? null : vitals.first;
      return latest == null
          ? 'No vitals are recorded yet.'
          : 'Latest ${latest.metric} is ${latest.value} ${latest.unit} from '
                '${latest.source}. Status: ${latest.status}. I can escalate '
                'to verified contacts after confirmation; contact emergency '
                'services directly for severe symptoms.';
    }
    if (lowered.contains('sos') || lowered.contains('emergency')) {
      return 'For a real emergency, call local emergency services now. CareAgent can notify Meera by WhatsApp, Amit by Telegram, then place an AI-disclosed test call after confirmation.';
    }
    if (lowered.contains('whatsapp') || lowered.contains('telegram')) {
      return 'WhatsApp uses approved Cloud API or BSP templates. Telegram '
          'uses a verified Bot API link with callback buttons. Both require '
          'webhook signature checks, consent, rate limits, and audit logs.';
    }
    return 'I can help organize your setup. Current profile: $patientName, '
        '$activeConsentCount active consent(s), and $openAlertCount open alert(s).';
  }
}

class _LocalVital {
  _LocalVital({
    required this.metric,
    required this.value,
    required this.unit,
    required this.source,
    required this.observedAt,
    required this.freshness,
    required this.status,
  });

  final String metric;
  final String value;
  final String unit;
  final String source;
  final DateTime observedAt;
  final String freshness;
  final String status;
}

class _LocalMedicine {
  _LocalMedicine({
    required this.name,
    required this.dose,
    required this.schedule,
    required this.status,
    required this.source,
  });

  final String name;
  final String dose;
  final String schedule;
  final String source;
  String status;
}

class _LocalDocument {
  _LocalDocument({
    required this.name,
    required this.kind,
    required this.status,
    required this.source,
    required this.extractedFacts,
  });

  final String name;
  final String kind;
  final String source;
  final List<String> extractedFacts;
  String status;
}

class _LocalMessage {
  _LocalMessage({required this.author, required this.body});

  final String author;
  final String body;
}

class _LocalTimelineEvent {
  _LocalTimelineEvent({required this.title, required this.body});

  final String title;
  final String body;
}

class _LocalChannel {
  _LocalChannel({
    required this.name,
    required this.provider,
    required this.readiness,
    required this.enabled,
    required this.verified,
    required this.contacts,
    required this.mode,
    required this.nextStep,
    required this.template,
  });

  final String name;
  final String provider;
  final String readiness;
  final String contacts;
  final String mode;
  final String nextStep;
  final String template;
  bool enabled;
  bool verified;
}

class _LocalContact {
  _LocalContact({
    required this.name,
    required this.role,
    required this.relation,
    required this.phone,
    required this.priority,
    required this.channels,
    required this.verification,
    required this.consent,
    required this.lastAction,
  });

  String name;
  final String role;
  final String relation;
  String phone;
  final int priority;
  final List<String> channels;
  final String verification;
  final String consent;
  final String lastAction;
}

class _LocalEscalationAction {
  _LocalEscalationAction({
    required this.step,
    required this.channel,
    required this.target,
    required this.status,
    required this.detail,
    required this.eta,
  });

  final String step;
  final String channel;
  final String target;
  String status;
  final String detail;
  final String eta;
}

class _LocalAlert {
  _LocalAlert({
    required this.title,
    required this.body,
    required this.severity,
    required this.evidence,
    required this.nextAction,
  });

  final String title;
  final String body;
  final String severity;
  final String evidence;
  final String nextAction;
  String status = 'open';
}

class _CareFeatureScreen extends StatelessWidget {
  const _CareFeatureScreen({
    required this.section,
    required this.careState,
    super.key,
  });

  final _Section section;
  final _LocalCareState careState;

  @override
  Widget build(BuildContext context) {
    return _ScreenFrame(
      title: section.heading,
      subtitle: section.description,
      children: [
        CaroCompanion(
          state: _caroStateFor(section.title),
          title: _caroTitleFor(section.title),
          message: section.shortLabel,
        ),
        _SafetyBanner(title: section.noticeTitle, message: section.notice),
        _FeatureBody(section: section, careState: careState),
      ],
    );
  }

  CaroState _caroStateFor(String title) {
    return switch (title) {
      'Consent' => CaroState.concerned,
      'Vitals' => CaroState.listening,
      'Alerts' => CaroState.concerned,
      'Chat' => CaroState.listening,
      'SOS' => CaroState.simulation,
      'Documents' => CaroState.handoff,
      _ => CaroState.neutral,
    };
  }

  String _caroTitleFor(String title) {
    return switch (title) {
      'Consent' => 'Caro keeps consent visible',
      'Vitals' => 'Caro checks source and freshness',
      'Alerts' => 'Caro separates open and acknowledged alerts',
      'Chat' => 'Caro answers with boundaries',
      'SOS' => 'Caro keeps this in drill mode',
      'Documents' => 'Caro waits for reviewed sources',
      _ => 'Caro guides this setup area',
    };
  }
}

class _FeatureBody extends StatelessWidget {
  const _FeatureBody({required this.section, required this.careState});

  final _Section section;
  final _LocalCareState careState;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: careState,
      builder: (context, _) {
        return switch (section.title) {
          'Onboarding' => _OnboardingFeature(careState: careState),
          'Consent' => _ConsentFeature(careState: careState),
          'Vitals' => _VitalsFeature(careState: careState),
          'Medicines' => _MedicinesFeature(careState: careState),
          'Documents' => _DocumentsFeature(careState: careState),
          'Chat' => _ChatFeature(careState: careState),
          'SOS' => _SosFeature(careState: careState),
          'Caretaker' => _CaretakerFeature(careState: careState),
          'Channels' => _ChannelsFeature(careState: careState),
          'Alerts' => _AlertsFeature(careState: careState),
          _ => Column(
            children: [
              for (final item in section.items)
                _InfoTile(icon: item.icon, title: item.title, body: item.body),
            ],
          ),
        };
      },
    );
  }
}

class _LocalCareSnapshot extends StatelessWidget {
  const _LocalCareSnapshot({required this.careState});

  final _LocalCareState careState;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: careState,
      builder: (context, _) {
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatusChip(
              icon: Icons.person_outline,
              label: careState.patientName,
            ),
            _StatusChip(
              icon: Icons.verified_user_outlined,
              label: '${careState.activeConsentCount} consent(s)',
            ),
            _StatusChip(
              icon: Icons.monitor_heart_outlined,
              label: '${careState.vitals.length} vital(s)',
            ),
            _StatusChip(
              icon: Icons.notification_important_outlined,
              label: '${careState.openAlertCount} open alert(s)',
            ),
            _StatusChip(
              icon: Icons.group_outlined,
              label: '${careState.contacts.length} contacts',
            ),
            _StatusChip(
              icon: Icons.settings_phone_outlined,
              label: 'WhatsApp + Telegram + calls',
            ),
          ],
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _CareScenarioPanel extends StatelessWidget {
  const _CareScenarioPanel({required this.careState});

  final _LocalCareState careState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.play_circle_outline, color: theme.colorScheme.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Care scenario',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Show Ravi Sharma, a 68-year-old patient with recent critical '
              'vitals. CareAgent explains the evidence, displays reviewed '
              'medicine/document data, sends simulated WhatsApp and Telegram '
              'alerts to verified contacts, and prepares an AI-disclosed '
              'test voice call without contacting real emergency services.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusChip(
                  icon: Icons.monitor_heart_outlined,
                  label:
                      '${careState.vitals.first.value} '
                      '${careState.vitals.first.unit} HR',
                ),
                _StatusChip(
                  icon: Icons.medication_outlined,
                  label: '${careState.medicines.length} medicines',
                ),
                _StatusChip(
                  icon: Icons.description_outlined,
                  label: '${careState.documents.length} documents',
                ),
                _StatusChip(
                  icon: Icons.timeline_outlined,
                  label: '${careState.escalationActions.length} step runbook',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingFeature extends StatefulWidget {
  const _OnboardingFeature({required this.careState});

  final _LocalCareState careState;

  @override
  State<_OnboardingFeature> createState() => _OnboardingFeatureState();
}

class _OnboardingFeatureState extends State<_OnboardingFeature> {
  late final _name = TextEditingController(text: widget.careState.patientName);
  late final _language = TextEditingController(text: widget.careState.language);
  late final _goal = TextEditingController(text: widget.careState.careGoal);
  late final _caretaker = TextEditingController(
    text: widget.careState.caretakerName,
  );
  late final _phone = TextEditingController(
    text: widget.careState.caretakerPhone,
  );

  @override
  void dispose() {
    _name.dispose();
    _language.dispose();
    _goal.dispose();
    _caretaker.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FormGrid(
          children: [
            _PilotTextField(
              controller: _name,
              label: 'Patient name',
              icon: Icons.person_outline,
            ),
            _PilotTextField(
              controller: _language,
              label: 'Primary language',
              icon: Icons.translate_outlined,
            ),
            _PilotTextField(
              controller: _caretaker,
              label: 'Primary caretaker',
              icon: Icons.group_outlined,
            ),
            _PilotTextField(
              controller: _phone,
              label: 'Caretaker phone',
              icon: Icons.phone_outlined,
            ),
          ],
        ),
        _PilotTextField(
          controller: _goal,
          label: 'Care goal',
          icon: Icons.flag_outlined,
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () {
            widget.careState.saveProfile(
              name: _name.text,
              profileLanguage: _language.text,
              goal: _goal.text,
              caretaker: _caretaker.text,
              phone: _phone.text,
            );
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Profile saved locally.')),
            );
          },
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save Profile'),
        ),
        const SizedBox(height: 12),
        _InfoTile(
          icon: Icons.badge_outlined,
          title: widget.careState.patientName,
          body:
              '${widget.careState.ageAndLocation}. '
              '${widget.careState.language}.\n'
              '${widget.careState.careGoal}\n'
              'Conditions: ${widget.careState.conditions}. '
              'Allergies: ${widget.careState.allergies}.\n'
              'Emergency address: ${widget.careState.emergencyAddress}\n'
              'Primary caretaker: ${widget.careState.caretakerName}, '
              '${widget.careState.caretakerPhone}',
        ),
        const SizedBox(height: 8),
        for (final contact in widget.careState.contacts.take(2))
          _ContactCard(contact: contact),
      ],
    );
  }
}

class _ConsentFeature extends StatelessWidget {
  const _ConsentFeature({required this.careState});

  final _LocalCareState careState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in careState.consents.entries) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.74),
              borderRadius: const BorderRadius.all(Radius.circular(18)),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.34),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  _CareActionLeading(
                    icon: entry.value
                        ? Icons.verified_user_outlined
                        : Icons.privacy_tip_outlined,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.key, style: theme.textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(
                          entry.value
                              ? 'Active for this care workspace.'
                              : 'Disabled until the patient allows it.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: entry.value,
                    onChanged: (value) =>
                        careState.setConsent(entry.key, value),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        const _InfoTile(
          icon: Icons.rule_outlined,
          title: 'Before alerts are sent',
          body:
              'Only verified contacts with active permission can receive care alerts, messages, location, or call requests.',
        ),
      ],
    );
  }
}

class _VitalsFeature extends StatefulWidget {
  const _VitalsFeature({required this.careState});

  final _LocalCareState careState;

  @override
  State<_VitalsFeature> createState() => _VitalsFeatureState();
}

class _VitalsFeatureState extends State<_VitalsFeature> {
  final _metric = TextEditingController(text: 'heart_rate');
  final _value = TextEditingController(text: '132');
  final _unit = TextEditingController(text: 'bpm');

  @override
  void dispose() {
    _metric.dispose();
    _value.dispose();
    _unit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FormGrid(
          children: [
            _PilotTextField(
              controller: _metric,
              label: 'Metric',
              icon: Icons.monitor_heart_outlined,
            ),
            _PilotTextField(
              controller: _value,
              label: 'Value',
              icon: Icons.speed_outlined,
            ),
            _PilotTextField(
              controller: _unit,
              label: 'Unit',
              icon: Icons.straighten_outlined,
            ),
          ],
        ),
        FilledButton.icon(
          onPressed: () =>
              widget.careState.addVital(_metric.text, _value.text, _unit.text),
          icon: const Icon(Icons.add_chart_outlined),
          label: const Text('Add Manual Reading'),
        ),
        const SizedBox(height: 12),
        for (final vital in widget.careState.vitals)
          _InfoTile(
            icon: Icons.favorite_outline,
            title: '${vital.metric}: ${vital.value} ${vital.unit}',
            body:
                'Status: ${vital.status}. Source: ${vital.source}. '
                'Freshness: ${vital.freshness}. Observed at '
                '${TimeOfDay.fromDateTime(vital.observedAt).format(context)}.',
          ),
      ],
    );
  }
}

class _MedicinesFeature extends StatefulWidget {
  const _MedicinesFeature({required this.careState});

  final _LocalCareState careState;

  @override
  State<_MedicinesFeature> createState() => _MedicinesFeatureState();
}

class _MedicinesFeatureState extends State<_MedicinesFeature> {
  final _name = TextEditingController(text: 'Amlodipine');
  final _schedule = TextEditingController(text: '9:00 PM');

  @override
  void dispose() {
    _name.dispose();
    _schedule.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FormGrid(
          children: [
            _PilotTextField(
              controller: _name,
              label: 'Medicine',
              icon: Icons.medication_outlined,
            ),
            _PilotTextField(
              controller: _schedule,
              label: 'Schedule',
              icon: Icons.alarm_outlined,
            ),
          ],
        ),
        FilledButton.icon(
          onPressed: () =>
              widget.careState.addMedicine(_name.text, _schedule.text),
          icon: const Icon(Icons.add_outlined),
          label: const Text('Add Medicine'),
        ),
        const SizedBox(height: 12),
        for (final medicine in widget.careState.medicines)
          _CareActionTile(
            icon: Icons.medication_outlined,
            title: medicine.name,
            body:
                '${medicine.dose} - ${medicine.schedule}\n'
                '${medicine.status} - ${medicine.source}',
            trailing: medicine.status == 'taken'
                ? const Icon(Icons.check_circle_outline)
                : TextButton(
                    onPressed: () =>
                        widget.careState.markMedicineTaken(medicine),
                    child: const Text('Taken'),
                  ),
          ),
      ],
    );
  }
}

class _DocumentsFeature extends StatefulWidget {
  const _DocumentsFeature({required this.careState});

  final _LocalCareState careState;

  @override
  State<_DocumentsFeature> createState() => _DocumentsFeatureState();
}

class _DocumentsFeatureState extends State<_DocumentsFeature> {
  final _name = TextEditingController(text: 'blood-report.pdf');
  final _kind = TextEditingController(text: 'Lab report');

  @override
  void dispose() {
    _name.dispose();
    _kind.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FormGrid(
          children: [
            _PilotTextField(
              controller: _name,
              label: 'File name',
              icon: Icons.description_outlined,
            ),
            _PilotTextField(
              controller: _kind,
              label: 'Document type',
              icon: Icons.category_outlined,
            ),
          ],
        ),
        FilledButton.icon(
          onPressed: () => widget.careState.addDocument(_name.text, _kind.text),
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('Add Document Record'),
        ),
        const SizedBox(height: 12),
        for (final document in widget.careState.documents)
          _CareActionTile(
            icon: Icons.description_outlined,
            title: document.name,
            body:
                '${document.kind} - ${document.status}\n'
                'Source: ${document.source}\n'
                'Facts: ${document.extractedFacts.join('; ')}',
            trailing: document.status == 'reviewed'
                ? const Icon(Icons.fact_check_outlined)
                : TextButton(
                    onPressed: () =>
                        widget.careState.markDocumentReviewed(document),
                    child: const Text('Mark reviewed'),
                  ),
          ),
      ],
    );
  }
}

class _ChatFeature extends StatefulWidget {
  const _ChatFeature({required this.careState});

  final _LocalCareState careState;

  @override
  State<_ChatFeature> createState() => _ChatFeatureState();
}

class _ChatFeatureState extends State<_ChatFeature> {
  final _message = TextEditingController(text: 'What is my latest vital?');

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final message in widget.careState.messages)
          Align(
            alignment: message.author == 'You'
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('${message.author}: ${message.body}'),
                ),
              ),
            ),
          ),
        _PilotTextField(
          controller: _message,
          label: 'Ask Caro',
          icon: Icons.chat_bubble_outline,
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () {
            widget.careState.sendMessage(_message.text);
            _message.clear();
          },
          icon: const Icon(Icons.send_outlined),
          label: const Text('Send'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final prompt in const [
              'Explain the alert evidence',
              'What happens on WhatsApp?',
              'What medicine is due?',
              'Start emergency drill?',
            ])
              ActionChip(
                label: Text(prompt),
                onPressed: () => widget.careState.sendMessage(prompt),
              ),
          ],
        ),
      ],
    );
  }
}

class _SosFeature extends StatelessWidget {
  const _SosFeature({required this.careState});

  final _LocalCareState careState;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: careState.startSosSimulation,
              icon: const Icon(Icons.emergency_outlined),
              label: Text(
                careState.sosRunning ? 'Restart drill' : 'Start drill',
              ),
            ),
            OutlinedButton.icon(
              onPressed: careState.sosTimeline.isEmpty
                  ? null
                  : careState.acknowledgeSos,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Acknowledge'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final action in careState.escalationActions)
          _EscalationActionTile(action: action),
        const SizedBox(height: 8),
        for (final event in careState.sosTimeline)
          _InfoTile(
            icon: Icons.timeline_outlined,
            title: event.title,
            body: event.body,
          ),
        if (careState.sosTimeline.isEmpty)
          const Text('No emergency drill has been started yet.'),
      ],
    );
  }
}

class _CaretakerFeature extends StatelessWidget {
  const _CaretakerFeature({required this.careState});

  final _LocalCareState careState;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final contact in careState.contacts)
          _ContactCard(contact: contact),
      ],
    );
  }
}

class _ChannelsFeature extends StatelessWidget {
  const _ChannelsFeature({required this.careState});

  final _LocalCareState careState;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final channel in careState.channels)
          _ChannelCard(
            channel: channel,
            onChanged: (value) => careState.setChannelEnabled(channel, value),
          ),
      ],
    );
  }
}

class _AlertsFeature extends StatelessWidget {
  const _AlertsFeature({required this.careState});

  final _LocalCareState careState;

  @override
  Widget build(BuildContext context) {
    if (careState.alerts.isEmpty) {
      return const Text('No alerts yet. Add an abnormal vital or run SOS.');
    }
    return Column(
      children: [
        for (final alert in careState.alerts)
          _CareActionTile(
            icon: Icons.notification_important_outlined,
            title: alert.title,
            body:
                '${alert.severity} - ${alert.status}\n${alert.body}\n'
                'Evidence: ${alert.evidence}\nNext: ${alert.nextAction}',
            trailing: alert.status == 'open'
                ? TextButton(
                    onPressed: () => careState.acknowledgeAlert(alert),
                    child: const Text('Ack'),
                  )
                : const Icon(Icons.check_circle_outline),
          ),
      ],
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.contact});

  final _LocalContact contact;

  @override
  Widget build(BuildContext context) {
    return _CareActionTile(
      icon: Icons.verified_outlined,
      leadingLabel: contact.priority.toString(),
      title: contact.name,
      body:
          '${contact.role} - ${contact.relation}\n'
          '${contact.phone}\n'
          'Channels: ${contact.channels.join(', ')}\n'
          'Verification: ${contact.verification}; consent: ${contact.consent}\n'
          '${contact.lastAction}',
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({required this.channel, required this.onChanged});

  final _LocalChannel channel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.74),
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.34),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _CareActionLeading(
                  icon: channel.verified
                      ? Icons.mark_email_read_outlined
                      : Icons.mark_email_unread_outlined,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(channel.name, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        channel.readiness,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Switch(value: channel.enabled, onChanged: onChanged),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Contacts: ${channel.contacts}\n'
              'Next: ${channel.nextStep}',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _EscalationActionTile extends StatelessWidget {
  const _EscalationActionTile({required this.action});

  final _LocalEscalationAction action;

  @override
  Widget build(BuildContext context) {
    return _CareActionTile(
      icon: Icons.route_outlined,
      leadingLabel: action.step,
      title: '${action.channel} to ${action.target}',
      body: '${action.status} - ${action.eta}\n${action.detail}',
    );
  }
}

class _FormGrid extends StatelessWidget {
  const _FormGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 640
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _ScreenFrame extends StatelessWidget {
  const _ScreenFrame({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth >= 720 ? 32.0 : 16.0;

          return ListView(
            padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 96),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _GlassPanel(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: theme.textTheme.headlineSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    subtitle,
                                    style: theme.textTheme.bodyLarge,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            const _LiveSignalBadge(),
                          ],
                        ),
                      )._careMotionEntry(),
                      const SizedBox(height: 20),
                      ...children.indexed.expand((entry) sync* {
                        yield _MotionEntry(
                          delay: Duration(milliseconds: 70 + entry.$1 * 45),
                          child: entry.$2,
                        );
                        yield const SizedBox(height: 12);
                      }),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MotionEntry extends StatelessWidget {
  const _MotionEntry({required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context) ||
        _careAgentRunningInWidgetTest) {
      return child;
    }

    return child
        .animate(delay: delay)
        .fadeIn(duration: 320.ms, curve: Curves.easeOutCubic)
        .slideY(
          begin: 0.045,
          end: 0,
          duration: 320.ms,
          curve: Curves.easeOutCubic,
        );
  }
}

extension on Widget {
  Widget _careMotionEntry({Duration delay = Duration.zero}) {
    return _MotionEntry(delay: delay, child: this);
  }
}

class _SafetyBanner extends StatelessWidget {
  const _SafetyBanner({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: CareMotion.standard,
      curve: CareMotion.standardCurve,
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.72),
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.36),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.11),
                  borderRadius: const BorderRadius.all(Radius.circular(14)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(icon, color: theme.colorScheme.primary, size: 22),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 5),
                    Text(body, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CareActionTile extends StatelessWidget {
  const _CareActionTile({
    required this.icon,
    required this.title,
    required this.body,
    this.trailing,
    this.leadingLabel,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? trailing;
  final String? leadingLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.74),
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.34),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _CareActionLeading(icon: icon, label: leadingLabel),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 5),
                    Text(body, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 10), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

class _CareActionLeading extends StatelessWidget {
  const _CareActionLeading({required this.icon, this.label});

  final IconData icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.11),
        borderRadius: const BorderRadius.all(Radius.circular(14)),
      ),
      child: SizedBox.square(
        dimension: 44,
        child: Center(
          child: label == null
              ? Icon(icon, color: theme.colorScheme.primary, size: 22)
              : Text(
                  label!,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
      ),
    );
  }
}

class _Section {
  const _Section({
    required this.title,
    required this.heading,
    required this.shortLabel,
    required this.description,
    required this.noticeTitle,
    required this.notice,
    required this.icon,
    required this.selectedIcon,
    required this.items,
  });

  final String title;
  final String heading;
  final String shortLabel;
  final String description;
  final String noticeTitle;
  final String notice;
  final IconData icon;
  final IconData selectedIcon;
  final List<_InfoItem> items;
}

class _InfoItem {
  const _InfoItem({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class _BottomTab {
  const _BottomTab({
    required this.label,
    required this.sectionIndex,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final int sectionIndex;
  final IconData icon;
  final IconData selectedIcon;
}

List<_BottomTab> _bottomTabsForRole(CareAgentUserRole role) {
  return switch (role) {
    CareAgentUserRole.patient => const [
      _BottomTab(
        label: 'Today',
        sectionIndex: 0,
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
      ),
      _BottomTab(
        label: 'Vitals',
        sectionIndex: _vitalsIndex,
        icon: Icons.monitor_heart_outlined,
        selectedIcon: Icons.monitor_heart,
      ),
      _BottomTab(
        label: 'Caro',
        sectionIndex: _chatIndex,
        icon: Icons.chat_bubble_outline,
        selectedIcon: Icons.chat_bubble,
      ),
      _BottomTab(
        label: 'SOS',
        sectionIndex: _sosIndex,
        icon: Icons.emergency_outlined,
        selectedIcon: Icons.emergency,
      ),
    ],
    CareAgentUserRole.caretaker => const [
      _BottomTab(
        label: 'Queue',
        sectionIndex: 0,
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
      ),
      _BottomTab(
        label: 'Alerts',
        sectionIndex: _alertsIndex,
        icon: Icons.notification_important_outlined,
        selectedIcon: Icons.notification_important,
      ),
      _BottomTab(
        label: 'Team',
        sectionIndex: _caretakerIndex,
        icon: Icons.contact_phone_outlined,
        selectedIcon: Icons.contact_phone,
      ),
      _BottomTab(
        label: 'SOS',
        sectionIndex: _sosIndex,
        icon: Icons.emergency_outlined,
        selectedIcon: Icons.emergency,
      ),
    ],
  };
}

const _vitalsIndex = 3;
const _medicinesIndex = 4;
const _chatIndex = 6;
const _sosIndex = 7;
const _caretakerIndex = 8;
const _alertsIndex = 10;

const _sections = <_Section>[
  _Section(
    title: 'Home',
    heading: 'Care status',
    shortLabel: 'Care day overview',
    description: 'A guided view for setup, records, alerts, and escalation.',
    noticeTitle: 'Care records',
    notice:
        'CareAgent separates recorded information from active alerts and always shows the latest known source.',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    items: [],
  ),
  _Section(
    title: 'Onboarding',
    heading: 'Onboarding',
    shortLabel: 'Profile, care team, and permissions',
    description: 'Guided profile setup for first-run care coordination.',
    noticeTitle: 'Profile can be edited',
    notice:
        'Review identity, contacts, permissions, address, and emergency preferences before using alerts.',
    icon: Icons.person_add_alt_1_outlined,
    selectedIcon: Icons.person_add_alt_1,
    items: [
      _InfoItem(
        icon: Icons.badge_outlined,
        title: 'Patient profile',
        body:
            'Collects basic profile, language, conditions, '
            'allergies, and care notes.',
      ),
      _InfoItem(
        icon: Icons.groups_outlined,
        title: 'Care team',
        body:
            'Prepares family, nurse, doctor, and emergency contact '
            'order with verification status.',
      ),
      _InfoItem(
        icon: Icons.watch_outlined,
        title: 'Health sources',
        body:
            'Connects Health Connect, BLE devices, manual entry, '
            'and document/photo fallback.',
      ),
    ],
  ),
  _Section(
    title: 'Consent',
    heading: 'Consent Center',
    shortLabel: 'Separate grants and revocation',
    description: 'Purpose-specific consent controls and revocation states.',
    noticeTitle: 'Consent is separated by purpose',
    notice:
        'Health data, documents, caretaker access, channels, calls, and '
        'location sharing must be granted separately before use.',
    icon: Icons.verified_user_outlined,
    selectedIcon: Icons.verified_user,
    items: [
      _InfoItem(
        icon: Icons.monitor_heart_outlined,
        title: 'Health data consent',
        body:
            'Controls Health Connect, connected devices, '
            'freshness labels, and emergency-use eligibility.',
      ),
      _InfoItem(
        icon: Icons.folder_copy_outlined,
        title: 'Document consent',
        body:
            'Controls uploads, OCR, extraction review, and '
            'answers based on reviewed records.',
      ),
      _InfoItem(
        icon: Icons.share_location_outlined,
        title: 'Escalation consent',
        body:
            'Controls caretaker alerts, AI disclosure, calls, '
            'messages, and emergency-only location sharing.',
      ),
    ],
  ),
  _Section(
    title: 'Vitals',
    heading: 'Vitals',
    shortLabel: 'Latest readings and source status',
    description: 'Recent observations with unit, source, and freshness.',
    noticeTitle: 'Unavailable is not normal',
    notice:
        'Missing or stale data must never be shown as healthy or used to '
        'clear an alert.',
    icon: Icons.monitor_heart_outlined,
    selectedIcon: Icons.monitor_heart,
    items: [
      _InfoItem(
        icon: Icons.favorite_border,
        title: 'Heart rate',
        body:
            'Unavailable. Reading cards show value, unit, source, observed '
            'time, freshness, and reliability tier.',
      ),
      _InfoItem(
        icon: Icons.bloodtype_outlined,
        title: 'Blood pressure and glucose',
        body:
            'Unavailable. Entries can come from Health Connect, BLE, '
            'manual entry, OCR, or reviewed records.',
      ),
      _InfoItem(
        icon: Icons.sensors_outlined,
        title: 'Device health',
        body:
            'Device status shows connected, stale, disconnected, '
            'permission required, and last sync states.',
      ),
    ],
  ),
  _Section(
    title: 'Medicines',
    heading: 'Medicines',
    shortLabel: 'Schedules and reminders',
    description: 'Schedules, dose history, and reminder readiness.',
    noticeTitle: 'No reminders configured',
    notice:
        'Medicine imports from prescriptions require user review before '
        'any reminder becomes active.',
    icon: Icons.medication_outlined,
    selectedIcon: Icons.medication,
    items: [
      _InfoItem(
        icon: Icons.today_outlined,
        title: 'Today',
        body: 'Tracks due, taken, snoozed, skipped, and missed doses.',
      ),
      _InfoItem(
        icon: Icons.alarm_outlined,
        title: 'Local reminder fallback',
        body:
            'Reminders should keep working during backend outages '
            'when notification consent allows it.',
      ),
      _InfoItem(
        icon: Icons.rule_folder_outlined,
        title: 'Review before activation',
        body:
            'Extracted medicine schedules stay inactive until the patient '
            'confirms or edits them.',
      ),
    ],
  ),
  _Section(
    title: 'Documents',
    heading: 'Documents',
    shortLabel: 'Uploads and extraction review',
    description: 'Medical records, prescriptions, and reviewed facts.',
    noticeTitle: 'No documents stored',
    notice:
        'OCR and extraction must show sources and allow correction '
        'before extracted facts are treated as reviewed.',
    icon: Icons.description_outlined,
    selectedIcon: Icons.description,
    items: [
      _InfoItem(
        icon: Icons.upload_file_outlined,
        title: 'Upload',
        body:
            'Entry points for camera, photo library, file picker, '
            'and channel handoff.',
      ),
      _InfoItem(
        icon: Icons.fact_check_outlined,
        title: 'Extraction review',
        body:
            'Review rows show value, confidence, source snippet, '
            'and confirm, edit, or reject actions.',
      ),
      _InfoItem(
        icon: Icons.source_outlined,
        title: 'Source links',
        body:
            'Chat answers about records should cite reviewed source '
            'documents or recent observations.',
      ),
    ],
  ),
  _Section(
    title: 'Chat',
    heading: 'Chat',
    shortLabel: 'Source-grounded assistant',
    description: 'In-app CareAgent conversations with safe boundaries.',
    noticeTitle: 'No medical advice engine active',
    notice:
        'CareAgent chat should say when data is missing or stale and refuse '
        'requests to change medication or ignore clinician advice.',
    icon: Icons.chat_bubble_outline,
    selectedIcon: Icons.chat_bubble,
    items: [
      _InfoItem(
        icon: Icons.forum_outlined,
        title: 'Caro conversation',
        body:
            'Messages should be grounded in reviewed documents, '
            'recent observations, and backend policy.',
      ),
      _InfoItem(
        icon: Icons.approval_outlined,
        title: 'Tool confirmations',
        body:
            'Calls, messages, sharing, contact changes, and '
            'escalation changes require explicit confirmation.',
      ),
      _InfoItem(
        icon: Icons.warning_amber_outlined,
        title: 'Urgent symptoms',
        body:
            'Chat should direct severe or urgent symptoms toward '
            'emergency help instead of trying to manage them locally.',
      ),
    ],
  ),
  _Section(
    title: 'SOS',
    heading: 'SOS',
    shortLabel: 'Emergency readiness',
    description:
        'Manual SOS readiness, multi-contact escalation, and test calls.',
    noticeTitle: 'This screen does not call emergency services',
    notice:
        'In a real emergency, call your local emergency number now. '
        'Automation requires explicit consent, verified contacts, and audit.',
    icon: Icons.emergency_outlined,
    selectedIcon: Icons.emergency,
    items: [
      _InfoItem(
        icon: Icons.contact_phone_outlined,
        title: 'Emergency contacts',
        body:
            'Configures primary caretaker, secondary contact, '
            'doctor, ambulance, hospital, and fallback order.',
      ),
      _InfoItem(
        icon: Icons.timeline_outlined,
        title: 'Escalation timeline',
        body:
            'Incidents should show prompts, messages, calls, '
            'acknowledgements, timestamps, and cancellation paths.',
      ),
      _InfoItem(
        icon: Icons.science_outlined,
        title: 'Drill mode',
        body:
            'Drills must be clearly labeled as test mode and must '
            'never call real emergency services.',
      ),
    ],
  ),
  _Section(
    title: 'Caretaker',
    heading: 'Caretaker',
    shortLabel: 'Primary support contact',
    description: 'Acknowledge-ready caretaker profile for care flows.',
    noticeTitle: 'Caretaker access requires consent',
    notice:
        'Contacts can receive care alerts only after consent and '
        'verification are active.',
    icon: Icons.contact_phone_outlined,
    selectedIcon: Icons.contact_phone,
    items: [
      _InfoItem(
        icon: Icons.person_pin_circle_outlined,
        title: 'Primary caretaker',
        body:
            'Shows the currently configured caretaker and phone number '
            'from onboarding.',
      ),
      _InfoItem(
        icon: Icons.check_circle_outline,
        title: 'Acknowledgement',
        body:
            'Alerts can be acknowledged in the app without implying '
            'clinical resolution.',
      ),
    ],
  ),
  _Section(
    title: 'Channels',
    heading: 'Channels',
    shortLabel: 'Notification readiness',
    description: 'In-app, WhatsApp, Telegram, and voice channel toggles.',
    noticeTitle: 'Channels need consent',
    notice:
        'Messaging and calls are available only for verified contacts with active permission.',
    icon: Icons.settings_input_antenna_outlined,
    selectedIcon: Icons.settings_input_antenna,
    items: [
      _InfoItem(
        icon: Icons.mark_email_read_outlined,
        title: 'Verification',
        body:
            'Channels show verified or unverified status before they can '
            'participate in escalation.',
      ),
      _InfoItem(
        icon: Icons.rule_outlined,
        title: 'Policy gate',
        body:
            'Outbound messages need explicit patient intent and AI '
            'disclosure.',
      ),
    ],
  ),
  _Section(
    title: 'Alerts',
    heading: 'Alerts',
    shortLabel: 'Open and acknowledged events',
    description: 'Manual vitals and emergency drills produce local alerts.',
    noticeTitle: 'Alerts are not diagnoses',
    notice:
        'Open alerts indicate review needs. They do not diagnose, clear, '
        'or replace clinician guidance.',
    icon: Icons.notification_important_outlined,
    selectedIcon: Icons.notification_important,
    items: [
      _InfoItem(
        icon: Icons.monitor_heart_outlined,
        title: 'Vital thresholds',
        body:
            'Abnormal manual readings create review alerts with severity '
            'and source context.',
      ),
      _InfoItem(
        icon: Icons.done_all_outlined,
        title: 'Acknowledgement',
        body:
            'Acknowledging records that someone saw the alert; it does '
            'not mark the patient as healthy.',
      ),
    ],
  ),
];
