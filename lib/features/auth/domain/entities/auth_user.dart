class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    this.name,
    required this.emailConfirmed,
  });

  final String id;
  final String email;
  final String? name;
  final bool emailConfirmed;
}
