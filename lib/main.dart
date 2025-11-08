import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'Screens/sign_up.dart';

void main() async {
  // Ensures all Flutter services are initialized before Firebase
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (auto-reads from google-services.json)
  await Firebase.initializeApp();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NetCalling',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const SignUpScreen(),
    );
  }
}
