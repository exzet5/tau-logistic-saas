import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'items_management_screen.dart';
import 'dashboard_screen.dart';
import 'user_management_screen.dart';
import 'patients_screen.dart';
import '../../utils/helpers.dart';
import 'pikadon_screen.dart'; 
import 'history_screen.dart';

/// Main dashboard for administrators, containing a side navigation rail 
/// for managing users, patients, inventory, and viewing history/deposits.
class AdminDashboard extends StatefulWidget {
  final String displayName; 
  // NEW: Add companyId parameter
  final String companyId; 
  
  const AdminDashboard({
    super.key, 
    required this.displayName, 
    required this.companyId // NEW
  });

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;

  // NEW: Initialize _pages dynamically in initState so we can pass companyId to them
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    // Pass the companyId to every screen that needs to access Firestore
    _pages = [
      DashboardScreen(companyId: widget.companyId),
      UserManagementScreen(companyId: widget.companyId),
      PatientsManagementScreen(companyId: widget.companyId),
      ItemsManagementScreen(companyId: widget.companyId),
      PikadonScreen(companyId: widget.companyId),
      HistoryScreen(companyId: widget.companyId), 
    ];
  }

  /// Generates a time-appropriate greeting in Hebrew.
  String _getGreeting() {
    var hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return 'בוקר טוב'; 
    } else if (hour >= 12 && hour < 17) {
      return 'צהריים טובים'; 
    } else if (hour >= 17 && hour < 21) {
      return 'ערב טוב'; 
    } else {
      return 'לילה טוב'; 
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "${_getGreeting()}, ${widget.displayName}",
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Text(
              "מערכת ניהול (Admin)",
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        backgroundColor: Colors.blueGrey[900],
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          )
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            destinations: [
              const NavigationRailDestination(icon: Icon(Icons.dashboard), label: Text('ראשי')),
              const NavigationRailDestination(icon: Icon(Icons.people), label: Text('משתמשים')),
              const NavigationRailDestination(icon: Icon(Icons.sick), label: Text('מטופלים')),
              const NavigationRailDestination(icon: Icon(Icons.inventory), label: Text('ציוד')),
              
              NavigationRailDestination(
                icon: StreamBuilder<QuerySnapshot>(
                  // NEW: Update stream path to be specific to the company
                  stream: FirebaseFirestore.instance
                      .collection('companies')
                      .doc(widget.companyId)
                      .collection('Pikadon')
                      .where('status', isEqualTo: 'pending')
                      .snapshots(),
                  builder: (context, snapshot) {
                    int pendingCount = 0;
                    if (snapshot.hasData) {
                      pendingCount = snapshot.data!.docs.length;
                    }
                    if (pendingCount > 0) {
                      return Badge(
                        label: Text(pendingCount.toString()),
                        child: const Icon(Icons.account_balance_wallet),
                      );
                    }
                    return const Icon(Icons.account_balance_wallet);
                  },
                ),
                label: const Text('פיקדונות'),
              ),

              const NavigationRailDestination(icon: Icon(Icons.history), label: Text('היסטוריה')), 
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: _pages[_selectedIndex],
          ),
        ],
      ),
    );
  }
}