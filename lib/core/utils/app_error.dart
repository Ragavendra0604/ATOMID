import 'package:firebase_auth/firebase_auth.dart';

/// An error whose message is safe and useful to show a user.
///
/// Domain code throws this for expected failures (insufficient stock, credit
/// limit exceeded, duplicate code). Anything else is treated as unexpected and
/// reduced to a generic message so internals never reach the screen.
class AppException implements Exception {
  final String message;

  const AppException(this.message);

  @override
  String toString() => 'AppException: $message';
}

/// Turns any thrown object into a sentence worth showing a user.
///
/// Expected failures keep their specific message; everything else gets a
/// generic line, with [fallback] naming the action that failed.
String describeError(
  Object error, {
  String fallback = 'Something went wrong.',
}) {
  if (error is AppException) return error.message;
  if (error is FirebaseAuthException) return _describeAuth(error);
  return fallback;
}

String _describeAuth(FirebaseAuthException error) {
  switch (error.code) {
    case 'invalid-email':
      return 'That email address is not valid.';
    case 'user-disabled':
      return 'This account has been disabled. Contact your store owner.';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return 'Email or password is incorrect.';
    case 'email-already-in-use':
      return 'An account already exists for that email. Try signing in.';
    case 'weak-password':
      return 'Choose a password of at least 6 characters.';
    case 'too-many-requests':
      return 'Too many attempts. Wait a minute and try again.';
    case 'network-request-failed':
      return 'No connection. Your work is saved locally and will sync later.';
    case 'operation-not-allowed':
      return 'Email sign-in is not enabled for this project.';
    default:
      return 'Could not complete that request. Please try again.';
  }
}
