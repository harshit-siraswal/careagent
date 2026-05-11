import 'package:firebase_core/firebase_core.dart';

/// Firebase web options supplied through `--dart-define` values.
///
/// Android uses `android/app/google-services.json`, copied from the
/// Studyspace Firebase project.
class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  static bool get hasRequiredWebOptions =>
      _webOptions.apiKey.isNotEmpty &&
      _webOptions.appId.isNotEmpty &&
      _webOptions.messagingSenderId.isNotEmpty &&
      _webOptions.projectId.isNotEmpty;

  static FirebaseOptions get web => _webOptions;

  static const FirebaseOptions _webOptions = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_API_KEY', defaultValue: ''),
    appId: String.fromEnvironment('FIREBASE_APP_ID', defaultValue: ''),
    messagingSenderId: String.fromEnvironment(
      'FIREBASE_MESSAGING_SENDER_ID',
      defaultValue: '',
    ),
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: ''),
    authDomain: String.fromEnvironment(
      'FIREBASE_AUTH_DOMAIN',
      defaultValue: '',
    ),
    storageBucket: String.fromEnvironment(
      'FIREBASE_STORAGE_BUCKET',
      defaultValue: '',
    ),
  );
}
