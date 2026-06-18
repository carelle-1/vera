import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { employee, company, admin }

final FirebaseAuth auth = FirebaseAuth.instance;
final FirebaseFirestore firestore = FirebaseFirestore.instance;

class UserSession extends ChangeNotifier {
  UserRole? _role;
  bool _isLoggedIn = false;
  String? _userId;

  UserRole? get role => _role;
  bool get isLoggedIn => _isLoggedIn;
  String? get userId => _userId;

  void login(UserRole role, String userId) {
    _role = role;
    _isLoggedIn = true;
    _userId = userId;
    notifyListeners();
  }

  Future<void> logout() async {
    await auth.signOut();
    _role = null;
    _isLoggedIn = false;
    _userId = null;
    notifyListeners();
  }

  Future<void> loginWithEmail(String email, String password) async {
    try {
      final userCredential = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = userCredential.user;
      if (user != null) {
        final uid = user.uid;
        final doc = await firestore.collection('users').doc(uid).get();
        if (doc.exists) {
          final data = doc.data();
          final roleStr = data?['role'] as String?;
          final role = UserRole.values.firstWhere(
            (e) => e.name == roleStr,
            orElse: () => UserRole.employee,
          );
          login(role, uid);
        } else {
          await firestore.collection('users').doc(uid).set({
            'email': email,
            'role': UserRole.employee.name,
            'createdAt': FieldValue.serverTimestamp(),
          });
          login(UserRole.employee, uid);
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> registerWithEmail(
    String email,
    String password,
    String name,
    UserRole role,
    String? documentPath,
  ) async {
    try {
      final userCredential = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = userCredential.user;
      if (user != null) {
        final uid = user.uid;
        await firestore.collection('users').doc(uid).set({
          'email': email,
          'name': name,
          'role': role.name,
          'createdAt': FieldValue.serverTimestamp(),
        });
        login(role, uid);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> checkAuthState() async {
    final user = auth.currentUser;
    if (user != null) {
      final uid = user.uid;
      final doc = await firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data();
        final roleStr = data?['role'] as String?;
        final role = UserRole.values.firstWhere(
          (e) => e.name == roleStr,
          orElse: () => UserRole.employee,
        );
        login(role, uid);
      }
    }
  }
}

final userSession = UserSession();