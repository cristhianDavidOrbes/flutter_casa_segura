import 'package:flutter_seguridad_en_casa/features/auth/domain/repositories/auth_repository.dart';

class SignOut {
  const SignOut(this.repository);

  final AuthRepository repository;

  Future<void> call() => repository.signOut();
}
