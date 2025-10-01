import 'package:flutter_seguridad_en_casa/features/auth/domain/entities/auth_user.dart';
import 'package:flutter_seguridad_en_casa/features/auth/domain/repositories/auth_repository.dart';

class SignInWithEmail {
  const SignInWithEmail(this.repository);

  final AuthRepository repository;

  Future<AuthUser> call({
    required String email,
    required String password,
  }) {
    return repository.signInWithEmail(email: email, password: password);
  }
}
