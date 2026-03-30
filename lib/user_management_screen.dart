import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

// --- SCREEN 6: USER MANAGEMENT ---
class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();

  final Map<String, String> _roleDescriptions = {
    'user': 'לקיחה והחזר של ציוד, מתאים לפיזיוטרפיסטים',
    'admin': 'דשבורדים וניהול מערכת ידני',
  };
    
  final _addEmailCtrl = TextEditingController();
  final _addNameCtrl = TextEditingController();
  final _addSurnameCtrl = TextEditingController();
  String _addSelectedRole = 'user';
  String? _backendEmailError;
  String? _statusMessage;
  bool _isSuccessMessage = true;

  final _searchEmailCtrl = TextEditingController();
  final _editNameCtrl = TextEditingController();
  final _editSurnameCtrl = TextEditingController();
  String _editSelectedRole = 'user';
    
  bool _isSearching = false;
  bool _isEditingFoundUser = false;
  Map<String, dynamic>? _foundAllowedUser;
  Map<String, dynamic>? _foundRealUser;
  String? _foundAllowedDocId;

  bool _isLoadingStats = false;
  int _statTaken = 0;
  int _statReturned = 0;
  List<int> _weekDayCounts = [0, 0, 0, 0, 0, 0, 0];

  final String serviceId = 'service_sy28x2a';
  final String templateId = 'template_f8npr5p';
  final String userId = 'cena3ADJA-VpQkwqw';
    
  final String apkLink = 'https://drive.google.com/file/d/1qDLI0zx13iCYcIKTB_rDXXc6cDIG5b-t/view?usp=sharing';
  final String webLink = 'https://reot-logistic-warehouse.web.app/';

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
    _searchEmailCtrl.dispose();
    _editNameCtrl.dispose();
    _editSurnameCtrl.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    // Regex allows letters, numbers, dots, underscores, and hyphens before the @ symbol
    // It also allows multiple dots in the domain name (e.g., .org.il)
    return RegExp(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$").hasMatch(email);
  }

  void _showStatus(String msg, {bool success = true}) {
    setState(() {
      _statusMessage = msg;
      _isSuccessMessage = success;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _statusMessage = null);
    });
  }

  Future<void> _sendWelcomeEmail(String email, String name, String role) async {
    final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');

    String adminMsg = "";
    if (role == 'admin') {
      adminMsg = "\n\nקישור לממשק מנהלים (Admin):\n$webLink";
    }

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'service_id': serviceId,
          'template_id': templateId,
          'user_id': userId,
          'template_params': {
            'to_name': name,
            'to_email': email,
            'android_link': apkLink, 
            'ios_link': webLink,     
            'admin_info': adminMsg   
          }
        }),
      );
        
      if (response.statusCode == 200) {
        print("Email sent successfully to $email");
      } else {
        print("Email Error: ${response.body}");
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text("שגיאה בשליחת מייל: ${response.body}"), backgroundColor: Colors.red)
           );
        }
      }
    } catch (e) {
      print("Email Network Error: $e");
    }
  }

  Future<void> _addNewUser() async {
    setState(() { _backendEmailError = null; });
    if (!_formKey.currentState!.validate()) return;

    try {
      final check = await FirebaseFirestore.instance
          .collection('allowed_users')
          .where('email', isEqualTo: _addEmailCtrl.text.trim().toLowerCase())
          .get();

      if (check.docs.isNotEmpty) {
        setState(() { _backendEmailError = 'שגיאה: המשתמש כבר קיים במערכת'; });
        _formKey.currentState!.validate();
        return;
      }

      await FirebaseFirestore.instance.collection('allowed_users').add({
        'email': _addEmailCtrl.text.trim().toLowerCase(),
        'name': _addNameCtrl.text.trim(),
        'surname': _addSurnameCtrl.text.trim(),
        'role': _addSelectedRole,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _sendWelcomeEmail(
        _addEmailCtrl.text.trim(), 
        _addNameCtrl.text.trim(),
        _addSelectedRole
      );

      _showStatus('משתמש נוסף ומייל נשלח!', success: true);
        
      _addEmailCtrl.clear();
      _addNameCtrl.clear();
      _addSurnameCtrl.clear();
      setState(() { _addSelectedRole = 'user'; });

    } catch (e) {
      _showStatus('Error: $e', success: false);
    }
  }

  Future<void> _fetchUserStats(String uid) async {
    setState(() {
      _isLoadingStats = true;
      _statTaken = 0;
      _statReturned = 0;
      _weekDayCounts = [0, 0, 0, 0, 0, 0, 0];
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('History')
          .where('staffUid', isEqualTo: uid)
          .get();

      int taken = 0;
      int returned = 0;
      List<int> days = [0, 0, 0, 0, 0, 0, 0];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        String action = data['action'] ?? '';
          
        if (action == 'take') taken++;
        if (action == 'return') returned++;

        if (data['timestamp'] != null) {
          DateTime date = (data['timestamp'] as Timestamp).toDate();
          int dayIndex = date.weekday;
          if (dayIndex == 7) dayIndex = 0;
            
          if (dayIndex >= 0 && dayIndex < 7) {
            days[dayIndex]++;
          }
        }
      }

      setState(() {
        _statTaken = taken;
        _statReturned = returned;
        _weekDayCounts = days;
        _isLoadingStats = false;
      });

    } catch (e) {
      print("Stats Error: $e");
      setState(() { _isLoadingStats = false; });
    }
  }

  Future<void> _searchUser() async {
    final email = _searchEmailCtrl.text.trim().toLowerCase();
    if (email.isEmpty) return;

    setState(() {
      _isSearching = true;
      _statusMessage = null;
      _foundAllowedUser = null;
      _foundRealUser = null;
      _isEditingFoundUser = false;
      _statTaken = 0;
      _statReturned = 0;
    });

    try {
      final allowedSnapshot = await FirebaseFirestore.instance
          .collection('allowed_users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (allowedSnapshot.docs.isEmpty) {
        _showStatus('משתמש לא נמצא ברשימת המורשים', success: false);
        setState(() { _isSearching = false; });
        return;
      }

      final allowedDoc = allowedSnapshot.docs.first;
        
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      Map<String, dynamic>? realUser;
      if (usersSnapshot.docs.isNotEmpty) {
        realUser = usersSnapshot.docs.first.data();
        if (realUser != null && realUser['uid'] != null) {
          _fetchUserStats(realUser['uid']);
        }
      }

      setState(() {
        _foundAllowedDocId = allowedDoc.id;
        _foundAllowedUser = allowedDoc.data();
        _foundRealUser = realUser;
          
        _editNameCtrl.text = _foundAllowedUser?['name'] ?? '';
        _editSurnameCtrl.text = _foundAllowedUser?['surname'] ?? '';
        _editSelectedRole = _foundAllowedUser?['role'] ?? 'user';
          
        _isSearching = false;
      });

    } catch (e) {
      _showStatus('Error: $e', success: false);
      setState(() { _isSearching = false; });
    }
  }

  Future<void> _saveUserEdits() async {
    if (_foundAllowedDocId == null) return;
    try {
      WriteBatch batch = FirebaseFirestore.instance.batch();
      DocumentReference allowedRef = FirebaseFirestore.instance.collection('allowed_users').doc(_foundAllowedDocId);
      batch.update(allowedRef, {
        'name': _editNameCtrl.text.trim(),
        'surname': _editSurnameCtrl.text.trim(),
        'role': _editSelectedRole,
      });

      if (_foundRealUser != null && _foundRealUser!['uid'] != null) {
        DocumentReference userRef = FirebaseFirestore.instance.collection('users').doc(_foundRealUser!['uid']);
        batch.update(userRef, {
          'name': _editNameCtrl.text.trim(),
          'surname': _editSurnameCtrl.text.trim(),
          'displayName': "${_editNameCtrl.text.trim()} ${_editSurnameCtrl.text.trim()}",
          'role': _editSelectedRole,
        });
      }

      await batch.commit();
      _showStatus('השינויים נשמרו בהצלחה!', success: true);
      setState(() { _isEditingFoundUser = false; });
      _searchUser();
    } catch (e) {
      _showStatus('Error saving: $e', success: false);
    }
  }

  Future<void> _deleteUser() async {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת משתמש'),
          content: const Text('האם אתה בטוח? המשתמש יוסר מהמערכת ולא יוכל להתחבר יותר.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ביטול')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(ctx);
                await _executeDelete();
              },
              child: const Text('מחק משתמש'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeDelete() async {
     if (_foundAllowedDocId == null) return;
     try {
       WriteBatch batch = FirebaseFirestore.instance.batch();
       DocumentReference allowedRef = FirebaseFirestore.instance.collection('allowed_users').doc(_foundAllowedDocId);
       batch.delete(allowedRef);
       if (_foundRealUser != null && _foundRealUser!['uid'] != null) {
         DocumentReference userRef = FirebaseFirestore.instance.collection('users').doc(_foundRealUser!['uid']);
         batch.update(userRef, { 'active': false });
       }
       await batch.commit();
       _showStatus('המשתמש נמחק והגישה נחסמה.', success: true);
       setState(() {
         _foundAllowedUser = null;
         _foundRealUser = null;
         _foundAllowedDocId = null;
         _searchEmailCtrl.clear();
       });
     } catch (e) {
       _showStatus('Error deleting: $e', success: false);
     }
  }

  Widget _buildStatusMessage() {
    if (_statusMessage == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _isSuccessMessage ? Colors.green[100] : Colors.red[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _isSuccessMessage ? Colors.green : Colors.red, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_isSuccessMessage ? Icons.check_circle : Icons.error, color: _isSuccessMessage ? Colors.green[800] : Colors.red[800]),
          const SizedBox(width: 10),
          Expanded(child: Text(_statusMessage!, textAlign: TextAlign.center, style: TextStyle(color: _isSuccessMessage ? Colors.green[900] : Colors.red[900], fontWeight: FontWeight.bold, fontSize: 16))),
        ],
      ),
    );
  }

  Widget _buildRoleDropdown(String currentVal, Function(String?) onChanged, bool enabled) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: currentVal,
          decoration: const InputDecoration(labelText: 'תפקיד (Role)', border: OutlineInputBorder()),
          items: _roleDescriptions.keys.map((role) => DropdownMenuItem(value: role, child: Text(role.toUpperCase()))).toList(),
          onChanged: enabled ? onChanged : null,
        ),
        const SizedBox(height: 5),
        Text(_roleDescriptions[currentVal] ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
      ],
    );
  }

  Widget _buildStatsArea() {
    if (_isLoadingStats) {
      return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
    }

    if (_foundRealUser == null) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!)
        ),
        child: Column(
          children: const [
            Icon(Icons.query_stats, size: 50, color: Colors.grey),
            SizedBox(height: 10),
            Text("אין נתונים סטטיסטיים", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
            Text("המשתמש טרם התחבר למערכת", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    int maxVal = _weekDayCounts.reduce(max);
    if (maxVal == 0) maxVal = 1;

    List<String> dayLabels = ['א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ש'];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("סטטיסטיקת משתמש", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF004D40))),
          const Divider(),
          const SizedBox(height: 10),
            
          Row(
            children: [
              Expanded(
                child: _buildStatCard("פריטים שנלקחו", _statTaken.toString(), Colors.orange.shade100, Colors.orange.shade800),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatCard("פריטים שהוחזרו", _statReturned.toString(), Colors.green.shade100, Colors.green.shade800),
              ),
            ],
          ),
          const SizedBox(height: 20),
            
          const Text("פעילות לפי ימי השבוע:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 10),
          SizedBox(
            height: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (index) {
                int count = _weekDayCounts[index];
                double barHeight = (count / maxVal) * 80;
                if (count > 0 && barHeight < 5) barHeight = 5;

                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                     if (count > 0) Text(count.toString(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                     Container(
                       width: 20,
                       height: barHeight,
                       decoration: BoxDecoration(
                         color: count > 0 ? const Color(0xFF00796B) : Colors.grey.shade200,
                         borderRadius: BorderRadius.circular(4),
                       ),
                     ),
                     const SizedBox(height: 5),
                     Text(dayLabels[index], style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                );
              }),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
          Text(title, style: TextStyle(color: textColor, fontSize: 14)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String lastLoginText = "טרם התחבר למערכת (Never Logged In)";
    if (_foundRealUser != null && _foundRealUser!['lastLogin'] != null) {
      lastLoginText = (_foundRealUser!['lastLogin'] as Timestamp).toDate().toString().substring(0, 16);
    }

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
              Tab(text: 'הוספת משתמש חדש', icon: Icon(Icons.person_add)),
              Tab(text: 'עריכת / מחיקת משתמש', icon: Icon(Icons.manage_accounts)),
            ],
          ),
        ),
          
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      const Text('הוספת משתמש חדש למערכת', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _addEmailCtrl,
                        decoration: const InputDecoration(labelText: 'אימייל', border: OutlineInputBorder()),
                        onChanged: (_) { if (_backendEmailError != null) setState(() => _backendEmailError = null); },
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'נא להזין אימייל';
                          if (!_isValidEmail(value)) return 'פורמט אימייל שגוי';
                          if (_backendEmailError != null) return _backendEmailError;
                          return null;
                        },
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(child: TextFormField(
                            controller: _addNameCtrl,
                            decoration: const InputDecoration(labelText: 'שם פרטי', border: OutlineInputBorder()),
                            validator: (v) => v!.isEmpty ? 'חובה למלא' : null,
                          )),
                          const SizedBox(width: 15),
                          Expanded(child: TextFormField(
                            controller: _addSurnameCtrl,
                            decoration: const InputDecoration(labelText: 'שם משפחה', border: OutlineInputBorder()),
                            validator: (v) => v!.isEmpty ? 'חובה למלא' : null,
                          )),
                        ],
                      ),
                      const SizedBox(height: 15),
                      _buildRoleDropdown(_addSelectedRole, (val) => setState(() => _addSelectedRole = val!), true),
                      const SizedBox(height: 20),
                      _buildStatusMessage(),
                      SizedBox(
                        width: double.infinity, height: 50,
                        child: ElevatedButton.icon(icon: const Icon(Icons.save), label: const Text('שמור והוסף'), onPressed: _addNewUser),
                      ),
                    ],
                  ),
                ),
              ),

              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 300),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: TextField(
                          controller: _searchEmailCtrl,
                          decoration: const InputDecoration(labelText: 'חפש לפי אימייל', border: OutlineInputBorder()),
                          onSubmitted: (_) => _searchUser(),
                        )),
                        const SizedBox(width: 10),
                        IconButton(
                          icon: _isSearching ? const CircularProgressIndicator() : const Icon(Icons.search),
                          onPressed: _isSearching ? null : _searchUser,
                          iconSize: 30, color: const Color(0xFF004D40),
                        )
                      ],
                    ),
                    const Divider(height: 20),
                    _buildStatusMessage(),
                    const SizedBox(height: 10),

                    if (_foundAllowedUser != null) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('פרטי משתמש:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Last Login
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)),
                        child: Row(
                          children: [
                            const Icon(Icons.history, color: Colors.teal),
                            const SizedBox(width: 10),
                            const Text("כניסה אחרונה: ", style: TextStyle(fontWeight: FontWeight.bold)),
                            Expanded(child: Text(lastLoginText, style: TextStyle(color: Colors.grey[800]))),
                          ],
                        ),
                      ),

                      _buildStatsArea(),
                        
                      const SizedBox(height: 20),

                      // Edit Button Row
                      Row(
                        children: [
                           const Text('פרטים אישיים:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                           const Spacer(),
                           if (!_isEditingFoundUser)
                             TextButton.icon(
                               onPressed: () => setState(() => _isEditingFoundUser = true),
                               icon: const Icon(Icons.edit),
                               label: const Text('ערוך פרטים'),
                               style: TextButton.styleFrom(foregroundColor: Colors.blue),
                             )
                        ],
                      ),
                      const SizedBox(height: 10),

                      TextField(controller: _editNameCtrl, enabled: _isEditingFoundUser, decoration: const InputDecoration(labelText: 'שם פרטי', border: OutlineInputBorder())),
                      const SizedBox(height: 10),
                      TextField(controller: _editSurnameCtrl, enabled: _isEditingFoundUser, decoration: const InputDecoration(labelText: 'שם משפחה', border: OutlineInputBorder())),
                      const SizedBox(height: 10),
                      _buildRoleDropdown(_editSelectedRole, (val) => setState(() => _editSelectedRole = val!), _isEditingFoundUser),
                      const SizedBox(height: 30),
                        
                      if (_isEditingFoundUser)
                        SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: _saveUserEdits, style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text('שמור שינויים'))),
                      const SizedBox(height: 20),
                      SizedBox(width: double.infinity, height: 50, child: OutlinedButton.icon(onPressed: _deleteUser, icon: const Icon(Icons.delete, color: Colors.red), label: const Text('מחק משתמש מהמערכת', style: TextStyle(color: Colors.red)), style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)))),
                    ] else if (!_isSearching && _searchEmailCtrl.text.isNotEmpty && _statusMessage == null) ...[
                        const Text('לא נמצא משתמש. אנא בדוק את האימייל.', style: TextStyle(color: Colors.grey)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}