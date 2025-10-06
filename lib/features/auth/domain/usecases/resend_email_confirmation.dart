import 'package:flutter_seguridad_en_casa/features/auth/domain/repositories/auth_repository.dart';

class ResendEmailConfirmation {
  const ResendEmailConfirmation(this.repository);

  final AuthRepository repository;

  Future<void> call({required String email, required String redirectUrl}) {
    return repository.resendConfirmationEmail(
      email: email,
      redirectUrl: redirectUrl,
    );
  }
}
