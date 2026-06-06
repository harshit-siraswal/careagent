import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
            message:
                'This browser preview is missing Firebase web configuration. '
                'Android app builds use android/app/google-services.json.',
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
    _errorMessage = 'Firebase Auth is not configured for this build.';
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
        return 'This sign-in method is not enabled in Firebase Auth.';
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
      return 'Google Sign-In configuration error. Check the Firebase Android client package and SHA fingerprint.';
    }
    if (message.contains('sign_in_canceled') || message.contains('canceled')) {
      return 'Google sign-in was cancelled.';
    }
    return error.message ?? 'Google sign-in failed.';
  }

  final message = error.toString().replaceFirst('Exception: ', '').trim();
  if (_looksLikeGoogleConfigIssue(message.toLowerCase())) {
    return 'Google Sign-In configuration error. Check the Firebase Android client package and SHA fingerprint.';
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
    await widget.safetyNoticeStore.accept();
    if (!mounted) return;
    setState(() {
      _acceptedSafetyNotice = true;
    });
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
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate({
    required this.authController,
    required this.apiClient,
    super.key,
  });

  final CareAgentAuthController authController;
  final CareAgentApiClient apiClient;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: authController,
      builder: (context, _) {
        if (authController.status == CareAgentAuthStatus.signedIn) {
          return _CareAgentShell(
            apiClient: apiClient,
            userEmail: authController.userEmail,
            onSignOut: authController.signOut,
          );
        }

        return _LoginScreen(authController: authController);
      },
    );
  }
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen({required this.authController});

  final CareAgentAuthController authController;

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

    final theme = Theme.of(context);
    final isConfigured = authController.isConfigured;
    final isSigningIn = authController.status == CareAgentAuthStatus.signingIn;
    final isBusy = isSigningIn || _isResettingPassword;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CaroCompanion(
                    state: CaroState.neutral,
                    title: 'Caro keeps the setup guided',
                    message:
                        'Sign in first, then CareAgent can connect your '
                        'profile, consent, vitals, and simulation history.',
                  ),
                  const SizedBox(height: 24),
                  Icon(
                    Icons.lock_person_outlined,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Sign in to CareAgent',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'CareAgent uses Firebase Auth for account access. '
                    'Patient records, connected devices, messages, and '
                    'emergency workflows stay unavailable until a user is '
                    'authenticated and consent is configured.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 20),
                  if (!isConfigured)
                    _SafetyBanner(
                      title: kIsWeb
                          ? 'Browser preview configuration required'
                          : 'Android Firebase configuration required',
                      message: kIsWeb
                          ? 'This is the browser build. It needs Firebase web '
                                'options through defaults or FIREBASE_* '
                                'dart-define values. The installed Android app '
                                'uses android/app/google-services.json.'
                          : 'The Android app needs a google-services.json '
                                'registered for package app.careagent.patient.',
                    )
                  else
                    _SafetyBanner(
                      title: 'Firebase sign-in',
                      message:
                          'Google and email/password sign-in use the '
                          'configured Firebase project for CareAgent access.',
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
                      onPressed: isConfigured && !isBusy
                          ? _signInWithGoogle
                          : null,
                      icon: isSigningIn
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: Text(
                        isSigningIn ? 'Signing in' : 'Continue with Google',
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or use email',
                          style: theme.textTheme.bodySmall,
                        ),
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
                            tooltip: _obscurePassword
                                ? 'Show password'
                                : 'Hide password',
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
                            onPressed: isConfigured && !isBusy
                                ? _submitEmail
                                : null,
                            child: Text(
                              _isLogin ? 'Sign in' : 'Create account',
                            ),
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
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailVerificationScreen() {
    final theme = Theme.of(context);
    final email = authController.userEmail ?? _emailController.text.trim();
    final isBusy = _isCheckingVerification || _isResendingVerification;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
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
    return Scaffold(
      body: SafeArea(
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
              'and simulation-only escalation without replacing a clinician.',
          compact: compact,
        ),
        SizedBox(height: compact ? 20 : 32),
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
    );
  }
}

class _SafetyNoticeContent extends StatelessWidget {
  const _SafetyNoticeContent({required this.onAccepted});

  final VoidCallback onAccepted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        border: Border.all(color: theme.colorScheme.outline),
      ),
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
    required this.userEmail,
    required this.onSignOut,
  });

  final CareAgentApiClient apiClient;
  final String? userEmail;
  final Future<void> Function() onSignOut;

  @override
  State<_CareAgentShell> createState() => _CareAgentShellState();
}

