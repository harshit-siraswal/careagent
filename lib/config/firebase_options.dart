import 'package:firebase_core/firebase_core.dart';

/// Firebase web options for browser previews.
///
/// Android uses `android/app/google-services.json` for the CareAgent package
/// registered inside the Studyspace Firebase project.
class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  static bool get hasRequiredWebOptions =>
      _webOptions.apiKey.isNotEmpty &&
      _webOptions.appId.isNotEmpty &&
      _webOptions.messagingSenderId.isNotEmpty &&
      _webOptions.projectId.isNotEmpty;

  static FirebaseOptions get web => _webOptions;

  static const FirebaseOptions _webOptions = FirebaseOptions(
    apiKey: String.fromEnvironment(
      'FIREBASE_API_KEY',
      defaultValue: 'AIzaSyDt_mnuBryHcssBjRSdnPlh9VIC58LKL9Q',
    ),
    appId: String.fromEnvironment(
      'FIREBASE_APP_ID',
      defaultValue: '1:28032445048:web:025624ffdb03cfd54b1b8d',
    ),
    messagingSenderId: String.fromEnvironment(
      'FIREBASE_MESSAGING_SENDER_ID',
      defaultValue: '28032445048',
    ),
    projectId: String.fromEnvironment(
      'FIREBASE_PROJECT_ID',
      defaultValue: 'studyspace-kiet',
    ),
    authDomain: String.fromEnvironment(
      'FIREBASE_AUTH_DOMAIN',
      defaultValue: 'studyspace-kiet.firebaseapp.com',
    ),
    storageBucket: String.fromEnvironment(
      'FIREBASE_STORAGE_BUCKET',
      defaultValue: 'studyspace-kiet.firebasestorage.app',
    ),
  );
}
