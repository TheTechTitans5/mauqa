import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../supabase_client.dart';

class AuthRepository {
  AuthRepository(this._c);
  final SupabaseClient _c;

  Session? get session => _c.auth.currentSession;

  Future<void> signUpWithEmail({required String email, required String password, required String fullName, required String language}) =>
      guard(() => _c.auth.signUp(
            email: email.trim(),
            password: password,
            emailRedirectTo: Env.authRedirect,
            data: {'full_name': fullName.trim(), 'preferred_language': language, 'accepted_terms': 'true'},
          ));

  /// Phone sign-up sends an SMS OTP (requires an SMS provider configured in Supabase Auth).
  Future<void> signUpWithPhone({required String phone, required String password, required String fullName, required String language}) =>
      guard(() => _c.auth.signUp(
            phone: phone,
            password: password,
            data: {'full_name': fullName.trim(), 'preferred_language': language, 'accepted_terms': 'true'},
          ));

  Future<void> signInWithEmail(String email, String password) =>
      guard(() => _c.auth.signInWithPassword(email: email.trim(), password: password));

  Future<void> signInWithPhone(String phone, String password) => guard(() => _c.auth.signInWithPassword(phone: phone, password: password));

  Future<void> sendPhoneOtp(String phone) => guard(() => _c.auth.signInWithOtp(phone: phone));

  Future<void> verifyPhoneOtp(String phone, String token) =>
      guard(() => _c.auth.verifyOTP(phone: phone, token: token.trim(), type: OtpType.sms));

  Future<void> resendEmailConfirmation(String email) =>
      guard(() => _c.auth.resend(type: OtpType.signup, email: email.trim(), emailRedirectTo: Env.authRedirect));

  Future<void> sendPasswordReset(String email) =>
      guard(() => _c.auth.resetPasswordForEmail(email.trim(), redirectTo: Env.authRedirect));

  Future<void> updatePassword(String newPassword) => guard(() => _c.auth.updateUser(UserAttributes(password: newPassword)));

  /// Re-authenticates before changing the password from Settings.
  Future<void> changePassword({required String current, required String next}) => guard(() async {
        final user = _c.auth.currentUser;
        if (user == null) throw AppException('Please sign in again.');
        if (user.email != null) {
          await _c.auth.signInWithPassword(email: user.email!, password: current);
        } else if (user.phone != null) {
          await _c.auth.signInWithPassword(phone: user.phone!, password: current);
        }
        await _c.auth.updateUser(UserAttributes(password: next));
      });

  Future<void> signInWithGoogle() => guard(() async {
        if (!Env.googleSignInEnabled) throw AppException('Google sign-in is not configured for this build.');
        await _c.auth.signInWithOAuth(OAuthProvider.google, redirectTo: Env.authRedirect);
      });

  Future<void> signOut() => guard(() => _c.auth.signOut());
}

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ref.watch(supabaseProvider)));
