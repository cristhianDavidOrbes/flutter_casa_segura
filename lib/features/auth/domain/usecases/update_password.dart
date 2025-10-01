import 'package:flutter_seguridad_en_casa/features/auth/domain/repositories/auth_repository.dart';

class UpdatePassword {
  const UpdatePassword(this.repository);

  final AuthRepository repository;

  Future<void> call(String newPassword) {
    return repository.updatePassword(newPassword: newPassword);
  }
}
