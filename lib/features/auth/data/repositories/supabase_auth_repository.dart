import 'package:flutter_seguridad_en_casa/core/errors/app_failure.dart';
import 'package:flutter_seguridad_en_casa/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:flutter_seguridad_en_casa/features/auth/domain/entities/auth_user.dart';
import 'package:flutter_seguridad_en_casa/features/auth/domain/repositories/auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._remote);

  final AuthRemoteDataSource _remote;

  @override
  AuthUser? get currentUser => _remote.currentUser;

  @override
  Future<void> sendPasswordReset({
    required String email,
    required String redirectUrl,
  }) {
    return _remote.sendPasswordReset(email: email, redirectUrl: redirectUrl);
  }

  @override
  Future<void> signOut() => _remote.signOut();

  @override
  Future<AuthUser> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _remote.signIn(email: email, password: password);
  }

  @override
  Future<AuthUser> signUpWithEmail({
    required String email,
    required String password,
    String? fullName,
  }) {
    return _remote.signUp(email: email, password: password, fullName: fullName);
  }

  @override
  Future<void> resendConfirmationEmail({
    required String email,
    required String redirectUrl,
  }) {
    return _remote.resendEmailConfirmation(
      email: email,
      redirectUrl: redirectUrl,
    );
  }

  @override
  Future<void> updatePassword({required String newPassword}) {
    if (newPassword.trim().isEmpty) {
      throw const AuthFailure('La contrasena no puede estar vacia.');
    }
    return _remote.updatePassword(newPassword: newPassword.trim());
  }
}
