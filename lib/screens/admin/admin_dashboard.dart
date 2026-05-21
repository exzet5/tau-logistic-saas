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

class TabDefinition {
  final String key;
  final String label;
  final Widget icon;
  final Widget page;

  TabDefinition({
    required this.key,
    required this.label,
    required this.icon,
    required this.page,
  });
}

class AdminDashboard extends StatefulWidget {
  final String displayName; 
  final String companyId; 
  
  const AdminDashboard({
    super.key, 
    required this.displayName, 
    required this.companyId 
  });

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  late final List<TabDefinition> _allAvailableTabs;
  late final Stream<DocumentSnapshot> _userPermissionsStream;

  @override
  void initState() {
    super.initState();
    
    // Initialize all tabs once
    _allAvailableTabs = [
      TabDefinition(key: 'dashboard', label: 'ראשי', icon: const Icon(Icons.dashboard), page: DashboardScreen(companyId: widget.companyId)),
      TabDefinition(key: 'users', label: 'משתמשים', icon: const Icon(Icons.people), page: UserManagementScreen(companyId: widget.companyId)),
      TabDefinition(key: 'patients', label: 'מטופלים', icon: const Icon(Icons.sick), page: PatientsManagementScreen(companyId: widget.companyId)),
      TabDefinition(key: 'items', label: 'ציוד', icon: const Icon(Icons.inventory), page: ItemsManagementScreen(companyId: widget.companyId)),
      TabDefinition(key: 'pikadon', label: 'פיקדונות', icon: _buildPikadonIcon(), page: PikadonScreen(companyId: widget.companyId)),
      TabDefinition(key: 'history', label: 'היסטוריה', icon: const Icon(Icons.history), page: HistoryScreen(companyId: widget.companyId)),
    ];

    // Cache the permissions stream
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      _userPermissionsStream = FirebaseFirestore.instance.collection('users').doc(currentUser.uid).snapshots();
    } else {
      _userPermissionsStream = const Stream.empty();
    }
  }

  /// Builds a widget with a badge for pending deposits
  Widget _buildPikadonIcon() {
    return StreamBuilder<QuerySnapshot>(
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
    );
  }

  /// Generates a time-appropriate greeting in Hebrew.
  String _getGreeting() {
    var hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'בוקר טוב'; 
    else if (hour >= 12 && hour < 17) return 'צהריים טובים'; 
    else if (hour >= 17 && hour < 21) return 'ערב טוב'; 
    else return 'לילה טוב'; 
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _userPermissionsStream,
      builder: (context, snapshot) {
        // Show a loader only on the very first load
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.teal)));
        }

        List<String> allowedKeys = [];
        if (snapshot.hasData && snapshot.data!.exists) {
          var userData = snapshot.data!.data() as Map<String, dynamic>;
          allowedKeys = userData.containsKey('allowedTabs') 
              ? List<String>.from(userData['allowedTabs'])
              : ['dashboard', 'patients', 'items', 'pikadon', 'history', 'users'];
        } else {
            // Default permissions if document not ready
            allowedKeys = ['dashboard', 'patients', 'items', 'pikadon', 'history', 'users'];
        }

        List<TabDefinition> activeTabs = _allAvailableTabs.where((tab) => allowedKeys.contains(tab.key)).toList();

        // Handle case where user lost all permissions or tab was removed
        if (activeTabs.isEmpty) {
          return Scaffold(
            appBar: AppBar(backgroundColor: Colors.blueGrey[900]),
            body: const Center(child: Text("אין לך הרשאות גישה", style: TextStyle(fontSize: 20))),
          );
        }

        // Adjust index if necessary
        if (_selectedIndex >= activeTabs.length) {
          _selectedIndex = 0;
        }

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("${_getGreeting()}, ${widget.displayName}", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const Text("מערכת ניהול (Admin)", style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
            backgroundColor: Colors.blueGrey[900],
            actions: [
              IconButton(icon: const Icon(Icons.logout), onPressed: () async => await FirebaseAuth.instance.signOut())
            ],
          ),
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: _selectedIndex,
                onDestinationSelected: (int index) => setState(() => _selectedIndex = index),
                labelType: NavigationRailLabelType.all,
                destinations: activeTabs.map((tab) => NavigationRailDestination(icon: tab.icon, label: Text(tab.label))).toList(),
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(child: activeTabs[_selectedIndex].page),
            ],
          ),
        );
      },
    );
  }
}