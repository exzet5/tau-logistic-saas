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

/// Helper class to bind a tab's key to its UI representations
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

/// Main dashboard for administrators, containing a dynamic side navigation rail 
/// based on the user's granular permissions fetched via a real-time Stream.
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
  
  // Define all available tabs once to preserve widget state
  late final List<TabDefinition> _allAvailableTabs;

  @override
  void initState() {
    super.initState();
    // Initialize pages once so they don't rebuild from scratch on every stream update
    _allAvailableTabs = [
      TabDefinition(key: 'dashboard', label: 'ראשי', icon: const Icon(Icons.dashboard), page: DashboardScreen(companyId: widget.companyId)),
      TabDefinition(key: 'users', label: 'משתמשים', icon: const Icon(Icons.people), page: UserManagementScreen(companyId: widget.companyId)),
      TabDefinition(key: 'patients', label: 'מטופלים', icon: const Icon(Icons.sick), page: PatientsManagementScreen(companyId: widget.companyId)),
      TabDefinition(key: 'items', label: 'ציוד', icon: const Icon(Icons.inventory), page: ItemsManagementScreen(companyId: widget.companyId)),
      TabDefinition(key: 'pikadon', label: 'פיקדונות', icon: _buildPikadonIcon(), page: PikadonScreen(companyId: widget.companyId)),
      TabDefinition(key: 'history', label: 'היסטוריה', icon: const Icon(Icons.history), page: HistoryScreen(companyId: widget.companyId)),
    ];
  }

  /// Custom stream builder to show pending deposit badges on the Pikadon icon
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
    User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text("Not logged in")));
    }

    // Wrap the entire Scaffold body in a StreamBuilder to listen to permission changes in real-time
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(currentUser.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.teal)));
        }

        List<String> allowedKeys = [];
        
        if (snapshot.hasData && snapshot.data!.exists) {
          var userData = snapshot.data!.data() as Map<String, dynamic>;
          if (userData.containsKey('allowedTabs')) {
            allowedKeys = List<String>.from(userData['allowedTabs']);
          } else {
            // Legacy fallback
            allowedKeys = ['dashboard', 'patients', 'items', 'pikadon', 'history', 'users'];
          }
        }

        // Filter available tabs based on the real-time permissions
        List<TabDefinition> activeTabs = _allAvailableTabs.where((tab) => allowedKeys.contains(tab.key)).toList();

        // Edge case: user has no permissions at all
        if (activeTabs.isEmpty) {
          return Scaffold(
            appBar: AppBar(backgroundColor: Colors.blueGrey[900]),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.block, size: 80, color: Colors.grey),
                  const SizedBox(height: 20),
                  const Text("אין לך הרשאות לצפות במסכים במערכת זו", style: TextStyle(fontSize: 20, color: Colors.grey)),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => FirebaseAuth.instance.signOut(), 
                    icon: const Icon(Icons.logout), 
                    label: const Text("התנתק")
                  )
                ],
              ),
            ),
          );
        }

        // Prevent range errors if a tab is removed while the user is actively on it
        int safeIndex = _selectedIndex;
        if (safeIndex >= activeTabs.length) {
          safeIndex = 0; 
        }

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
                selectedIndex: safeIndex,
                onDestinationSelected: (int index) {
                  // Only update state if we are actually mounted and clicking
                  setState(() {
                    _selectedIndex = index;
                  });
                },
                labelType: NavigationRailLabelType.all,
                destinations: activeTabs.map((tab) => 
                  NavigationRailDestination(icon: tab.icon, label: Text(tab.label))
                ).toList(),
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(
                child: activeTabs[safeIndex].page,
              ),
            ],
          ),
        );
      },
    );
  }
}