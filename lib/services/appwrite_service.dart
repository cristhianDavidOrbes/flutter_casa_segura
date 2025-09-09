import 'package:appwrite/appwrite.dart';

class AppwriteService {
  final Client client = Client();
  late Account account;

  AppwriteService() {
    client.setEndpoint('http://localhost/v1').setProject('tu_project_id');
    account = Account(client);
  }

  // Registrar usuario
  Future createUser(String email, String password, String name) async {
    return await account.create(
      userId: ID.unique(),
      email: email,
      password: password,
      name: name,
    );
  }

  Future login(String email, String password) async {
    return await account.createEmailPasswordSession(
      email: email,
      password: password,
    );
  }

  Future logout() async {
    return await account.deleteSession(sessionId: 'current');
  }

  Future getUser() async {
    return await account.get();
  }
}
