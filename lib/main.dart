import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = CareAgentSupabaseConfig.fromEnvironment();
  SupabaseClient? client;

  if (config.isConfigured) {
    await Supabase.initialize(
      url: config.supabaseUrl,
      anonKey: config.publicKey,
    );
    client = Supabase.instance.client;
  }

  runApp(CareAgentApp(authController: CareAgentAuthController(config, client)));
}

/// Supabase configuration provided at build/run time with `--dart-define`.
class CareAgentSupabaseConfig {
  /// Creates Supabase configuration for CareAgent authentication.
  const CareAgentSupabaseConfig({
    required this.supabaseUrl,
    required this.publicKey,
    required this.redirectUrl,
  });

  /// Reads Supabase configuration from compile-time environment values.
  factory CareAgentSupabaseConfig.fromEnvironment() {
    const url = String.fromEnvironment('SUPABASE_URL');
    const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    const redirectUrl = String.fromEnvironment(
      'SUPABASE_REDIRECT_URL',
      defaultValue: 'app.careagent://auth-callback',
    );

    return CareAgentSupabaseConfig(
      supabaseUrl: url,
      publicKey: publishableKey.isNotEmpty ? publishableKey : anonKey,
      redirectUrl: redirectUrl,
    );
  }

  /// Supabase project URL, for example `https://<project-ref>.supabase.co`.
  final String supabaseUrl;

  /// Publishable or anon key. Never use a service-role key in the app.
  final String publicKey;

  /// OAuth redirect URL allowed in Supabase Auth URL configuration.
  final String redirectUrl;

  /// Whether enough public configuration exists to start Supabase Auth.
  bool get isConfigured => supabaseUrl.isNotEmpty && publicKey.isNotEmpty;
}

/// Authentication state shown by the app shell.
enum CareAgentAuthStatus { unconfigured, signedOut, signingIn, signedIn, error }

/// Small Supabase Auth wrapper used by the Flutter shell.
class CareAgentAuthController extends ChangeNotifier {
  /// Creates an auth controller backed by Supabase when `client` is provided.
  CareAgentAuthController(this.config, SupabaseClient? client)
    : _client = client {
    if (!config.isConfigured || _client == null) {
      _status = CareAgentAuthStatus.unconfigured;
      return;
    }

    _applySession(_client.auth.currentSession);
    _subscription = _client.auth.onAuthStateChange.listen((event) {
      _applySession(event.session);
      notifyListeners();
    });
  }

  /// Creates a deterministic signed-in controller for widget tests.
  CareAgentAuthController.previewSignedIn({String? email})
    : config = const CareAgentSupabaseConfig(
        supabaseUrl: '',
        publicKey: '',
        redirectUrl: 'app.careagent://auth-callback',
      ),
      _client = null,
      _status = CareAgentAuthStatus.signedIn,
      _userEmail = email;

  /// Creates a deterministic unconfigured controller for widget tests.
  CareAgentAuthController.previewUnconfigured()
    : config = const CareAgentSupabaseConfig(
        supabaseUrl: '',
        publicKey: '',
        redirectUrl: 'app.careagent://auth-callback',
      ),
      _client = null,
      _status = CareAgentAuthStatus.unconfigured;

  /// Supabase public configuration used by this session.
  final CareAgentSupabaseConfig config;

  final SupabaseClient? _client;
  StreamSubscription<AuthState>? _subscription;
  CareAgentAuthStatus _status = CareAgentAuthStatus.signedOut;
  String? _userEmail;
  String? _errorMessage;

  /// Current auth state.
  CareAgentAuthStatus get status => _status;

  /// Signed-in user's email when Supabase exposes it.
  String? get userEmail => _userEmail;

  /// Last safe user-facing auth error.
  String? get errorMessage => _errorMessage;

