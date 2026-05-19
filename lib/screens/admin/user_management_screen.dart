import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/email_service.dart';
import '../../utils/helpers.dart';

/// Screen for administrators to manage system users.
/// Provides functionality to add new users (with automated welcome emails),
/// view a complete list of allowed users, edit their details, view activity statistics,
/// and revoke their access (delete).
class UserManagementScreen extends StatefulWidget {
  // NEW: Add companyId parameter
  final String companyId; 

  const UserManagementScreen({super.key, required this.companyId}); // UPDATED

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Form keys for validation
  final _addFormKey = GlobalKey<FormState>();
  final _editFormKey = GlobalKey<FormState>();

  final Map<String, String> _roleDescriptions = {
    'user': 'לקיחה והחזר של ציוד, מתאים לפיזיוטרפיסטים',
    'admin': 'דשבורדים וניהול מערכת ידני',
  };

  // --- ADD USER CONTROLLERS ---
  final _addEmailCtrl = TextEditingController();
  final _addNameCtrl = TextEditingController();
  final _addSurnameCtrl = TextEditingController();
  String _addSelectedRole = 'user';
  String? _backendEmailError;

  // --- LIST & FILTER CONTROLLERS ---
  final _searchFilterCtrl = TextEditingController();
  String _searchQuery = "";

