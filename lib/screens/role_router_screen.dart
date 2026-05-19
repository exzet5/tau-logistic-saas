import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/security_service.dart';
import 'login_screen.dart';
import 'admin/admin_dashboard.dart';
import 'user/user_home_screen.dart';
import '../../services/inventory_service.dart';

/// Routes the authenticated user to either AdminDashboard or UserHomeScreen 
/// based on their role retrieved from Firestore.
class RoleRouter extends StatefulWidget {
  const RoleRouter({super.key});

  @override
  State<RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<RoleRouter> {
  bool? _isMobileModeLocked; 

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return const LoginScreen();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
           return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        
        bool isActive = data['active'] ?? true;
        if (!isActive) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            FirebaseAuth.instance.signOut();
          });
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        String role = data['role'] ?? 'user';
        String displayName = data['displayName'] ?? "${data['name']} ${data['surname']}";
        
        // NEW: Retrieve company_id from user data
        String? companyId = data['company_id'];
        
        // Handle case where user has no company assigned
        if (companyId == null || companyId.isEmpty) {
           return const Scaffold(body: Center(child: Text('שגיאה: משתמש לא משויך לאף חברה')));
        }

        if (_isMobileModeLocked == null) {
           double screenWidth = MediaQuery.of(context).size.width;
           _isMobileModeLocked = screenWidth < 800;
        }

        // NEW: Pass companyId to the underlying screens
        if (role == 'admin' && !_isMobileModeLocked!) {
          return AdminDashboard(
            displayName: displayName, 
            companyId: companyId, // <-- Added parameter
          );
        } else {
          return UserHomeScreen(
            displayName: displayName,
            companyId: companyId, // <-- Added parameter
          );
        }
      }
    );
  }
}