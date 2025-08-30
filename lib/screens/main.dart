import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login.dart'; // make sure this file exists
import 'signup.dart'; // make sure this file exists
import 'home.dart'; // make sure this file exists

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Ensure bindings initialized
  await Supabase.initialize(
    url: 'https://joerjjtiwctzdbcynnar.supabase.co',
    anonKey: 'sb_publishable_78ZUvr1qtfV9aq0qErtIuA_nABUte5B',
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'ConnectAAC',
      theme: const CupertinoThemeData(
        primaryColor: CupertinoColors.activeBlue,
      ),
      initialRoute: '/login',
      routes: {
        '/': (context) => const LoginPage(),
        '/login': (context) => const LoginPage(),
        '/signup': (context) => const SignupPage(),
        '/home': (context) => const MyHomePage(),
      },
    );
  }
}
