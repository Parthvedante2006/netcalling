import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 🔹 Get current user (optional)
  User? get currentUser => _auth.currentUser;

  /// 🔹 Create a new user account
  Future<String> signUpUser({
    required String name,
    required String username,
    required String email,
    required String password,
  }) async {
    try {
      // Step 1️⃣: Check if username already exists
      final usernameQuery = await _firestore
          .collection('users')
          .where('username', isEqualTo: username)
          .get();

      if (usernameQuery.docs.isNotEmpty) {
        return 'Username already taken. Try another one.';
      }

      // Step 2️⃣: Create user in Firebase Authentication
      UserCredential cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      await Future.delayed(const Duration(seconds: 1));
      // Step 3️⃣: Save user info to Firestore
      final uid = cred.user?.uid;
      print('signUpUser: created user with uid=$uid; auth.currentUser=${_auth.currentUser?.uid}');
      if (uid == null) return 'Failed to create user';

      try {
        await _firestore.collection('users').doc(uid).set({
          'uid': uid,
          'name': name.trim(),
          'username': username.trim(),
          'email': email.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'online', // optional
        });
      } on FirebaseException catch (fe) {
        print('Firestore write failed (code=${fe.code}): ${fe.message}');
        return 'firestore_error:${fe.code}:${fe.message}';
      }

      print('signUpUser: Firestore write succeeded for uid=$uid');
      return 'success';
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        return 'Email already registered. Try logging in.';
      } else if (e.code == 'invalid-email') {
        return 'Invalid email format.';
      } else if (e.code == 'weak-password') {
        return 'Password is too weak. Use 6+ characters.';
      } else {
        return 'Auth Error: ${e.message}';
      }
    } catch (e) {
      return 'Error: ${e.toString()}';
    }
  }

  /// 🔹 Login user using username + password
  Future<String> loginUser({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return 'success';
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Login failed';
    } catch (e) {
      return 'Login failed: ${e.toString()}';
    }
  }

  /// 🔹 Get user document by username (needed for login)
  Future<DocumentSnapshot<Map<String, dynamic>>?> getUserByUsername(String username) async {
    final snapshot = await _firestore
        .collection('users')
        .where('username', isEqualTo: username)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return snapshot.docs.first;
  }
}


