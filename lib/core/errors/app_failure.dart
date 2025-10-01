class AppFailure implements Exception {
  const AppFailure(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class AuthFailure extends AppFailure {
  const AuthFailure(super.message, [super.cause]);
}
