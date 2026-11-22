/// Build-time configuration passed with --dart-define (or --dart-define-from-file=env/dev.json).
///
/// Only PUBLIC values belong here: the Supabase URL and anon key are designed to be shipped in apps and are
/// protected by Row Level Security. NEVER put the service-role key or any API secret in the app.
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const authRedirect = String.fromEnvironment('AUTH_REDIRECT', defaultValue: 'io.mauqa.app://login-callback');
  static const googleSignInEnabled = bool.fromEnvironment('GOOGLE_SIGN_IN_ENABLED');

  // Firebase Cloud Messaging (optional). Without these, push is disabled and in-app notifications still work.
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
  static bool get pushConfigured =>
      firebaseApiKey.isNotEmpty && firebaseAppId.isNotEmpty && firebaseSenderId.isNotEmpty && firebaseProjectId.isNotEmpty;
}