  // --- USER STATISTICS STATE ---
  int _statTaken = 0;
  int _statReturned = 0;
  List<int> _weekDayCounts = [0, 0, 0, 0, 0, 0, 0];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _addEmailCtrl.dispose();
    _addNameCtrl.dispose();
    _addSurnameCtrl.dispose();
    _searchFilterCtrl.dispose();
    super.dispose();
  }

  // --- HELPERS ---

  /// Displays a temporary status message via Snackbar.
  void _showSnackBar(String msg, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg), 
          backgroundColor: isError ? Colors.red : Colors.green
        ),
      );
    }
  }

  /// Displays a non-dismissible loading indicator dialog.
  void _showLoadingDialog() {
    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: Colors.white))
    );
  }

  /// Closes the loading indicator dialog.
  void _hideLoadingDialog() {
    if (Navigator.canPop(context)) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  // --- DATABASE OPERATIONS ---

  // NEW: Helper getter for the current company document reference
  DocumentReference get _companyRef => FirebaseFirestore.instance.collection('companies').doc(widget.companyId);

  /// Validates inputs, creates a new allowed user record in Firestore, 
  /// and triggers a welcome email via EmailJS.
  Future<void> _addNewUser() async {
    setState(() => _backendEmailError = null);
    if (!_addFormKey.currentState!.validate()) return;

    _showLoadingDialog();
    try {
      final check = await FirebaseFirestore.instance
          .collection('allowed_users')
          .where('email', isEqualTo: _addEmailCtrl.text.trim().toLowerCase())
          .get();

      if (check.docs.isNotEmpty) {
        _hideLoadingDialog();
        setState(() => _backendEmailError = 'שגיאה: המשתמש כבר קיים במערכת');
        _addFormKey.currentState!.validate();
        return;
      }

      await FirebaseFirestore.instance.collection('allowed_users').add({
        'email': _addEmailCtrl.text.trim().toLowerCase(),
        'name': _addNameCtrl.text.trim(),
        'surname': _addSurnameCtrl.text.trim(),
        'role': _addSelectedRole,
        // NEW: Assign the user to the specific company
        'company_id': widget.companyId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Delegate email sending to the external EmailService
      try {
        await EmailService.sendWelcomeEmail(
          email: _addEmailCtrl.text.trim().toLowerCase(),
          name: _addNameCtrl.text.trim(),
          role: _addSelectedRole,
        );
      } catch (e) {
        debugPrint("Failed to send welcome email: $e");
      }

      _hideLoadingDialog();
      _showSnackBar('משתמש נוסף ומייל נשלח!');
      
      _addEmailCtrl.clear();
      _addNameCtrl.clear();
      _addSurnameCtrl.clear();
      setState(() => _addSelectedRole = 'user');
    } catch (e) {
      _hideLoadingDialog();
      _showSnackBar('Error: $e', isError: true);
    }
  }

  /// Updates existing user data in both 'allowed_users' and 'users' collections.
  /// Also checks if the newly provided email is already taken.
  Future<void> _updateUser(String docId, String oldEmail, String newEmail, String name, String surname, String role) async {
    _showLoadingDialog();
    try {
      // Check if new email is already taken by someone else
      if (oldEmail != newEmail) {
        final check = await FirebaseFirestore.instance
            .collection('allowed_users')
            .where('email', isEqualTo: newEmail)
            .get();

        if (check.docs.isNotEmpty) {
          _hideLoadingDialog();
          _showSnackBar('שגיאה: האימייל החדש כבר קיים במערכת', isError: true);
          return;
        }
      }

      WriteBatch batch = FirebaseFirestore.instance.batch();
      
      // Update the permission list
      batch.update(FirebaseFirestore.instance.collection('allowed_users').doc(docId), {
        'email': newEmail,
        'name': name,
        'surname': surname,
        'role': role,
      });

      // If the user has already logged in, update their active profile as well
      final userSnap = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: oldEmail).get();
      if (userSnap.docs.isNotEmpty) {
        batch.update(userSnap.docs.first.reference, {
          'email': newEmail,
          'name': name,
          'surname': surname,
          'displayName': "$name $surname",
          'role': role,
        });
      }

      await batch.commit();
      _hideLoadingDialog();
      _showSnackBar('השינויים נשמרו בהצלחה');
    } catch (e) {
      _hideLoadingDialog();
      _showSnackBar('Error: $e', isError: true);
    }
  }

  /// Fetches equipment usage statistics for a specific user.
  Future<void> _fetchUserStats(String uid) async {
    _statTaken = 0;
    _statReturned = 0;
    _weekDayCounts = [0, 0, 0, 0, 0, 0, 0];

    // NEW: Use _companyRef to fetch History from the specific company
    final snapshot = await _companyRef
        .collection('History')
        .where('staffUid', isEqualTo: uid)
        .get();

    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      String action = data['action'] ?? '';
      if (action == 'take') _statTaken++;
      if (action == 'return') _statReturned++;

      if (data['timestamp'] != null) {
        DateTime date = (data['timestamp'] as Timestamp).toDate();
        // Shift Dart's weekday (1=Mon, 7=Sun) to standard array index (0=Sun, 6=Sat) 
        // depending on your display logic. Here we use 0=Sun.
        int dayIndex = date.weekday == 7 ? 0 : date.weekday;
        if (dayIndex >= 0 && dayIndex < 7) {
          _weekDayCounts[dayIndex]++;
        }
      }
    }
  }

  // --- DIALOGS ---

  /// Opens a dialog to edit user details including email. Requires valid non-empty inputs to save.
  void _showEditDialog(String docId, Map<String, dynamic> userData) {
    final emailCtrl = TextEditingController(text: userData['email']);
    final nameCtrl = TextEditingController(text: userData['name']);
    final surnameCtrl = TextEditingController(text: userData['surname']);
    String selectedRole = userData['role'] ?? 'user';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('עריכת פרטי משתמש', style: TextStyle(fontWeight: FontWeight.bold)),
            content: Form(
              key: _editFormKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(labelText: 'אימייל', border: OutlineInputBorder()),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'חובה להזין אימייל';
                        if (!AppHelpers.isValidEmail(v.trim())) return 'פורמט אימייל שגוי';
                        return null;
                      },
                    ),
                    const SizedBox(height: 15),
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'שם פרטי', border: OutlineInputBorder()),
                      validator: (v) => v!.trim().isEmpty ? 'חובה להזין שם' : null,
                    ),
                    const SizedBox(height: 15),
                    TextFormField(
                      controller: surnameCtrl,
                      decoration: const InputDecoration(labelText: 'שם משפחה', border: OutlineInputBorder()),
                      validator: (v) => v!.trim().isEmpty ? 'חובה להזין שם משפחה' : null,
                    ),
                    const SizedBox(height: 15),
                    _buildRoleDropdown(selectedRole, (val) => setDialogState(() => selectedRole = val!)),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx), 
                child: const Text('ביטול', style: TextStyle(color: Colors.red))
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () async {
                  if (!_editFormKey.currentState!.validate()) return;
                  Navigator.pop(ctx); // Close dialog first
                  await _updateUser(
                    docId, 
                    userData['email'], 
                    emailCtrl.text.trim().toLowerCase(), 
                    nameCtrl.text.trim(), 
                    surnameCtrl.text.trim(), 
                    selectedRole
                  );
                },
                child: const Text('שמור שינויים'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens a confirmation dialog before sending the welcome email.
  Future<void> _confirmSendEmail(String email, String name, String role) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('שליחת הזמנה מחדש', style: TextStyle(color: Colors.orange)),
          content: Text('האם אתה בטוח שברצונך לשלוח שוב את מייל ההזמנה והקישורים לכתובת:\n$email?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('שלח מייל'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      _showLoadingDialog();
      try {
        await EmailService.sendWelcomeEmail(name: name, email: email, role: role);
        _hideLoadingDialog();
        _showSnackBar('מייל נשלח בהצלחה ל-$email');
      } catch (e) {
        _hideLoadingDialog();
        _showSnackBar('שגיאה בשליחת המייל: $e', isError: true);
      }
    }
  }

  /// Opens a confirmation dialog before deleting a user and revoking their access.
  Future<void> _confirmDelete(String docId, String email) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת משתמש', style: TextStyle(color: Colors.red)),
          content: Text('האם אתה בטוח שברצונך למחוק את $email?\nהגישה למערכת תיחסם מיידית.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('מחק לצמיתות'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      _showLoadingDialog();
      try {
        WriteBatch batch = FirebaseFirestore.instance.batch();
        batch.delete(FirebaseFirestore.instance.collection('allowed_users').doc(docId));
        
        final userSnap = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: email).get();
        if (userSnap.docs.isNotEmpty) {
          batch.update(userSnap.docs.first.reference, {'active': false});
        }
        
        await batch.commit();
        _hideLoadingDialog();
        _showSnackBar('המשתמש נמחק בהצלחה');
      } catch (e) {
        _hideLoadingDialog();
        _showSnackBar('Error: $e', isError: true);
      }
    }
  }

  /// Fetches user stats and opens a dialog to display the activity chart.
  void _showStatsDialog(String email, String name) async {
    _showLoadingDialog();
    
    try {
      final userSnap = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: email).get();
      if (userSnap.docs.isEmpty) {
        _hideLoadingDialog();
        _showSnackBar('המשתמש טרם התחבר למערכת, אין סטטיסטיקה', isError: true);
        return;
      }
      
      String uid = userSnap.docs.first.id;
      Timestamp? lastLoginTs = userSnap.docs.first.data()['lastLogin'];
      String lastLoginText = lastLoginTs != null 
          ? lastLoginTs.toDate().toString().substring(0, 16) 
          : "לא ידוע";

      await _fetchUserStats(uid);
      _hideLoadingDialog();

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text("סטטיסטיקה: $name", style: const TextStyle(fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("כניסה אחרונה: $lastLoginText", style: const TextStyle(color: Colors.blueGrey)),
                  const SizedBox(height: 20),
                  _buildStatsArea(),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('סגור'))
            ],
          ),
        ),
      );
    } catch (e) {
      _hideLoadingDialog();
      _showSnackBar('שגיאה בטעינת סטטיסטיקה', isError: true);
    }
  }

  // --- UI BUILDERS ---

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF004D40),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF004D40),
            tabs: const [
              Tab(text: 'הוספת משתמש', icon: Icon(Icons.person_add)),
              Tab(text: 'ניהול רשימת משתמשים', icon: Icon(Icons.people)),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildAddUserTab(),
              _buildUserListTab(),
            ],
          ),
        ),
      ],
    );
  }

  /// Builds the tab for adding a new user.
  Widget _buildAddUserTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(30),
      child: Form(
        key: _addFormKey,
        child: Column(
          children: [
            const Text('הוספת משתמש חדש למערכת', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 30),
            TextFormField(
              controller: _addEmailCtrl,
              decoration: const InputDecoration(labelText: 'אימייל', border: OutlineInputBorder()),
              validator: (v) {
                if (v == null || v.isEmpty) return 'נא להזין אימייל';
                if (!AppHelpers.isValidEmail(v)) return 'פורמט אימייל שגוי';
                if (_backendEmailError != null) return _backendEmailError;
                return null;
              },
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _addNameCtrl, 
                    decoration: const InputDecoration(labelText: 'שם פרטי', border: OutlineInputBorder()), 
                    validator: (v) => v!.isEmpty ? 'חובה למלא' : null
                  )
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: TextFormField(
                    controller: _addSurnameCtrl, 
                    decoration: const InputDecoration(labelText: 'שם משפחה', border: OutlineInputBorder()), 
                    validator: (v) => v!.isEmpty ? 'חובה למלא' : null
                  )
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildRoleDropdown(_addSelectedRole, (val) => setState(() => _addSelectedRole = val!)),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity, 
              height: 60, 
              child: ElevatedButton.icon(
                icon: const Icon(Icons.person_add_alt_1), 
                label: const Text('צור משתמש ושלח הזמנה', style: TextStyle(fontSize: 18)), 
                onPressed: _addNewUser
              )
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the CRM-style list of all allowed users with real-time filtering and action buttons.
  Widget _buildUserListTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: TextField(
            controller: _searchFilterCtrl,
            decoration: const InputDecoration(
              labelText: 'חיפוש משתמש (שם או אימייל)', 
              prefixIcon: Icon(Icons.search), 
              border: OutlineInputBorder()
            ),
            onTap: () {
              // Clear search query on tap to quickly reset the list
              _searchFilterCtrl.clear();
              setState(() => _searchQuery = "");
            },
            onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            // NEW: Filter by company_id. OrderBy is done in memory to avoid Firebase index requirements
            stream: FirebaseFirestore.instance
                .collection('allowed_users')
                .where('company_id', isEqualTo: widget.companyId)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              
              // NEW: Sort the documents manually in Dart by name
              var allDocs = snapshot.data!.docs.toList();
              allDocs.sort((a, b) => (a.data() as Map<String, dynamic>)['name'].toString().compareTo((b.data() as Map<String, dynamic>)['name'].toString()));

              final docs = allDocs.where((doc) {
                final d = doc.data() as Map<String, dynamic>;
                final searchStr = "${d['name']} ${d['surname']} ${d['email']}".toLowerCase();
                return searchStr.contains(_searchQuery);
              }).toList();

              if (docs.isEmpty) return const Center(child: Text("לא נמצאו משתמשים", style: TextStyle(fontSize: 18, color: Colors.grey)));

              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final d = doc.data() as Map<String, dynamic>;
                  final fullName = "${d['name']} ${d['surname']}";
                  final role = d['role'] ?? 'user';

                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                      leading: CircleAvatar(
                        backgroundColor: role == 'admin' ? Colors.red[50] : Colors.teal[50],
                        child: Icon(role == 'admin' ? Icons.admin_panel_settings : Icons.person, color: role == 'admin' ? Colors.red : Colors.teal),
                      ),
                      title: Text(fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      subtitle: Text(d['email'], style: TextStyle(color: Colors.grey[700])),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue), 
                            tooltip: "ערוך פרטים", 
                            onPressed: () => _showEditDialog(doc.id, d)
                          ),
                          IconButton(
                            icon: const Icon(Icons.email_outlined, color: Colors.orange), 
                            tooltip: "שלח הזמנה שוב", 
                            onPressed: () => _confirmSendEmail(d['email'], d['name'], role)
                          ),
                          IconButton(
                            icon: const Icon(Icons.bar_chart, color: Colors.green), 
                            tooltip: "סטטיסטיקה", 
                            onPressed: () => _showStatsDialog(d['email'], fullName)
                          ),
                          const SizedBox(width: 15),
                          IconButton(
                            icon: const Icon(Icons.delete_forever, color: Colors.red), 
                            tooltip: "מחק משתמש", 
                            onPressed: () => _confirmDelete(doc.id, d['email'])
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Builds the visual area displaying user equipment interactions and weekly activity chart.
  Widget _buildStatsArea() {
    int maxVal = _weekDayCounts.reduce(max);
    if (maxVal == 0) maxVal = 1;
    List<String> dayLabels = ['א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ש'];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _buildStatCard("נלקחו", _statTaken.toString(), Colors.orange.shade50, Colors.orange.shade800!)),
            const SizedBox(width: 10),
            Expanded(child: _buildStatCard("הוחזרו", _statReturned.toString(), Colors.green.shade50, Colors.green.shade800!)),
          ],
        ),
        const SizedBox(height: 20),
        const Text("פעילות שבועית:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 10),
        SizedBox(
          height: 100,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (index) {
              double barHeight = (_weekDayCounts[index] / maxVal) * 60;
              return Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    width: 15, 
                    height: max(barHeight, 2), 
                    decoration: BoxDecoration(color: Colors.teal[400], borderRadius: BorderRadius.circular(3))
                  ),
                  const SizedBox(height: 4),
                  Text(dayLabels[index], style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }

  /// Builds a minimal card for numerical statistics.
  Widget _buildStatCard(String title, String value, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
          Text(title, style: TextStyle(color: textColor, fontSize: 14)),
        ],
      ),
    );
  }

  /// Helper widget to render role selection dropdowns.
  Widget _buildRoleDropdown(String currentVal, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: currentVal,
          decoration: const InputDecoration(labelText: 'תפקיד', border: OutlineInputBorder()),
          items: _roleDescriptions.keys.map((role) => DropdownMenuItem(value: role, child: Text(role.toUpperCase()))).toList(),
          onChanged: onChanged,
        ),
        const SizedBox(height: 5),
        Text(_roleDescriptions[currentVal] ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
      ],
    );
  }
}