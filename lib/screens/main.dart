import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login.dart'; // make sure this file exists
import 'signup.dart'; // make sure this file exists

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
        primaryColor: Color.fromARGB(255, 238, 233, 224),
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

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: const Padding(
          padding: EdgeInsets.only(left: 8.0),
          child: Text(
            'ConnectAAC',
            style: TextStyle(
              fontSize: 40.0,
              fontWeight: FontWeight.bold,
              color: CupertinoColors.black,
            ),
          ),
        ),
        trailing: Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  // TODO: Implement settings
                },
                child: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.fromARGB(255, 153, 160, 113),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: const Icon(CupertinoIcons.settings, size: 24, color: CupertinoColors.white),
                ),
              ),
              const SizedBox(width: 8),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  // TODO: Implement AI action
                },
                child: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.fromARGB(255, 153, 160, 113),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: const Icon(CupertinoIcons.sparkles, size: 24, color: CupertinoColors.white),
                ),
              ),
            ],
          ),
        ),
      ),
      child: const Center(
        child: Text('Welcome to ConnectAAC!'),
      ),
    );
  }
}
