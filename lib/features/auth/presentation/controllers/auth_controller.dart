import 'package:flutter_seguridad_en_casa/core/config/environment.dart';
import 'package:flutter_seguridad_en_casa/core/errors/app_failure.dart';
import 'package:flutter_seguridad_en_casa/features/auth/domain/entities/auth_user.dart';
import 'package:flutter_seguridad_en_casa/features/auth/domain/repositories/auth_repository.dart';
import 'package:flutter_seguridad_en_casa/features/auth/domain/usecases/send_password_reset.dart';
import 'package:flutter_seguridad_en_casa/features/auth/domain/usecases/sign_in_with_email.dart';
import 'package:flutter_seguridad_en_casa/features/auth/domain/usecases/sign_out.dart';
import 'package:flutter_seguridad_en_casa/features/auth/domain/usecases/sign_up_with_email.dart';
import 'package:flutter_seguridad_en_casa/features/auth/domain/usecases/update_password.dart';
import 'package:get/get.dart';

class AuthController extends GetxController {
  AuthController({
    required SignInWithEmail signInWithEmail,
    required SignUpWithEmail signUpWithEmail,
    required SendPasswordReset sendPasswordReset,
    required UpdatePassword updatePassword,
    required SignOut signOut,
    required AuthRepository repository,
  })  : _signInWithEmail = signInWithEmail,
        _signUpWithEmail = signUpWithEmail,
        _sendPasswordReset = sendPasswordReset,
        _updatePassword = updatePassword,
        _signOut = signOut,
        _repository = repository;

  final SignInWithEmail _signInWithEmail;
  final SignUpWithEmail _signUpWithEmail;
  final SendPasswordReset _sendPasswordReset;
  final UpdatePassword _updatePassword;
  final SignOut _signOut;
  final AuthRepository _repository;

  final Rxn<AuthUser> currentUser = Rxn<AuthUser>();

  @override
  void onInit() {
    currentUser.value = _repository.currentUser;
    super.onInit();
  }

  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    final user = await _signInWithEmail(email: email, password: password);
    currentUser.value = user;
    return user;
  }

  Future<AuthUser> signUp({
    required String email,
    required String password,
    String? fullName,
  }) {
    return _signUpWithEmail(
      email: email,
      password: password,
      fullName: fullName,
    );
  }

  Future<void> sendPasswordResetEmail({required String email}) {
    return _sendPasswordReset(
      email: email,
      redirectUrl: Environment.supabaseResetRedirect,
    );
  }

  Future<void> changePassword({required String newPassword}) {
    return _updatePassword(newPassword);
  }

  Future<void> signOut() async {
    await _signOut();
    currentUser.value = null;
  }

  void refreshCurrentUser() {
    currentUser.value = _repository.currentUser;
  }
}

AuthFailure mapToAuthFailure(Object error) {
  if (error is AuthFailure) return error;
  return AuthFailure(error.toString(), error);
}
