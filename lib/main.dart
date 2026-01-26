import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login.dart';
import 'screens/signup.dart';
import 'screens/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Ensure bindings initialized
  final supabaseUrl = kIsWeb
      ? '/supabase' // proxied via _redirects on Netlify
      : 'https://joerjjtiwctzdbcynnar.supabase.co';
  await Supabase.initialize(
    url: supabaseUrl,
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
