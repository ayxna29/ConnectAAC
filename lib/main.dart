import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login.dart';
import 'screens/signup.dart';
import 'screens/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Ensure bindings initialized
  // Always use the direct Supabase URL, never proxy through the frontend.
  // This ensures auth requests go to Supabase, not to the frontend server.
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
      theme: const CupertinoThemeData(primaryColor: CupertinoColors.activeBlue),
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
