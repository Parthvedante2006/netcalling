import 'package:flutter/material.dart';
import 'package:netcalling/Screens/sign_up.dart';
import 'package:netcalling/Services/firebase_service.dart';

class LoginScreen extends StatefulWidget {
  final bool showSignUpSuccess;
  const LoginScreen({super.key, this.showSignUpSuccess = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.showSignUpSuccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Account created successfully!")),
        );
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _onLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    String? email;

    try {
      final snapshot = await FirebaseService().getUserByUsername(username);
      if (snapshot == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ Username not found")),
        );
        setState(() => _isLoading = false);
        return;
      }
      email = snapshot['email'] as String;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error: $e")),
      );
      setState(() => _isLoading = false);
      return;
    }

    final result = await FirebaseService().loginUser(email: email, password: password);

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (result == 'success') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Login successful")),
      );
      // TODO: Navigate to Home/Dashboard
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ $result")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (v) => (v == null || v.isEmpty) ? 'Enter username' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (v) => (v == null || v.isEmpty) ? 'Enter password' : null,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _onLogin,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Login'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SignUpScreen()),
                  );
                },
                child: const Text('Don\'t have an account? Sign Up'),
              )
            ],
          ),
        ),
      ),
    );
  }
}
