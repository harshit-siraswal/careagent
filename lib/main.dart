import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'config/app_config.dart';
import 'config/firebase_options.dart';
import 'core/careagent_api.dart';

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

/// Small Firebase Auth wrapper used by the Flutter shell.
class CareAgentAuthController extends ChangeNotifier {
  /// Creates a controller after initializing Firebase for the current platform.
  static Future<CareAgentAuthController> create() async {
    try {
      if (kIsWeb) {
        if (!DefaultFirebaseOptions.hasRequiredWebOptions) {
          return CareAgentAuthController.previewUnconfigured(
            message: 'Firebase web configuration is missing for this build.',
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
    super.key,
  }) : apiClient =
           apiClient ??
           CareAgentApiClient(
             config: AppConfig.fromEnvironment(),
             idTokenProvider: authController.idToken,
           );

  /// Auth controller used to gate the protected app shell.
  final CareAgentAuthController authController;

  /// Backend API client used by pilot flows.
  final CareAgentApiClient apiClient;

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF0B6E69);

    return MaterialApp(
      title: 'CareAgent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
        useMaterial3: true,
        cardTheme: const CardThemeData(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      home: _SafetyGate(authController: authController, apiClient: apiClient),
    );
  }
}

class _SafetyGate extends StatefulWidget {
  const _SafetyGate({required this.authController, required this.apiClient});

  final CareAgentAuthController authController;
  final CareAgentApiClient apiClient;

  @override
  State<_SafetyGate> createState() => _SafetyGateState();
}

class _SafetyGateState extends State<_SafetyGate> {
  bool _acceptedSafetyNotice = false;

  @override
  Widget build(BuildContext context) {
    if (_acceptedSafetyNotice) {
      return _AuthGate(
        authController: widget.authController,
        apiClient: widget.apiClient,
      );
    }

    return _SafetyNoticeScreen(
      onAccepted: () {
        setState(() {
          _acceptedSafetyNotice = true;
        });
      },
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate({required this.authController, required this.apiClient});

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
                      title: 'Firebase configuration required',
                      message:
                          'Android builds need google-services.json from the '
                          'Firebase project. Web builds need FIREBASE_* '
                          'dart-define values.',
                    )
                  else
                    _SafetyBanner(
                      title: 'Firebase sign-in',
                      message:
                          'Google and email/password sign-in use the same '
                          'Firebase project configured for Studyspace.',
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
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
    );
  }
}

class _SafetyNoticeScreen extends StatelessWidget {
  const _SafetyNoticeScreen({required this.onAccepted});

  final VoidCallback onAccepted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                  Icon(
                    Icons.health_and_safety_outlined,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'CareAgent safety notice',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'CareAgent is a health coordination shell for reminders, '
                    'records, consent, and care-team workflows. It does not '
                    'diagnose, prescribe, or replace a clinician.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'In an emergency or for severe symptoms, contact local '
                    'emergency services or a qualified medical professional '
                    'directly. Escalation, calls, messages, and location '
                    'sharing must be explicitly configured before use.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onAccepted,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('I understand'),
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

  _Section get _selectedSection => _sections[_selectedIndex];

  void _selectSection(int index) {
    setState(() {
      _selectedIndex = index;
    });
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final selectedSection = _selectedSection;

    return Scaffold(
      appBar: AppBar(
        title: Text(selectedSection.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Text(
                widget.userEmail ?? 'Signed in',
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
              onSelectSection: _selectSection,
            )
          : _PlaceholderScreen(section: selectedSection),
      floatingActionButton: _selectedIndex == _sosIndex
          ? null
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
          Text(
            'Android-first patient app scaffold',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen({required this.apiClient, required this.onSelectSection});

  final CareAgentApiClient apiClient;
  final ValueChanged<int> onSelectSection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _ScreenFrame(
      title: 'CareAgent Pilot',
      subtitle: 'Backend-connected pilot flows for controlled testing.',
      children: [
        _SafetyBanner(
          title: apiClient.isConfigured
              ? 'Backend connected'
              : 'Backend URL required',
          message: apiClient.isConfigured
              ? 'Pilot actions use the configured Render API with Firebase ID tokens.'
              : 'Set CAREAGENT_API_BASE_URL at build time to enable live API calls.',
        ),
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
  final _nameController = TextEditingController(text: 'Pilot Patient');
  final _metricController = TextEditingController(text: 'heart_rate');
  final _valueController = TextEditingController(text: '92');
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
  List<Map<String, dynamic>> _vitals = const [];
  List<Map<String, dynamic>> _alerts = const [];
  List<Map<String, dynamic>> _auditLogs = const [];

  CareAgentApiClient get _api => widget.apiClient;
  String? get _patientId => _patient?['id']?.toString();

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
    });
  }

  Future<void> _grantPilotConsent() async {
    final patientId = _requirePatient();
    await _run('Pilot consent granted.', () async {
      await _api.grantConsent(
        patientId: patientId,
        consentType: 'pilot_mvp',
        scope: {
          'health_data': true,
          'audit': true,
          'emergency_simulation': true,
        },
      );
    });
  }

  Future<void> _submitVital() async {
    final patientId = _requirePatient();
    final value = num.tryParse(_valueController.text.trim());
    if (value == null) {
      setState(() => _status = 'Enter a numeric vital value.');
      return;
    }
    await _run('Vital submitted.', () async {
      await _api.submitManualVital(
        patientId: patientId,
        metricCode: _metricController.text.trim(),
        value: value,
        unit: _unitController.text.trim(),
      );
      _vitals = await _api.latestVitals(patientId);
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
    await _run('Document placeholder created.', () async {
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
                    'Pilot vertical slice',
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
              _SafetyBanner(title: 'Pilot status', message: _status!),
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
                  onPressed: _busy || _patientId == null
                      ? null
                      : _grantPilotConsent,
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text('Grant Consent'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy || _patientId == null ? null : _initDocument,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Document Placeholder'),
                ),
              ],
            ),
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
                  label: const Text('Submit Vital'),
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
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _PilotSummary extends StatelessWidget {
  const _PilotSummary({
    required this.patient,
    required this.vitals,
    required this.alerts,
    required this.riskEvent,
    required this.escalationRun,
    required this.document,
    required this.auditLogs,
  });

  final Map<String, dynamic>? patient;
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

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.section});

  final _Section section;

  @override
  Widget build(BuildContext context) {
    return _ScreenFrame(
      title: section.heading,
      subtitle: section.description,
      children: [
        _SafetyBanner(title: section.noticeTitle, message: section.notice),
        for (final item in section.items)
          _InfoTile(icon: item.icon, title: item.title, body: item.body),
      ],
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
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 20),
          ...children.expand((child) sync* {
            yield child;
            yield const SizedBox(height: 12);
          }),
        ],
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

    return Card(
      color: theme.colorScheme.secondaryContainer,
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
                      fontWeight: FontWeight.w700,
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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(section.icon, color: theme.colorScheme.primary),
              const Spacer(),
              Text(
                section.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
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
    heading: 'CareAgent MVP Shell',
    shortLabel: 'Safety-first starting point',
    description: 'A conservative app shell for the Android-first MVP.',
    noticeTitle: 'No monitoring active',
    notice: 'This scaffold does not collect or interpret health data.',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    items: [],
  ),
  _Section(
    title: 'Onboarding',
    heading: 'Onboarding',
    shortLabel: 'Profile, care team, and permissions',
    description: 'Placeholder flow for patient profile setup and first run.',
    noticeTitle: 'Setup is local only',
    notice:
        'No account, contacts, permissions, or health data are saved by '
        'this shell.',
    icon: Icons.person_add_alt_1_outlined,
    selectedIcon: Icons.person_add_alt_1,
    items: [
      _InfoItem(
        icon: Icons.badge_outlined,
        title: 'Patient profile',
        body:
            'Future form for basic profile, language, conditions, '
            'allergies, and care notes.',
      ),
      _InfoItem(
        icon: Icons.groups_outlined,
        title: 'Care team',
        body:
            'Future setup for family, nurse, doctor, and emergency contact '
            'order with verification status.',
      ),
      _InfoItem(
        icon: Icons.watch_outlined,
        title: 'Health sources',
        body:
            'Future handoff for Health Connect, BLE devices, manual entry, '
            'and document/photo fallback.',
      ),
    ],
  ),
  _Section(
    title: 'Consent',
    heading: 'Consent Center',
    shortLabel: 'Separate grants and revocation',
    description: 'Placeholder for purpose-specific consent controls.',
    noticeTitle: 'No consent has been granted',
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
            'Future controls for Health Connect, connected devices, '
            'freshness labels, and emergency-use eligibility.',
      ),
      _InfoItem(
        icon: Icons.folder_copy_outlined,
        title: 'Document consent',
        body:
            'Future controls for uploads, OCR, extraction review, and '
            'source-grounded answers.',
      ),
      _InfoItem(
        icon: Icons.share_location_outlined,
        title: 'Escalation consent',
        body:
            'Future controls for caretaker alerts, AI disclosure, calls, '
            'messages, and emergency-only location sharing.',
      ),
    ],
  ),
  _Section(
    title: 'Vitals',
    heading: 'Vitals',
    shortLabel: 'Latest readings and source status',
    description: 'Placeholder dashboard for recent observations.',
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
            'Unavailable. Future cards show value, unit, source, observed '
            'time, freshness, and reliability tier.',
      ),
      _InfoItem(
        icon: Icons.bloodtype_outlined,
        title: 'Blood pressure and glucose',
        body:
            'Unavailable. Future entries can come from Health Connect, BLE, '
            'manual entry, OCR, or reviewed records.',
      ),
      _InfoItem(
        icon: Icons.sensors_outlined,
        title: 'Device health',
        body:
            'Future device status shows connected, stale, disconnected, '
            'permission required, and last sync states.',
      ),
    ],
  ),
  _Section(
    title: 'Medicines',
    heading: 'Medicines',
    shortLabel: 'Schedules and reminders',
    description: 'Placeholder for schedules, dose history, and reminders.',
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
        body: 'Future list for due, taken, snoozed, skipped, and missed doses.',
      ),
      _InfoItem(
        icon: Icons.alarm_outlined,
        title: 'Local reminder fallback',
        body:
            'Future reminders should keep working during backend outages '
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
    description: 'Placeholder for medical records and prescriptions.',
    noticeTitle: 'No documents stored',
    notice:
        'Future OCR and extraction must show sources and allow correction '
        'before extracted facts are treated as reviewed.',
    icon: Icons.description_outlined,
    selectedIcon: Icons.description,
    items: [
      _InfoItem(
        icon: Icons.upload_file_outlined,
        title: 'Upload',
        body:
            'Future entry points for camera, photo library, file picker, '
            'and channel handoff.',
      ),
      _InfoItem(
        icon: Icons.fact_check_outlined,
        title: 'Extraction review',
        body:
            'Future review rows show value, confidence, source snippet, '
            'and confirm, edit, or reject actions.',
      ),
      _InfoItem(
        icon: Icons.source_outlined,
        title: 'Source links',
        body:
            'Future chat answers about records should cite reviewed source '
            'documents or recent observations.',
      ),
    ],
  ),
  _Section(
    title: 'Chat',
    heading: 'Chat',
    shortLabel: 'Source-grounded assistant placeholder',
    description: 'Placeholder for in-app CareAgent conversations.',
    noticeTitle: 'No medical advice engine active',
    notice:
        'Future chat should say when data is missing or stale and refuse '
        'requests to change medication or ignore clinician advice.',
    icon: Icons.chat_bubble_outline,
    selectedIcon: Icons.chat_bubble,
    items: [
      _InfoItem(
        icon: Icons.forum_outlined,
        title: 'Caro conversation',
        body:
            'Future messages should be grounded in reviewed documents, '
            'recent observations, and backend policy.',
      ),
      _InfoItem(
        icon: Icons.approval_outlined,
        title: 'Tool confirmations',
        body:
            'Future calls, messages, sharing, contact changes, and '
            'escalation changes require explicit confirmation.',
      ),
      _InfoItem(
        icon: Icons.warning_amber_outlined,
        title: 'Urgent symptoms',
        body:
            'Future chat should direct severe or urgent symptoms toward '
            'emergency help instead of trying to manage them locally.',
      ),
    ],
  ),
  _Section(
    title: 'SOS',
    heading: 'SOS',
    shortLabel: 'Emergency readiness placeholder',
    description: 'Placeholder for manual SOS and escalation status.',
    noticeTitle: 'This screen does not call emergency services',
    notice:
        'In a real emergency, call your local emergency number now. Future '
        'automation requires explicit consent, verified contacts, and audit.',
    icon: Icons.emergency_outlined,
    selectedIcon: Icons.emergency,
    items: [
      _InfoItem(
        icon: Icons.contact_phone_outlined,
        title: 'Emergency contacts',
        body:
            'Future configuration for primary caretaker, secondary contact, '
            'doctor, ambulance, hospital, and fallback order.',
      ),
      _InfoItem(
        icon: Icons.timeline_outlined,
        title: 'Escalation timeline',
        body:
            'Future incidents should show prompts, messages, calls, '
            'acknowledgements, timestamps, and cancellation paths.',
      ),
      _InfoItem(
        icon: Icons.science_outlined,
        title: 'Simulation mode',
        body:
            'Future drills must be clearly labeled as test mode and must '
            'never call real emergency services.',
      ),
    ],
  ),
];
