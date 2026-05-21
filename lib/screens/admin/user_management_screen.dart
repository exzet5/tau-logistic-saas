import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/email_service.dart';
import '../../utils/helpers.dart';

/// Screen for administrators to manage system users.
/// Provides functionality to add new users, set granular tab permissions,
/// view user lists, edit details, view activity statistics, and revoke access.
class UserManagementScreen extends StatefulWidget {
  final String companyId; 

  const UserManagementScreen({super.key, required this.companyId});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  final _addFormKey = GlobalKey<FormState>();
  final _editFormKey = GlobalKey<FormState>();

  final Map<String, String> _roleDescriptions = {
    'user': 'לקיחה והחזר של ציוד, מתאים לפיזיוטרפיסטים',
    'admin': 'דשבורדים וניהול מערכת ידני',
  };

  // --- AVAILABLE TABS CONFIGURATION ---
  final Map<String, String> _availableTabs = {
    'dashboard': 'ראשי',
    'patients': 'לקוחות',
    'items': 'ציוד',
    'pikadon': 'פיקדונות',
    'history': 'היסטוריה',
    'users': 'משתמשים',
  };

  // --- ADD USER CONTROLLERS ---
  final _addEmailCtrl = TextEditingController();
  final _addNameCtrl = TextEditingController();
  final _addSurnameCtrl = TextEditingController();
  String _addSelectedRole = 'user';
  String? _backendEmailError;
  
  // Default tabs for a new user
  List<String> _addSelectedTabs = ['dashboard', 'patients', 'items', 'pikadon', 'history'];

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

