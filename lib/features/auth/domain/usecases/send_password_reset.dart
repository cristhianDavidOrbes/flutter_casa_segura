import 'package:flutter_seguridad_en_casa/features/auth/domain/repositories/auth_repository.dart';

class SendPasswordReset {
  const SendPasswordReset(this.repository);

  final AuthRepository repository;

  Future<void> call({required String email, required String redirectUrl}) {
    return repository.sendPasswordReset(email: email, redirectUrl: redirectUrl);
  }
}
