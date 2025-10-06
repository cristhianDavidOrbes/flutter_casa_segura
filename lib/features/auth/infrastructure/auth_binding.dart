import 'package:flutter_seguridad_en_casa/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:flutter_seguridad_en_casa/features/auth/data/repositories/supabase_auth_repository.dart';
import 'package:flutter_seguridad_en_casa/features/auth/domain/usecases/send_password_reset.dart';
import 'package:flutter_seguridad_en_casa/features/auth/domain/usecases/sign_in_with_email.dart';
import 'package:flutter_seguridad_en_casa/features/auth/domain/usecases/sign_out.dart';
import 'package:flutter_seguridad_en_casa/features/auth/domain/usecases/sign_up_with_email.dart';
import 'package:flutter_seguridad_en_casa/features/auth/domain/usecases/update_password.dart';
import 'package:flutter_seguridad_en_casa/features/auth/domain/usecases/resend_email_confirmation.dart';
import 'package:flutter_seguridad_en_casa/features/auth/presentation/controllers/auth_controller.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthBinding {
  static void ensureInitialized() {
    if (Get.isRegistered<AuthController>()) return;

    final client = Supabase.instance.client;
    final dataSource = AuthRemoteDataSource(client);
    final repository = SupabaseAuthRepository(dataSource);

    Get.put<AuthController>(
      AuthController(
        signInWithEmail: SignInWithEmail(repository),
        signUpWithEmail: SignUpWithEmail(repository),
        sendPasswordReset: SendPasswordReset(repository),
        resendEmailConfirmation: ResendEmailConfirmation(repository),
        updatePassword: UpdatePassword(repository),
        signOut: SignOut(repository),
        repository: repository,
      ),
      permanent: true,
    );
  }
}
