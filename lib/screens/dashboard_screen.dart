import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../auth_service.dart';
import 'admin_dashboard.dart';
import 'company_dashboard.dart';
import 'employee_dashboard.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  StreamSubscription<DocumentSnapshot>? _userDocSubscription;

  @override
  void initState() {
    super.initState();
    _loadUserStatus();
  }

  @override
  void dispose() {
    _userDocSubscription?.cancel();
    super.dispose();
  }

  void _loadUserStatus() {
    if (userSession.userId == null) {
      setState(() => _isLoading = false);
      return;
    }
    _userDocSubscription?.cancel();
    _userDocSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(userSession.userId)
        .snapshots()
        .listen((doc) {
      if (mounted) {
        setState(() {
          _userData = doc.data();
          _isLoading = false;
        });
      }
    }, onError: (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final status = _userData?['status'] as String?;

    switch (userSession.role) {
      case UserRole.admin:
        return const AdminDashboard();
      case UserRole.company:
        if (status == 'pending') {
          return const PendingCompanyScreen();
        }
        if (status == 'rejected') {
          final reason = _userData?['rejectionReason'] as String?;
          return RejectedCompanyScreen(rejectionReason: reason ?? '');
        }
        return const CompanyDashboard();
      case UserRole.employee:
      default:
        return const EmployeeDashboard();
    }
  }
}

class PendingCompanyScreen extends StatelessWidget {
  const PendingCompanyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Espace entreprise'),
        backgroundColor: const Color(0xFF00BCD4),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hourglass_empty, size: 80, color: Colors.orange),
              const SizedBox(height: 24),
              const Text(
                'Compte en attente de validation',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Votre compte entreprise est en cours de validation par l\'administrateur. '
                'Vous recevrez une notification dès que votre compte sera validé.',
                style: TextStyle(fontSize: 16, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RejectedCompanyScreen extends StatelessWidget {
  final String rejectionReason;

  const RejectedCompanyScreen({super.key, required this.rejectionReason});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Espace entreprise'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cancel, size: 80, color: Colors.red),
              const SizedBox(height: 24),
              const Text(
                'Compte rejeté',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Motif du rejet :',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  rejectionReason.isNotEmpty ? rejectionReason : 'Raison non spécifiée',
                  style: const TextStyle(fontSize: 15),
                  textAlign: TextAlign.center,
                ),
                ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () async {
                  await userSession.logout();
                  if (context.mounted) {
                    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                  }
                },
                icon: const Icon(Icons.logout),
                label: const Text('Se déconnecter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

