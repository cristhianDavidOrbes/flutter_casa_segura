import 'package:flutter_seguridad_en_casa/features/auth/domain/entities/auth_user.dart';

abstract class AuthRepository {
  AuthUser? get currentUser;

  Future<AuthUser> signInWithEmail({
    required String email,
    required String password,
  });

  Future<AuthUser> signUpWithEmail({
    required String email,
    required String password,
    String? fullName,
  });

  Future<void> signOut();

  Future<void> sendPasswordReset({
    required String email,
    required String redirectUrl,
  });

  Future<void> resendConfirmationEmail({
    required String email,
    required String redirectUrl,
  });

  Future<void> updatePassword({required String newPassword});
}