  /// Starts Google OAuth through Supabase Auth.
  Future<void> signInWithGoogle() async {
    if (!config.isConfigured || _client == null) {
      _status = CareAgentAuthStatus.unconfigured;
      _errorMessage = 'Supabase Auth is not configured for this build.';
      notifyListeners();
      return;
    }

    _status = CareAgentAuthStatus.signingIn;
    _errorMessage = null;
    notifyListeners();

    try {
      final launched = await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: config.redirectUrl,
        scopes: 'email profile',
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

      _status = CareAgentAuthStatus.signedOut;
      if (!launched) {
        _errorMessage = 'Could not open Google sign-in.';
      }
    } on AuthException catch (error) {
      _status = CareAgentAuthStatus.error;
      _errorMessage = error.message;
    } catch (_) {
      _status = CareAgentAuthStatus.error;
      _errorMessage = 'Google sign-in could not be started.';
    }

    notifyListeners();
  }

  /// Signs out of Supabase Auth.
  Future<void> signOut() async {
    if (_client == null) {
      _status = CareAgentAuthStatus.unconfigured;
      _userEmail = null;
      notifyListeners();
      return;
    }

    await _client.auth.signOut();
    _applySession(null);
    notifyListeners();
  }

  void _applySession(Session? session) {
    if (session == null) {
      _status = CareAgentAuthStatus.signedOut;
      _userEmail = null;
      return;
    }

    _status = CareAgentAuthStatus.signedIn;
    _userEmail = session.user.email;
    _errorMessage = null;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// Root widget for the Android-first CareAgent MVP shell.
class CareAgentApp extends StatelessWidget {
  /// Creates the CareAgent application.
  const CareAgentApp({required this.authController, super.key});

  /// Auth controller used to gate the protected app shell.
  final CareAgentAuthController authController;

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
      home: _SafetyGate(authController: authController),
    );
  }
}

class _SafetyGate extends StatefulWidget {
  const _SafetyGate({required this.authController});

  final CareAgentAuthController authController;

  @override
  State<_SafetyGate> createState() => _SafetyGateState();
}

class _SafetyGateState extends State<_SafetyGate> {
  bool _acceptedSafetyNotice = false;

  @override
  Widget build(BuildContext context) {
    if (_acceptedSafetyNotice) {
      return _AuthGate(authController: widget.authController);
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
  const _AuthGate({required this.authController});

  final CareAgentAuthController authController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: authController,
      builder: (context, _) {
        if (authController.status == CareAgentAuthStatus.signedIn) {
          return _CareAgentShell(
            userEmail: authController.userEmail,
            onSignOut: authController.signOut,
          );
        }

        return _LoginScreen(authController: authController);
      },
    );
  }
}

class _LoginScreen extends StatelessWidget {
  const _LoginScreen({required this.authController});

  final CareAgentAuthController authController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isConfigured = authController.config.isConfigured;
    final isSigningIn = authController.status == CareAgentAuthStatus.signingIn;

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
                    'CareAgent uses Supabase Auth for account access. '
                    'Patient records, connected devices, messages, and '
                    'emergency workflows stay unavailable until a user is '
                    'authenticated and consent is configured.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 20),
                  if (!isConfigured)
                    _SafetyBanner(
                      title: 'Supabase configuration required',
                      message:
                          'Run the app with SUPABASE_URL and '
                          'SUPABASE_PUBLISHABLE_KEY or SUPABASE_ANON_KEY. '
                          'Never pass a service-role key to Flutter.',
                    )
                  else
                    _SafetyBanner(
                      title: 'Google sign-in',
                      message:
                          'Google OAuth opens through Supabase. Google client '
                          'secrets remain in the Supabase project settings, '
                          'not in the mobile app.',
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
                      onPressed: isConfigured && !isSigningIn
                          ? authController.signInWithGoogle
                          : null,
                      icon: isSigningIn
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: Text(
                        isSigningIn
                            ? 'Opening Google sign-in'
                            : 'Continue with Google',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Configured redirect: ${authController.config.redirectUrl}',
                    style: theme.textTheme.bodySmall,
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
  const _CareAgentShell({required this.userEmail, required this.onSignOut});

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
          ? _HomeScreen(onSelectSection: _selectSection)
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
  const _HomeScreen({required this.onSelectSection});

  final ValueChanged<int> onSelectSection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _ScreenFrame(
      title: 'CareAgent MVP Shell',
      subtitle: 'No health data, contacts, documents, or messages are active.',
      children: [
        _SafetyBanner(
          title: 'Safety posture',
          message:
              'This shell is not monitoring you and cannot contact '
              'emergency services. It only maps the first CareAgent surfaces.',
        ),
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
