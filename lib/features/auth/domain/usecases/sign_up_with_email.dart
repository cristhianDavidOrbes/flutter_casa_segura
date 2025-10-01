import 'package:flutter_seguridad_en_casa/features/auth/domain/entities/auth_user.dart';
import 'package:flutter_seguridad_en_casa/features/auth/domain/repositories/auth_repository.dart';

class SignUpWithEmail {
  const SignUpWithEmail(this.repository);

  final AuthRepository repository;

  Future<AuthUser> call({
    required String email,
    required String password,
    String? fullName,
  }) {
    return repository.signUpWithEmail(
      email: email,
      password: password,
      fullName: fullName,
    );
  }
}
