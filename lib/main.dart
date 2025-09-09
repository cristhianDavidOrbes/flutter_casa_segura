import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import 'config/environment.dart';
import 'circle_state.dart';
import 'login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  Client client = Client()
    ..setEndpoint(Environment.appwritePublicEndpoint)
    ..setProject(Environment.appwriteProjectId);

  Account account = Account(client);

  runApp(MyApp(account: account));
}

class MyApp extends StatelessWidget {
  final Account account;

  const MyApp({super.key, required this.account});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Casa Segura',
      theme: ThemeData.dark(),
      home: LoginScreen(circleNotifier: CircleStateNotifier()),
    );
  }
}