class _CareAgentShellState extends State<_CareAgentShell> {
  int _selectedIndex = 0;
  late final _LocalCareState _localCareState;

  _Section get _selectedSection => _sections[_selectedIndex];

  @override
  void initState() {
    super.initState();
    _localCareState = _LocalCareState();
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
    final showUserIdentity = width >= 720;
    final compactFab = width < 480;

    return Scaffold(
      appBar: AppBar(
        title: Text(selectedSection.title),
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
          const _DrawerHeader(),
          for (final section in _sections)
            NavigationDrawerDestination(
              icon: Icon(section.icon),
              selectedIcon: Icon(section.selectedIcon),
              label: Text(section.title),
            ),
        ],
      ),
      body: _selectedIndex == 0
          ? _HomeScreen(
              apiClient: widget.apiClient,
              localCareState: _localCareState,
              onSelectSection: _selectSection,
            )
          : _CareFeatureScreen(
              section: selectedSection,
              careState: _localCareState,
            ),
      floatingActionButton: _selectedIndex == _sosIndex
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
  const _DrawerHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.volunteer_activism_outlined,
            size: 36,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'CareAgent',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text('Soft clinical companion', style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen({
    required this.apiClient,
    required this.localCareState,
    required this.onSelectSection,
  });

  final CareAgentApiClient apiClient;
  final _LocalCareState localCareState;
  final ValueChanged<int> onSelectSection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _ScreenFrame(
      title: 'Care status',
      subtitle:
          'A guided CareAgent workspace for setup, consent, vitals, and '
          'simulation-only escalation.',
      children: [
        const CaroCompanion(
          state: CaroState.neutral,
          title: 'Caro watches the care signals',
          message:
              'Start with a patient profile, consent, and a manual reading. '
              'CareAgent will keep source, freshness, and simulation status '
              'visible as you test the MVP flow.',
        ),
        _SafetyBanner(
          title: apiClient.isConfigured
              ? 'Backend connection ready'
              : 'Connect the backend before live flows',
          message: apiClient.isConfigured
              ? 'MVP actions use the configured Render API with Firebase ID tokens.'
              : 'Set CAREAGENT_API_BASE_URL at build time to enable live API calls.',
        ),
        _LocalCareSnapshot(careState: localCareState),
        _HackathonDemoPanel(careState: localCareState),
        _PilotWorkspace(apiClient: apiClient),
        Text(
          'Setup areas',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        GridView.builder(
          itemCount: _sections.length - 1,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 260,
            mainAxisExtent: 156,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            final sectionIndex = index + 1;
            final section = _sections[sectionIndex];

            return _SectionCard(
              section: section,
              onTap: () => onSelectSection(sectionIndex),
            );
          },
        ),
      ],
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
                    'MVP sandbox workspace',
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
          'Demo context loaded for Ravi Sharma. I can explain vitals, '
          'medicine schedule, reviewed documents, and the simulated '
          'WhatsApp/Telegram/voice escalation plan.',
    ),
    _LocalMessage(
      author: 'Caro',
      body:
          'Critical demo alert: heart_rate 132 bpm and SpO2 91% are recent. '
          'CareAgent will notify verified contacts in simulation mode and '
          'will not call real emergency services.',
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
      consent: 'disabled in demo',
      lastAction: 'MVP requires legal/provider approval',
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
      title: 'Policy gate passed for simulation',
      body:
          'Health data, caretaker, WhatsApp, Telegram, voice, and simulation '
          'consents are active. Real emergency automation is disabled.',
    ),
  ];
  final List<_LocalChannel> channels = [
    _LocalChannel(
      name: 'In-app push',
      provider: 'FCM/APNs',
      readiness: 'ready',
      enabled: true,
      verified: true,
      contacts: 'Patient app + Meera device',
      mode: 'sandbox-ready',
      nextStep: 'Add production Firebase sender credentials.',
      template: 'urgent_vitals_alert_v1',
    ),
    _LocalChannel(
      name: 'WhatsApp',
      provider: 'Cloud API or approved BSP',
      readiness: 'template plan ready',
      enabled: true,
      verified: true,
      contacts: 'Meera, Dr. Neha',
      mode: 'simulation now',
      nextStep:
          'Need WABA, approved alert templates, webhook secret, phone ID.',
      template: 'critical_escalation_caretaker_v1',
    ),
    _LocalChannel(
      name: 'Telegram',
      provider: 'Telegram Bot API',
      readiness: 'linked pilot contact',
      enabled: true,
      verified: true,
      contacts: 'Amit',
      mode: 'simulation now',
      nextStep: 'Need bot token, webhook URL, signed link/nonce flow.',
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
          '5 minutes. Caretaker escalation is running in simulation mode.',
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
      status: 'MVP gated',
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
      sosTimeline.any((event) => event.title == 'Simulation started');

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
          title: 'Simulation started',
          body:
              'Critical vitals scenario started. No real emergency service '
              'or provider was contacted.',
        ),
      )
      ..add(
        _LocalTimelineEvent(
          title: 'WhatsApp and Telegram sent',
          body:
              'Meera receives WhatsApp template with ack link. Amit receives '
              'Telegram bot callback. Both messages are simulation records.',
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
            'WhatsApp, Telegram, and voice test-call actions are in the '
            'incident timeline. This is a test run only.',
        severity: 'critical',
        evidence: 'Simulation run CRIT-HR-001',
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
            '$caretakerName acknowledged the simulated escalation from the '
            'WhatsApp link and voice DTMF path.',
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
                'to verified contacts in simulation mode; contact emergency '
                'services directly for severe symptoms.';
    }
    if (lowered.contains('sos') || lowered.contains('emergency')) {
      return 'For a real emergency, call local emergency services now. MVP '
          'automation will first notify Meera by WhatsApp, Amit by Telegram, '
          'then place an AI-disclosed test call. Public emergency calling is '
          'disabled until explicit policy and provider approval.';
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
  const _CareFeatureScreen({required this.section, required this.careState});

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
      'SOS' => 'Caro keeps this in simulation mode',
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

class _HackathonDemoPanel extends StatelessWidget {
  const _HackathonDemoPanel({required this.careState});

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
                    'Hackathon demo scenario',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in careState.consents.entries)
          SwitchListTile(
            value: entry.value,
            onChanged: (value) => careState.setConsent(entry.key, value),
            secondary: Icon(
              entry.value
                  ? Icons.verified_user_outlined
                  : Icons.privacy_tip_outlined,
            ),
            title: Text(entry.key),
            subtitle: Text(
              entry.value
                  ? 'Active for this local pilot workspace.'
                  : 'Disabled. Related actions stay blocked or simulation-only.',
            ),
          ),
        const SizedBox(height: 8),
        const _InfoTile(
          icon: Icons.rule_outlined,
          title: 'MVP gate',
          body:
              'Real WhatsApp, Telegram, and voice dispatch will require '
              'verified contacts, provider webhooks, idempotency keys, '
              'rate limits, and audit records before production use.',
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
          Card(
            child: ListTile(
              leading: const Icon(Icons.medication_outlined),
              title: Text(medicine.name),
              subtitle: Text(
                '${medicine.dose} - ${medicine.schedule}\n'
                '${medicine.status} - ${medicine.source}',
              ),
              trailing: medicine.status == 'taken'
                  ? const Icon(Icons.check_circle_outline)
                  : TextButton(
                      onPressed: () =>
                          widget.careState.markMedicineTaken(medicine),
                      child: const Text('Taken'),
                    ),
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
          Card(
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(document.name),
              subtitle: Text(
                '${document.kind} - ${document.status}\n'
                'Source: ${document.source}\n'
                'Facts: ${document.extractedFacts.join('; ')}',
              ),
              trailing: document.status == 'reviewed'
                  ? const Icon(Icons.fact_check_outlined)
                  : TextButton(
                      onPressed: () =>
                          widget.careState.markDocumentReviewed(document),
                      child: const Text('Mark reviewed'),
                    ),
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
              'Start emergency simulation?',
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
                careState.sosRunning
                    ? 'Restart Simulation'
                    : 'Start Simulation',
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
          const Text('No simulation has been started yet.'),
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
          Card(
            child: ListTile(
              leading: const Icon(Icons.notification_important_outlined),
              title: Text(alert.title),
              subtitle: Text(
                '${alert.severity} - ${alert.status}\n${alert.body}\n'
                'Evidence: ${alert.evidence}\nNext: ${alert.nextAction}',
              ),
              trailing: alert.status == 'open'
                  ? TextButton(
                      onPressed: () => careState.acknowledgeAlert(alert),
                      child: const Text('Ack'),
                    )
                  : const Icon(Icons.check_circle_outline),
            ),
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
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text(contact.priority.toString())),
        title: Text(contact.name),
        subtitle: Text(
          '${contact.role} - ${contact.relation}\n'
          '${contact.phone}\n'
          'Channels: ${contact.channels.join(', ')}\n'
          'Verification: ${contact.verification}; consent: ${contact.consent}\n'
          '${contact.lastAction}',
        ),
        trailing: const Icon(Icons.verified_outlined),
      ),
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: channel.enabled,
              onChanged: onChanged,
              secondary: Icon(
                channel.verified
                    ? Icons.mark_email_read_outlined
                    : Icons.mark_email_unread_outlined,
                color: theme.colorScheme.primary,
              ),
              title: Text(channel.name),
              subtitle: Text('${channel.provider} - ${channel.readiness}'),
            ),
            Text(
              'Mode: ${channel.mode}\n'
              'Contacts: ${channel.contacts}\n'
              'Template/script: ${channel.template}\n'
              'Next setup: ${channel.nextStep}',
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
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text(action.step)),
        title: Text('${action.channel} to ${action.target}'),
        subtitle: Text('${action.status} - ${action.eta}\n${action.detail}'),
        trailing: const Icon(Icons.route_outlined),
      ),
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
                      Text(title, style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text(subtitle, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 20),
                      ...children.expand((child) sync* {
                        yield child;
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section, required this.onTap});

  final _Section section;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(section.icon, color: theme.colorScheme.primary),
                    const Spacer(),
                    Text(section.title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text(
                      section.shortLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
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

    return Card(
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(body),
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

const _sosIndex = 7;

const _sections = <_Section>[
  _Section(
    title: 'Home',
    heading: 'CareAgent Hackathon Demo',
    shortLabel: 'Synthetic end-to-end care flow',
    description:
        'A guided MVP demo for patient setup, records, alerts, and escalation.',
    noticeTitle: 'Synthetic demo data',
    notice:
        'The visible patient, vitals, documents, channel messages, and calls '
        'are seeded demo records unless a backend action is explicitly run.',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    items: [],
  ),
  _Section(
    title: 'Onboarding',
    heading: 'Onboarding',
    shortLabel: 'Profile, care team, and permissions',
    description: 'Guided profile setup for first-run care coordination.',
    noticeTitle: 'Demo profile can be edited',
    notice:
        'The seeded profile is synthetic. Production onboarding must verify '
        'identity, contacts, consent, address, and emergency policy.',
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
            'source-grounded answers.',
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
        title: 'Simulation mode',
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
    description: 'Acknowledge-ready caretaker profile for local pilot flows.',
    noticeTitle: 'Caretaker access requires consent',
    notice:
        'Contacts can receive simulation alerts only after consent and '
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
    noticeTitle: 'External channels are simulated',
    notice:
        'Toggles here simulate readiness only. Real messaging requires '
        'provider setup, consent, and audit logging.',
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
    description: 'Manual vitals and SOS simulations produce local alerts.',
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
