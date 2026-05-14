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
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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

        if (_isMobileModeLocked == null) {
           double screenWidth = MediaQuery.of(context).size.width;
           _isMobileModeLocked = screenWidth < 800;
        }

        if (role == 'admin' && !_isMobileModeLocked!) {
          return AdminDashboard(displayName: displayName);
        } else {
          return UserHomeScreen(displayName: displayName);
        }
      }
    );
  }
}