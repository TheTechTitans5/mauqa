import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

/// Emits whenever the auth state changes so dependent providers refresh.
final authStateProvider = StreamProvider<AuthState>((ref) => ref.watch(supabaseProvider).auth.onAuthStateChange);

final currentUserIdProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentUser?.id;
});

/// User-facing error with a readable message; the original error is kept for logs.
class AppException implements Exception {
  AppException(this.message, {this.cause, this.isOffline = false});
  final String message;
  final Object? cause;
  final bool isOffline;
  @override
  String toString() => message;
}

AppException mapError(Object e) {
  if (e is AppException) return e;
  if (e is SocketException || e is TimeoutException || e.toString().contains('SocketException')) {
    return AppException('No internet connection. Check your connection and try again.', cause: e, isOffline: true);
  }
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) return AppException('Incorrect email/phone or password.', cause: e);
    if (m.contains('already registered')) return AppException('An account already exists for this email or phone.', cause: e);
    if (m.contains('email not confirmed')) return AppException('Please verify your email first — check your inbox.', cause: e);
    if (m.contains('token') && m.contains('expired')) return AppException('The code has expired. Request a new one.', cause: e);
    return AppException(e.message, cause: e);
  }
  if (e is PostgrestException) {
    if (e.code == '42501') return AppException('You do not have permission to do that.', cause: e);
    if (e.code == '23505') return AppException('This already exists.', cause: e);
    if (e.code == '23514') return AppException('Some values are not valid. Please check the form.', cause: e);
    if (e.code == '22023') return AppException(e.message, cause: e);
    return AppException('Could not complete the request. Please try again.', cause: e);
  }
  if (e is FunctionException) {
    final details = e.details;
    final msg = details is Map ? ((details['error'] as Map?)?['message'] as String?) : null;
    return AppException(msg ?? 'The service is temporarily unavailable. Please try again.', cause: e);
  }
  if (e is StorageException) return AppException('File operation failed: ${e.message}', cause: e);
  return AppException('Something went wrong. Please try again.', cause: e);
}

/// Runs [f] and converts any thrown error into an [AppException].
Future<T> guard<T>(Future<T> Function() f) async {
  try {
    return await f().timeout(const Duration(seconds: 30));
  } catch (e) {
    throw mapError(e);
  }
}

String requireUserId(SupabaseClient c) {
  final id = c.auth.currentUser?.id;
  if (id == null) throw AppException('Please sign in again.');
  return id;
}
