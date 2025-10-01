import 'package:flutter_seguridad_en_casa/core/config/environment.dart';
import 'package:flutter_seguridad_en_casa/core/errors/app_failure.dart';
import 'package:flutter_seguridad_en_casa/features/auth/domain/entities/auth_user.dart' as domain;
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRemoteDataSource {
  AuthRemoteDataSource(this._client);

  final SupabaseClient _client;

  domain.AuthUser _mapUser(User user) {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    return domain.AuthUser(
      id: user.id,
      email: user.email ?? '',
      name: metadata['full_name'] as String?,
      emailConfirmed: user.emailConfirmedAt != null,
    );
  }

  domain.AuthUser? get currentUser {
    final user = _client.auth.currentUser;
    return user != null ? _mapUser(user) : null;
  }

  Future<domain.AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final user = response.user;
      if (user == null) {
        throw const AuthFailure('No se pudo crear la sesion.');
      }
      return _mapUser(user);
    } on AuthException catch (e) {
      throw AuthFailure(e.message, e);
    } catch (e) {
      throw AuthFailure('Error inesperado al iniciar sesion.', e);
    }
  }

  Future<domain.AuthUser> signUp({
    required String email,
    required String password,
    String? fullName,
  }) async {
    try {
      final sanitizedFullName = fullName?.trim();
      final metadata = (sanitizedFullName?.isNotEmpty ?? false)
          ? {'full_name': sanitizedFullName}
          : null;

      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: metadata,
        emailRedirectTo: Environment.supabaseEmailRedirect,
      );
      final user = response.user;
      if (user == null) {
        throw const AuthFailure('No se pudo registrar al usuario.');
      }
      return _mapUser(user);
    } on AuthException catch (e) {
      throw AuthFailure(e.message, e);
    } catch (e) {
      throw AuthFailure('Error inesperado al registrar usuario.', e);
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } on AuthException catch (e) {
      throw AuthFailure(e.message, e);
    } catch (e) {
      throw AuthFailure('Error inesperado al cerrar sesion.', e);
    }
  }

  Future<void> sendPasswordReset({
    required String email,
    required String redirectUrl,
  }) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email,
        redirectTo: redirectUrl,
      );
    } on AuthException catch (e) {
      throw AuthFailure(e.message, e);
    } catch (e) {
      throw AuthFailure('Error inesperado al enviar la recuperacion.', e);
    }
  }

  Future<void> updatePassword({required String newPassword}) async {
    try {
      await _client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
    } on AuthException catch (e) {
      throw AuthFailure(e.message, e);
    } catch (e) {
      throw AuthFailure('Error inesperado al actualizar la contrasena.', e);
    }
  }
}
