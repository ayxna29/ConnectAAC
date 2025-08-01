import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  await Supabase.initialize(
    url: 'https://joerjjtiwctzdbcynnar.supabase.co',
    anonKey: 'sb_publishable_78ZUvr1qtfV9aq0qErtIuA_nABUte5B',
  );
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'ConnectAAC',
      theme: CupertinoThemeData(
        primaryColor: Color.fromARGB(255, 238, 233, 224),
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key});
  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 8.0),
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
              // Settings button
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  // TODO: Implement settings action
                },
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.fromARGB(255, 153, 160, 113),
                  ),
                  padding: EdgeInsets.all(8),
                  child: Icon(CupertinoIcons.settings, size: 24, color: CupertinoColors.white),
                ),
              ),
              SizedBox(width: 8),
              // AI Optimization button
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  // TODO: Implement AI optimization action
                },
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.fromARGB(255, 153, 160, 113),
                  ),
                  padding: EdgeInsets.all(8),
                  child: Icon(CupertinoIcons.sparkles, size: 24, color: CupertinoColors.white),
                ),
              ),
            ],
          ),
        ),
      ),
      child: Center(
        child: Text('Welcome to ConnectAAC!'),
      ),
    );
  }
}