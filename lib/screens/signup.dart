// ignore_for_file: unnecessary_import

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'; // Needed only for SnackBar fallback
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';

class SignupPage extends StatefulWidget {
  @override
  _SignupPageState createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final caregiverCodeController = TextEditingController();

  final List<String> roles = [
    'AAC User',
    'Parent/Guardian',
    'Speech Therapist',
    'Occupational Therapist',
    'Other',
  ];

  int selectedRoleIndex = 0;
  bool showPicker = false;
  bool isLoading = false;

  String get selectedRole => roles[selectedRoleIndex];

  void showRolePicker() {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => Container(
        height: 250,
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: Column(
          children: [
            SizedBox(
              height: 200,
              child: CupertinoPicker(
                scrollController: FixedExtentScrollController(initialItem: selectedRoleIndex),
                itemExtent: 32,
                onSelectedItemChanged: (index) {
                  setState(() => selectedRoleIndex = index);
                },
                children: roles.map((r) => Text(r)).toList(),
              ),
            ),
            CupertinoButton(
              child: const Text('Done'),
              onPressed: () => Navigator.of(context).pop(),
            )
          ],
        ),
      ),
    );
  }

  Future<void> signUp() async {
    setState(() => isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final authResponse = await supabase.auth.signUp(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      final userId = authResponse.user?.id;
      if (userId == null) throw Exception('User not created');

      await supabase.from('users').insert({
        'id': userId,
        'name': nameController.text.trim(),
        'role': selectedRole,
        'caregiver_code': selectedRole == 'Parent/Guardian'
            ? caregiverCodeController.text.trim()
            : null,
      });

      showCupertinoDialog(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text("Success"),
          content: const Text("Account created."),
          actions: [
            CupertinoDialogAction(
              child: const Text("OK"),
              onPressed: () => Navigator.of(context).pop(),
            )
          ],
        ),
      );
    } catch (e) {
      showCupertinoDialog(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text("Error"),
          content: Text(e.toString()),
          actions: [
            CupertinoDialogAction(
              child: const Text("OK"),
              onPressed: () => Navigator.of(context).pop(),
            )
          ],
        ),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Sign Up'),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            children: [
              CupertinoTextField(
                controller: nameController,
                placeholder: 'Full Name',
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: emailController,
                placeholder: 'Email',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: passwordController,
                placeholder: 'Password',
                obscureText: true,
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: showRolePicker,
                child: AbsorbPointer(
                  child: CupertinoTextField(
                    placeholder: 'Select Role',
                    controller: TextEditingController(text: selectedRole),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (selectedRole == 'Parent/Guardian')
                CupertinoTextField(
                  controller: caregiverCodeController,
                  placeholder: 'Set 4-digit Caregiver Lock',
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                ),
              const SizedBox(height: 20),
              CupertinoButton.filled(
                onPressed: isLoading ? null : signUp,
                child: isLoading
                    ? CupertinoActivityIndicator()
                    : const Text('Create Account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
