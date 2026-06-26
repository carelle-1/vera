import 'package:flutter/material.dart';
import '../auth_service.dart';
import 'admin_dashboard.dart';
import 'company_dashboard.dart';
import 'employee_dashboard.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    switch (userSession.role) {
      case UserRole.admin:
        return const AdminDashboard();
      case UserRole.company:
        return const CompanyDashboard();
      case UserRole.employee:
      default:
        return const EmployeeDashboard();
    }
  }
}