  void _showLoadingDialog() {
    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: Colors.white))
    );
  }

  void _hideLoadingDialog() {
    if (Navigator.canPop(context)) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  DocumentReference get _companyRef => FirebaseFirestore.instance.collection('companies').doc(widget.companyId);

  // --- DATABASE OPERATIONS ---

  Future<void> _addNewUser() async {
    setState(() => _backendEmailError = null);
    if (!_addFormKey.currentState!.validate()) return;

    if (_addSelectedRole == 'admin' && _addSelectedTabs.isEmpty) {
      _showSnackBar('חובה לבחור לפחות הרשאה אחת (לשונית)', isError: true);
      return;
    }

    final nav = Navigator.of(context, rootNavigator: true);
    final scaffold = ScaffoldMessenger.of(context);

    _showLoadingDialog();
    try {
      final check = await FirebaseFirestore.instance
          .collection('allowed_users')
          .where('email', isEqualTo: _addEmailCtrl.text.trim().toLowerCase())
          .get();

      if (check.docs.isNotEmpty) {
        nav.pop();
        setState(() => _backendEmailError = 'שגיאה: המשתמש כבר קיים במערכת');
        _addFormKey.currentState!.validate();
        return;
      }

      await FirebaseFirestore.instance.collection('allowed_users').add({
        'email': _addEmailCtrl.text.trim().toLowerCase(),
        'name': _addNameCtrl.text.trim(),
        'surname': _addSurnameCtrl.text.trim(),
        'role': _addSelectedRole,
        'company_id': widget.companyId,
        'allowedTabs': _addSelectedTabs, 
        'createdAt': FieldValue.serverTimestamp(),
      });

      try {
        await EmailService.sendWelcomeEmail(
          email: _addEmailCtrl.text.trim().toLowerCase(),
          name: _addNameCtrl.text.trim(),
          role: _addSelectedRole,
        );
      } catch (e) {
        debugPrint("Failed to send welcome email: $e");
      }

      nav.pop();
      scaffold.showSnackBar(const SnackBar(content: Text('משתמש נוסף ומייל נשלח!'), backgroundColor: Colors.green));
      
      _addEmailCtrl.clear();
      _addNameCtrl.clear();
      _addSurnameCtrl.clear();
      setState(() {
        _addSelectedRole = 'user';
        _addSelectedTabs = ['dashboard', 'patients', 'items', 'pikadon', 'history'];
        _tabController.index = 1; // Возвращаемся в список
      });
    } catch (e) {
      nav.pop();
      scaffold.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _updateUser(String docId, String oldEmail, String newEmail, String name, String surname, String role, List<String> allowedTabs) async {
    final nav = Navigator.of(context, rootNavigator: true);
    final scaffold = ScaffoldMessenger.of(context);

    _showLoadingDialog();
    try {
      if (oldEmail != newEmail) {
        final check = await FirebaseFirestore.instance
            .collection('allowed_users')
            .where('email', isEqualTo: newEmail)
            .get();

        if (check.docs.isNotEmpty) {
          nav.pop();
          scaffold.showSnackBar(const SnackBar(content: Text('שגיאה: האימייל החדש כבר קיים במערכת'), backgroundColor: Colors.red));
          return;
        }
      }

      WriteBatch batch = FirebaseFirestore.instance.batch();
      
      batch.update(FirebaseFirestore.instance.collection('allowed_users').doc(docId), {
        'email': newEmail,
        'name': name,
        'surname': surname,
        'role': role,
        'allowedTabs': allowedTabs, 
      });

      final userSnap = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: oldEmail).get();
      if (userSnap.docs.isNotEmpty) {
        batch.update(userSnap.docs.first.reference, {
          'email': newEmail,
          'name': name,
          'surname': surname,
          'displayName': "$name $surname",
          'role': role,
          'allowedTabs': allowedTabs, 
        });
      }

      await batch.commit();
      nav.pop();
      scaffold.showSnackBar(const SnackBar(content: Text('השינויים נשמרו בהצלחה'), backgroundColor: Colors.green));
      setState(() => _tabController.index = 1); // Оставляем на вкладке списка
    } catch (e) {
      nav.pop();
      scaffold.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _fetchUserStats(String uid) async {
    _statTaken = 0;
    _statReturned = 0;
    _weekDayCounts = [0, 0, 0, 0, 0, 0, 0];

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
        int dayIndex = date.weekday == 7 ? 0 : date.weekday;
        if (dayIndex >= 0 && dayIndex < 7) {
          _weekDayCounts[dayIndex]++;
        }
      }
    }
  }

  // --- UI COMPONENTS ---

  /// Builds a clean grid of checkboxes for granular tab permissions. 
  /// Only rendered if the role is Admin.
  Widget _buildPermissionsGrid(List<String> selectedTabs, Function(String, bool) onTabToggled, {bool isLockedForUsersTab = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.teal.shade50.withOpacity(0.5), 
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.shade100)
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('הרשאות גישה אישיות (לשוניות למנהל):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF004D40))),
          const SizedBox(height: 15),
          Wrap(
            spacing: 15,
            runSpacing: 10,
            children: _availableTabs.entries.map((entry) {
              String tabKey = entry.key;
              String tabName = entry.value;
              
              bool isUsersTab = (tabKey == 'users');
              bool isChecked = selectedTabs.contains(tabKey);
              bool isDisabled = isUsersTab && isLockedForUsersTab;

              return SizedBox(
                width: 140, 
                child: CheckboxListTile(
                  title: Text(
                    tabName, 
                    style: TextStyle(
                      fontSize: 14, 
                      color: isDisabled ? Colors.grey : Colors.black87,
                      fontWeight: isChecked ? FontWeight.bold : FontWeight.normal
                    )
                  ),
                  value: isChecked,
                  activeColor: Colors.teal,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: isDisabled ? null : (bool? val) {
                    onTabToggled(tabKey, val ?? false);
                  },
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // --- DIALOGS ---

  void _showEditDialog(String docId, Map<String, dynamic> userData) {
    final emailCtrl = TextEditingController(text: userData['email']);
    final nameCtrl = TextEditingController(text: userData['name']);
    final surnameCtrl = TextEditingController(text: userData['surname']);
    String selectedRole = userData['role'] ?? 'user';
    
    List<String> editSelectedTabs = userData.containsKey('allowedTabs') 
        ? List<String>.from(userData['allowedTabs'])
        : ['dashboard', 'patients', 'items', 'pikadon', 'history', 'users'];

    bool initialHasUsersTab = editSelectedTabs.contains('users');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('עריכת פרטי משתמש', style: TextStyle(fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 500,
              child: Form(
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
                      _buildRoleDropdown(
                        selectedRole, 
                        (val) => setDialogState(() {
                          selectedRole = val!;
                          if (val == 'user') {
                            editSelectedTabs = ['dashboard', 'patients', 'items', 'pikadon', 'history'];
                          } else {
                            editSelectedTabs = ['dashboard', 'patients', 'items', 'pikadon', 'history', 'users'];
                          }
                        })
                      ),
                      
                      if (selectedRole == 'admin') ...[
                        const SizedBox(height: 20),
                        const Divider(),
                        const SizedBox(height: 10),
                        _buildPermissionsGrid(
                          editSelectedTabs, 
                          (tabKey, isChecked) {
                            setDialogState(() {
                              if (isChecked) {
                                editSelectedTabs.add(tabKey);
                              } else {
                                editSelectedTabs.remove(tabKey);
                              }
                            });
                          },
                          isLockedForUsersTab: initialHasUsersTab
                        ),
                      ]
                    ],
                  ),
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
                  if (selectedRole == 'admin' && editSelectedTabs.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('חובה להשאיר לפחות הרשאה אחת'), backgroundColor: Colors.red));
                    return;
                  }
                  
                  Navigator.pop(ctx);
                  await _updateUser(
                    docId, 
                    userData['email'], 
                    emailCtrl.text.trim().toLowerCase(), 
                    nameCtrl.text.trim(), 
                    surnameCtrl.text.trim(), 
                    selectedRole,
                    editSelectedTabs 
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
      final nav = Navigator.of(context, rootNavigator: true);
      final scaffold = ScaffoldMessenger.of(context);

      _showLoadingDialog();
      try {
        await EmailService.sendWelcomeEmail(name: name, email: email, role: role);
        nav.pop();
        scaffold.showSnackBar(SnackBar(content: Text('מייל נשלח בהצלחה ל-$email'), backgroundColor: Colors.green));
      } catch (e) {
        nav.pop();
        scaffold.showSnackBar(SnackBar(content: Text('שגיאה בשליחת המייל: $e'), backgroundColor: Colors.red));
      }
    }
  }

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
      final nav = Navigator.of(context, rootNavigator: true);
      final scaffold = ScaffoldMessenger.of(context);

      _showLoadingDialog();
      try {
        WriteBatch batch = FirebaseFirestore.instance.batch();
        batch.delete(FirebaseFirestore.instance.collection('allowed_users').doc(docId));
        
        final userSnap = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: email).get();
        if (userSnap.docs.isNotEmpty) {
          batch.update(userSnap.docs.first.reference, {'active': false});
        }
        
        await batch.commit();
        nav.pop();
        scaffold.showSnackBar(const SnackBar(content: Text('המשתמש נמחק בהצלחה'), backgroundColor: Colors.green));
      } catch (e) {
        nav.pop();
        scaffold.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

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
            _buildRoleDropdown(
              _addSelectedRole, 
              (val) => setState(() {
                _addSelectedRole = val!;
                if (val == 'user') {
                  _addSelectedTabs = ['dashboard', 'patients', 'items', 'pikadon', 'history'];
                } else {
                  _addSelectedTabs = ['dashboard', 'patients', 'items', 'pikadon', 'history', 'users'];
                }
              })
            ),
            
            if (_addSelectedRole == 'admin') ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 10),
              _buildPermissionsGrid(
                _addSelectedTabs, 
                (tabKey, isChecked) {
                  setState(() {
                    if (isChecked) {
                      _addSelectedTabs.add(tabKey);
                    } else {
                      _addSelectedTabs.remove(tabKey);
                    }
                  });
                },
                isLockedForUsersTab: false // Новый пользователь — чекбокс разблокирован
              ),
            ],

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
              _searchFilterCtrl.clear();
              setState(() => _searchQuery = "");
            },
            onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('allowed_users')
                .where('company_id', isEqualTo: widget.companyId)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              
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
                  
                  List<dynamic> allowedTabs = d['allowedTabs'] ?? ['dashboard', 'patients', 'items', 'pikadon', 'history', 'users'];

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
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d['email'], style: TextStyle(color: Colors.grey[700])),
                          const SizedBox(height: 4),
                          Text("גישה ל-${allowedTabs.length} לשוניות", style: const TextStyle(fontSize: 12, color: Colors.teal)),
                        ],
                      ),
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