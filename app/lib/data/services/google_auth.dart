import 'package:google_sign_in/google_sign_in.dart';

/// The Web OAuth client id from Google Cloud (Clients, type "Web
/// application"). Not a secret: it only names the app the ID token is for,
/// and the sync server checks tokens against it. Empty hides the Google
/// button.
const String googleWebClientId =
    '16049310186-eb57dja4q527kmotnt4krj40anri2331.apps.googleusercontent.com';

/// Sign in with Google on this phone.
abstract class GoogleAuth {
  /// False until a client id is set.
  bool get available;

  /// Shows Google's account picker and returns an ID token for the sync
  /// server, or null when the person closed the picker.
  Future<String?> idToken();
}

class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message);
  final String message;

  @override
  String toString() => 'GoogleAuthException($message)';
}

/// Uses the google_sign_in plugin (Android Credential Manager underneath).
class PluginGoogleAuth implements GoogleAuth {
  PluginGoogleAuth({this.clientId = googleWebClientId});

  final String clientId;
  Future<void>? _ready;

  @override
  bool get available => clientId.isNotEmpty;

  @override
  Future<String?> idToken() async {
    if (!available) return null;
    final signIn = GoogleSignIn.instance;
    try {
      await (_ready ??= signIn.initialize(serverClientId: clientId));
      final account = await signIn.authenticate();
      final token = account.authentication.idToken;
      if (token == null) throw const GoogleAuthException('no ID token');
      return token;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw GoogleAuthException(e.code.name);
    }
  }
}
