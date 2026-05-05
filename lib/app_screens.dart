import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart' hide Address;
import 'package:http/http.dart' as http;
import 'user_management_screen.dart';
import 'security_service.dart';
import 'items_screen.dart';
import 'history_screen.dart';
import 'dashboard_screen.dart';
import 'patients_screen.dart';
import 'pikadon_screen.dart'; 
import 'main.dart';
// ВНИМАНИЕ: Класс PikadonLogic отсюда УДАЛЕН. 
// Программа теперь берет его из файла security_service.dart, чтобы не было ошибок компиляции.

// --- SCREEN 1: LOGIN ---
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
    
  bool _isCodeSent = false;
  bool _isLoading = false;

  String? _fetchedName;
  String? _fetchedSurname;
  String? _fetchedRole;
  String? _generatedCode;

  // --- EMAILJS CONFIGURATION ---
  final String serviceId = 'service_sy28x2a';
  final String templateId = 'template_je2ry6c';
  final String userId = 'cena3ADJA-VpQkwqw';
  // -----------------------------

  Future<void> _verifyEmailAndSendCode() async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty) return;

    setState(() { _isLoading = true; });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('allowed_users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        _showSnack('האימייל לא נמצא במערכת (אין גישה)');
        setState(() { _isLoading = false; });
        return;
      }

      final data = snapshot.docs.first.data();
      _fetchedName = data['name'];
      _fetchedSurname = data['surname'];
      _fetchedRole = data['role'] ?? 'user';

      if (_fetchedName == null) {
        _showSnack('שגיאה: חסר שם בהגדרות המערכת');
        setState(() { _isLoading = false; });
        return;
      }

      var rng = Random();
      _generatedCode = (rng.nextInt(900000) + 100000).toString();

      await _sendEmailJS(
      name: _fetchedName!,
      email: email,
      code: _generatedCode!,
      updateLink: LATEST_UPDATE_URL, // Passing the parameter here
    );

      setState(() {
        _isCodeSent = true;
        _isLoading = false;
      });
      _showSnack('קוד נשלח למייל בהצלחה!');
        
    } catch (e) {
      _showSnack('שגיאה בשליחת אימייל: $e');
      setState(() { _isLoading = false; });
    }
  }

  Future<void> _sendEmailJS({
    required String name, 
    required String email, 
    required String code,
    required String updateLink, // New required parameter
  }) async {
    final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');
      
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'service_id': serviceId,
        'template_id': templateId,
        'user_id': userId,
        'template_params': {
          'to_name': name,
          'to_email': email,
          'message': code,        // Verification code
          'app_link': updateLink,  // This is your new parameter for the template!
        }
      }),
    );

    if (response.statusCode != 200) {
      throw 'EmailJS Error: ${response.body}';
    }
  }

  Future<void> _verifyCodeAndLogin() async {
    final code = _otpController.text.trim();
      
    if (code != _generatedCode) {
      _showSnack('קוד שגוי');
      return;
    }

    setState(() { _isLoading = true; });

    try {
      UserCredential userCredential;
        
      try {
        userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: "AppPassword123!",
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
           userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: "AppPassword123!",
          );
        } else {
          throw e;
        }
      }

      User? user = userCredential.user;
      if (user != null) {
        String fullName = "$_fetchedName $_fetchedSurname";
        await user.updateDisplayName(fullName);
        
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'email': user.email,
          'name': _fetchedName,
          'surname': _fetchedSurname,
          'displayName': fullName,
          'role': _fetchedRole,
          'active': true,
          'lastLogin': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await user.reload();
      }

    } catch (e) {
      _showSnack('שגיאת כניסה: $e');
      setState(() { _isLoading = false; });
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/reuth_logo.png',
                  height: 220,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 30),
                  
                const Text(
                  'כניסה למערכת',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF004D40)),
                ),
                const SizedBox(height: 40),
                  
                if (!_isCodeSent) ...[
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'אימייל',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    onSubmitted: (_) => _verifyEmailAndSendCode(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _verifyEmailAndSendCode,
                      child: _isLoading 
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('שלח קוד', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ] else ...[
                  Text(
                    'שלום $_fetchedName $_fetchedSurname',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'קוד נשלח ל-${_emailController.text}',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _otpController,
                    decoration: const InputDecoration(
                      labelText: 'קוד אימות',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock),
                    ),
                    keyboardType: TextInputType.number,
                    onSubmitted: (_) => _verifyCodeAndLogin(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _verifyCodeAndLogin,
                      child: _isLoading 
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('כניסה', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() { _isCodeSent = false; }),
                    child: const Text('שנה אימייל')
                  ),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- SCREEN 2: HOME (ROUTER WITH LOCK) ---
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

// --- SCREEN 3: USER HOME ---
class UserHomeScreen extends StatelessWidget {
  final String displayName;
  const UserHomeScreen({super.key, required this.displayName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ניהול ציוד רפואי', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          )
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Image.asset(
              'assets/reuth_logo.png',
              height: 200,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 30),
              
            Text(
              'שלום, $displayName',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF004D40)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'ברוכים הבאים למערכת',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 50),
            SizedBox(
              width: 250,
              height: 60,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('קח ציוד', style: TextStyle(fontSize: 20)),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ScannerScreen(mode: 'take')),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 250,
              height: 60,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.assignment_return),
                label: const Text('החזר ציוד', style: TextStyle(fontSize: 20)),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ScannerScreen(mode: 'return')),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- SCREEN 4: ADMIN DASHBOARD ---
class AdminDashboard extends StatefulWidget {
  final String displayName; 
  const AdminDashboard({super.key, required this.displayName});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const DashboardScreen(), 
    const UserManagementScreen(), 
    const PatientsManagementScreen(), 
    const ItemsManagementScreen(), 
    const PikadonScreen(), 
    const HistoryScreen(), 
  ];

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
                  stream: FirebaseFirestore.instance
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

// --- SCREEN 5: SCANNER LOGIC ---
class ScannerScreen extends StatefulWidget {
  final String mode;

  const ScannerScreen({super.key, required this.mode});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  MobileScannerController controller = MobileScannerController();
  final TextEditingController _manualInputController = TextEditingController();
    
  bool _isProcessing = false;
  List<DocumentSnapshot> _sessionItems = [];
  bool _isAddingMoreItems = false;
  bool _isScanningPatient = false;
  DocumentSnapshot? _returnCandidate;
  bool _showReturnConfirmation = false;
  
  // Error flags
  bool _itemInUseError = false;
  bool _itemFreeError = false; 
  bool _itemBrokenError = false;
  bool _itemAlreadyInListError = false;
  bool _itemNotFoundError = false; 
  bool _invalidBarcodeFormatError = false; 
  
  // Data for error screens
  String? _errorItemName;
  String? _errorItemGroup; // <--- НОВОЕ ПОЛЕ ДЛЯ ОШИБОК
  String? _errorPatientId;
  String? _errorItemId;
  String? _lastScannedBarcode; 

  @override
  void dispose() {
    controller.dispose();
    _manualInputController.dispose();
    super.dispose();
  }

  // Helper to fetch group name
  Future<String> _getGroupName(Map<String, dynamic> data) async {
    if (data.containsKey('group') && data['group'] != null && data['group'].toString().isNotEmpty) {
      return data['group'].toString();
    }
    String gId = data['GroupID'] ?? '';
    if (gId.isEmpty) return 'לא הוגדר';
    try {
      var doc = await FirebaseFirestore.instance.collection('items_groups').doc(gId).get();
      if (doc.exists) return (doc.data() as Map<String, dynamic>)['name'] ?? 'לא הוגדר';
    } catch (_) {}
    return 'לא הוגדר';
  }

  bool _isValidItemBarcode(String barcode) {
    if (barcode.length != 8) return false;
    if (!barcode.startsWith('88')) return false;
    if (int.tryParse(barcode) == null) return false;

    String base = barcode.substring(0, 7);
    int expectedCheckDigit = int.parse(barcode.substring(7));
    
    int sum = 0;
    bool alternate = true;
    for (int i = base.length - 1; i >= 0; i--) {
      int n = int.parse(base[i]);
      if (alternate) {
        n *= 2;
        if (n > 9) n = (n % 10) + 1;
      }
      sum += n;
      alternate = !alternate;
    }
    
    int calculatedCheckDigit = (10 - (sum % 10)) % 10;
    return expectedCheckDigit == calculatedCheckDigit;
  }

  void _resetScan() {
    setState(() {
      _sessionItems.clear();
      _isAddingMoreItems = false;
      _isScanningPatient = false;
      _returnCandidate = null;
      _showReturnConfirmation = false;
      
      _itemInUseError = false;
      _itemFreeError = false;
      _itemBrokenError = false;
      _itemAlreadyInListError = false;
      _itemNotFoundError = false;
      _invalidBarcodeFormatError = false;
      
      _errorItemName = null;
      _errorItemGroup = null; // сброс группы
      _errorPatientId = null;
      _errorItemId = null;
      _lastScannedBarcode = null;
      _isProcessing = false;
    });
  }

  void _dismissError() {
    setState(() {
      _itemInUseError = false;
      _itemFreeError = false;
      _itemBrokenError = false;
      _itemAlreadyInListError = false;
      _itemNotFoundError = false;
      _invalidBarcodeFormatError = false;
      
      _errorItemName = null;
      _errorItemGroup = null;
      _errorPatientId = null;
      _errorItemId = null;
      _lastScannedBarcode = null;
      _isProcessing = false;
    });
  }

  void _backToList() {
    setState(() {
      _itemInUseError = false;
      _itemFreeError = false;
      _itemBrokenError = false;
      _itemAlreadyInListError = false;
      _itemNotFoundError = false;
      _invalidBarcodeFormatError = false;
      
      _lastScannedBarcode = null;
      _errorItemGroup = null;
      _isProcessing = false;
      _isAddingMoreItems = false; 
    });
  }

  void _scanNextItem() {
    setState(() {
      _isAddingMoreItems = true;
      _isProcessing = false;
    });
  }

  void _goToPatientScan() {
    setState(() {
      _isScanningPatient = true;
      _isAddingMoreItems = false;
      _isProcessing = false;
    });
  }

  void _confirmRemoveItem(int index) {
    final item = _sessionItems[index];
    final data = item.data() as Map<String, dynamic>;
    String name = data['name'] ?? 'Unknown';

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת פריט'),
          content: Text('האם להסיר את "$name" מהרשימה?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('לא'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _sessionItems.removeAt(index);
                  if (_sessionItems.isEmpty) {
                    _isAddingMoreItems = false;
                    _isProcessing = false;
                  }
                });
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('כן, מחק'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFinalAssignmentDialog(String patientId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('items_groups').snapshots(),
          builder: (context, snapshot) {
            Map<String, String> groupNamesMap = {};
            if (snapshot.hasData) {
              for (var doc in snapshot.data!.docs) {
                groupNamesMap[doc.id] = (doc.data() as Map<String, dynamic>)['name']?.toString() ?? 'לא ידוע';
              }
            }

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text('אישור שיוך למטופל'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       Text('המטופל (ID): $patientId', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
                       const SizedBox(height: 10),
                       const Text('הפריטים לשיוך:'),
                       const Divider(),
                       ..._sessionItems.map((doc) {
                          final d = doc.data() as Map<String, dynamic>;
                          String groupId = d['GroupID'] ?? '';
                          String groupName = d['group'] ?? groupNamesMap[groupId] ?? 'לא הוגדר';
                          
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (groupName.isNotEmpty) 
                                  Text("קבוצה: $groupName", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 15)),
                                Text(d['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text('ID: ${d['ID']}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                              ],
                            ),
                          );
                       }).toList(),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                       Navigator.pop(ctx); 
                       setState(() { _isProcessing = false; });
                    },
                    child: const Text('ביטול'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      // Передаем мапу с группами внутрь _executeAssignment
                      _executeAssignment(patientId, groupNamesMap);
                    },
                    child: const Text('אישור (החל)'),
                  ),
                ],
              ),
            );
          }
        );
      },
    );
  }

  // UPDATED: Added group parameter and History updating
  Future<void> _executeAssignment(String patientId, Map<String, String> groupNamesMap) async {
    try {
      String encryptedPatientId = SecurityService.encryptID(patientId);
      final user = FirebaseAuth.instance.currentUser;
        
      WriteBatch batch = FirebaseFirestore.instance.batch();

      for (var doc in _sessionItems) {
        batch.update(doc.reference, {
          'status': 'in_use',
          'patientId': encryptedPatientId,
          'lastTaken': FieldValue.serverTimestamp(),
        });

        final itemData = doc.data() as Map<String, dynamic>;
        String groupName = itemData['group'] ?? groupNamesMap[itemData['GroupID']] ?? 'לא הוגדר';

        final historyRef = FirebaseFirestore.instance.collection('History').doc();
        batch.set(historyRef, {
          'itemId': itemData['ID'],
          'itemName': itemData['name'],
          'group': groupName, // <--- ADDED GROUP TO HISTORY
          'action': 'take',
          'patientId': encryptedPatientId,
          'timestamp': FieldValue.serverTimestamp(),
          'staffUid': user?.uid,
        });
      }

      await batch.commit();

      for (var doc in _sessionItems) {
        final itemData = doc.data() as Map<String, dynamic>;
        double itemCost = double.tryParse(itemData['cost']?.toString() ?? '0') ?? 0.0;
        String groupName = itemData['group'] ?? groupNamesMap[itemData['GroupID']] ?? 'לא הוגדר';

        if (itemCost > 0) {
          // ВНИМАНИЕ: Здесь добавлен 4-й аргумент groupName. 
          // Метод в security_service.dart должен быть обновлен (см. ниже).
          await PikadonLogic.addToPendingPikadon(
            encryptedPatientId, 
            itemData['ID'].toString(), 
            itemData['name'] ?? 'Unknown', 
            groupName, // <--- ADDED GROUP FOR PIKADON
            itemCost,
            user?.uid 
          );
        }
      }

      _showSnack('הפעולה בוצעה בהצלחה!');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showSnack('שגיאה בשמירה: $e');
      setState(() { _isProcessing = false; });
    }
  }

  Future<DocumentSnapshot?> _findItemSnapshot(String barcode) async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('items')
          .where('ID', isEqualTo: barcode)
          .limit(1)
          .get();
      if (querySnapshot.docs.isNotEmpty) return querySnapshot.docs.first;
    } catch (e) { print("Error: $e"); }
    return null;
  }

  void _handleBarcode(BarcodeCapture capture) async {
    if (_isProcessing) return;

    bool hasAnyError = _itemInUseError || _itemFreeError || _itemBrokenError || _itemAlreadyInListError || _itemNotFoundError || _invalidBarcodeFormatError;
    bool isCameraHidden = hasAnyError || 
                          (widget.mode == 'take' && _sessionItems.isNotEmpty && !_isAddingMoreItems && !_isScanningPatient) || 
                          (widget.mode == 'return' && _showReturnConfirmation);
                          
    if (isCameraHidden) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String barcode = barcodes.first.rawValue ?? "Unknown";
      setState(() { _isProcessing = true; });

      if (widget.mode == 'take') {
        await _handleTakeFlow(barcode);
      } else {
        await _handleReturnFlow(barcode);
      }
    }
  }

  Future<void> _handleTakeFlow(String barcode) async {
    if (_isScanningPatient) {
      if (barcode.trim().isEmpty) {
        _showSnack('שגיאה: ברקוד ריק');
        await Future.delayed(const Duration(seconds: 2));
        setState(() { _isProcessing = false; });
        return;
      }
      await _showFinalAssignmentDialog(barcode);
      return;
    }

    if (!_isValidItemBarcode(barcode)) {
      setState(() {
        _invalidBarcodeFormatError = true;
        _lastScannedBarcode = barcode;
        _isProcessing = false;
      });
      return;
    }

    bool alreadyInList = _sessionItems.any((doc) => doc['ID'] == barcode);
    if (alreadyInList) {
      setState(() {
        _itemAlreadyInListError = true;
        _lastScannedBarcode = barcode;
        _isProcessing = false;
      });
      return;
    }

    DocumentSnapshot? doc = await _findItemSnapshot(barcode);
    
    if (doc == null) {
      setState(() {
         _itemNotFoundError = true;
         _lastScannedBarcode = barcode;
         _isProcessing = false;
      });
      return;
    }

    final data = doc.data() as Map<String, dynamic>;
    String status = data['status'] ?? 'available';

    if (status == 'broken' || status == 'lost' || status == 'sold' || status == 'other') {
      String groupName = await _getGroupName(data);
      setState(() {
        _itemBrokenError = true;
        _errorItemName = data['name'];
        _errorItemGroup = groupName;
        _errorItemId = data['ID'];
        _isProcessing = false;
      });
      return;
    }

    if (status == 'in_use') {
      String encryptedPid = data['patientId'] ?? '';
      String realPid = SecurityService.decryptID(encryptedPid);
      String groupName = await _getGroupName(data);

      setState(() {
        _itemInUseError = true;
        _errorItemName = data['name'];
        _errorItemGroup = groupName;
        _errorPatientId = realPid;
        _isProcessing = false;
      });
      return;
    }

    setState(() {
      _sessionItems.add(doc);
      _itemInUseError = false;
      _itemBrokenError = false;
      _itemAlreadyInListError = false;
      _itemNotFoundError = false;
      _invalidBarcodeFormatError = false;
      _isAddingMoreItems = false;
      _isProcessing = false;
    });
  }

  Future<void> _handleReturnFlow(String barcode) async {
    if (!_isValidItemBarcode(barcode)) {
      setState(() {
        _invalidBarcodeFormatError = true;
        _lastScannedBarcode = barcode;
        _isProcessing = false;
      });
      return;
    }

    DocumentSnapshot? doc = await _findItemSnapshot(barcode);

    if (doc == null) {
      setState(() {
         _itemNotFoundError = true;
         _lastScannedBarcode = barcode;
         _isProcessing = false;
      });
      return;
    }

    final data = doc.data() as Map<String, dynamic>;
    String status = data['status'] ?? 'available';

    if (status == 'available') {
      String groupName = await _getGroupName(data);
      setState(() {
         _itemFreeError = true;
         _errorItemName = data['name'];
         _errorItemGroup = groupName;
         _errorItemId = data['ID'];
         _isProcessing = false;
      });
      return;
    }

    setState(() {
      _returnCandidate = doc;
      _showReturnConfirmation = true;
      _isProcessing = false;
    });
  }

  // UPDATED: Fetches group name and stores to History
  Future<void> _confirmReturn() async {
    if (_returnCandidate == null || _isProcessing) return;

    setState(() { _isProcessing = true; });

    final data = _returnCandidate!.data() as Map<String, dynamic>;
    String encryptedPid = data['patientId'] ?? 'Unknown';
    String iId = data['ID'] ?? 'Unknown';
    String itemName = data['name'] ?? 'Unknown';
    String groupName = await _getGroupName(data);

    try {
      final user = FirebaseAuth.instance.currentUser;
      WriteBatch batch = FirebaseFirestore.instance.batch();
        
      batch.update(_returnCandidate!.reference, {
        'status': 'available',
        'patientId': null,
      });

      final historyRef = FirebaseFirestore.instance.collection('History').doc();
      batch.set(historyRef, {
        'itemId': iId,
        'itemName': itemName,
        'group': groupName, // <--- ADDED GROUP TO HISTORY
        'action': 'return',
        'patientId': encryptedPid,
        'timestamp': FieldValue.serverTimestamp(),
        'staffUid': user?.uid,
      });

      await batch.commit();

      _showSnack('הפריט הוחזר בהצלחה!');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showSnack('שגיאה: $e');
      setState(() { _isProcessing = false; });
    }
  }

  void _showManualEntryDialog() {
    _manualInputController.clear();
    
    String dialogTitle = _isScanningPatient ? 'הכנס מספר מטופל' : 'הכנס קוד פריט';
    String hintText = _isScanningPatient ? 'מספר מטופל (לדוגמה: 123456789)' : 'סרוק קוד (לדוגמה: 88000013)';

    showDialog(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(dialogTitle),
            content: TextField(
              controller: _manualInputController,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(hintText: hintText),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ביטול'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  String code = _manualInputController.text.trim();
                  if (code.isNotEmpty) {
                    setState(() { _isProcessing = true; });
                    if (widget.mode == 'take') {
                       _handleTakeFlow(code);
                    } else {
                       _handleReturnFlow(code);
                    }
                  }
                },
                child: const Text('אישור'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    String title = widget.mode == 'take' ? 'קח ציוד' : 'החזר ציוד';
    
    Color headerColor = const Color(0xFF004D40); 
    if (_itemInUseError || _itemFreeError || _itemBrokenError || _invalidBarcodeFormatError) {
      headerColor = Colors.red[900]!;
    } else if (_itemAlreadyInListError) {
      headerColor = Colors.blue[800]!; 
    } else if (_itemNotFoundError) {
      headerColor = Colors.orange[800]!; 
    }

    String fabLabel = _isScanningPatient ? 'הכנס מספר מטופל' : 'הכנס קוד ידנית';

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(color: Colors.white)),
        backgroundColor: headerColor,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _resetScan)],
      ),
      floatingActionButton: _shouldShowManualButton() 
        ? FloatingActionButton.extended(
            backgroundColor: const Color(0xFF00796B),
            onPressed: _showManualEntryDialog,
            icon: const Icon(Icons.keyboard, color: Colors.white),
            label: Text(fabLabel, style: const TextStyle(color: Colors.white)),
          )
        : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: Column(
        children: [
          Expanded(flex: 5, child: _buildMainContent()),
          if (!_shouldHideBottomText())
            Expanded(flex: 2, child: _buildInstructionArea()),
        ],
      ),
    );
  }

  bool _shouldShowManualButton() {
    bool hasAnyError = _itemInUseError || _itemFreeError || _itemBrokenError || _itemAlreadyInListError || _itemNotFoundError || _invalidBarcodeFormatError;
    if (hasAnyError) return false;
    if (_showReturnConfirmation) return false;
    
    if (widget.mode == 'take' && _sessionItems.isNotEmpty && !_isAddingMoreItems && !_isScanningPatient) {
      return false;
    }
    
    return true;
  }

  bool _shouldHideBottomText() {
    bool hasAnyError = _itemInUseError || _itemFreeError || _itemBrokenError || _itemAlreadyInListError || _itemNotFoundError || _invalidBarcodeFormatError;
    if (hasAnyError) return true;
    if (widget.mode == 'take' && _sessionItems.isNotEmpty && !_isAddingMoreItems && !_isScanningPatient) return true;
    if (widget.mode == 'return' && _showReturnConfirmation) return true;
    return false;
  }

  Widget _buildMainContent() {
    bool hasAnyError = _itemInUseError || _itemFreeError || _itemBrokenError || _itemAlreadyInListError || _itemNotFoundError || _invalidBarcodeFormatError;
    bool showCamera = !(hasAnyError || 
                        (widget.mode == 'take' && _sessionItems.isNotEmpty && !_isAddingMoreItems && !_isScanningPatient) || 
                        (widget.mode == 'return' && _showReturnConfirmation));

    return Stack(
      children: [
        Offstage(
          offstage: !showCamera,
          child: MobileScanner(
            controller: controller,
            onDetect: _handleBarcode,
          ),
        ),

        if (!showCamera)
          Container(
            color: Colors.white,
            width: double.infinity,
            height: double.infinity,
            child: _buildOverlayScreens(),
          ),

        if (showCamera && _sessionItems.isNotEmpty)
           Positioned(
             bottom: 20,
             left: 0,
             right: 0,
             child: Center(
               child: ElevatedButton.icon(
                 style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                 icon: const Icon(Icons.list),
                 label: const Text('ביטול (חזור לרשימה)'),
                 onPressed: () {
                   setState(() {
                     _isAddingMoreItems = false;
                     _isScanningPatient = false;
                   });
                 },
               ),
             ),
           )
      ],
    );
  }

  Widget _buildOverlayScreens() {
    if (_itemInUseError) return _buildErrorScreenInUse();
    if (_itemFreeError) return _buildErrorScreenFree();
    if (_itemBrokenError) return _buildErrorScreenBroken();
    if (_itemAlreadyInListError) return _buildErrorScreenAlreadyInList();
    if (_itemNotFoundError) return _buildErrorScreenNotFound();
    if (_invalidBarcodeFormatError) return _buildErrorScreenInvalidFormat(); 
      
    if (widget.mode == 'take' && _sessionItems.isNotEmpty && !_isAddingMoreItems && !_isScanningPatient) {
      return _buildTakeListScreen();
    }

    if (widget.mode == 'return' && _showReturnConfirmation) {
      return _buildReturnConfirmationScreen();
    }
    
    return const SizedBox.shrink();
  }

  Widget _buildInstructionArea() {
    String text = '';
    if (widget.mode == 'take') {
      text = _isScanningPatient ? 'נא לסרוק מספר מטופל' : 'נא לסרוק ברקוד פריט';
    } else {
      text = 'נא לסרוק פריט להחזרה';
    }

    return Container(
      color: Colors.white,
      width: double.infinity,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            text,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF004D40)),
            textAlign: TextAlign.center,
          ),
          if (_isProcessing)
            const Padding(padding: EdgeInsets.only(top: 20), child: CircularProgressIndicator())
        ],
      ),
    );
  }

  Widget _buildTakeListScreen() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('items_groups').snapshots(),
      builder: (context, snapshot) {
        Map<String, String> groupNamesMap = {};
        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            groupNamesMap[doc.id] = (doc.data() as Map<String, dynamic>)['name']?.toString() ?? 'לא ידוע';
          }
        }

        return Container(
          color: Colors.white,
          padding: const EdgeInsets.all(20),
          width: double.infinity,
          child: Column(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 60),
              const SizedBox(height: 10),
              const Text(
                'פריטים ברשימה:',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: _sessionItems.length,
                  itemBuilder: (context, index) {
                    final data = _sessionItems[index].data() as Map<String, dynamic>;
                    String groupId = data['GroupID'] ?? '';
                    String groupName = data['group'] ?? groupNamesMap[groupId] ?? 'לא הוגדר';

                    return Card(
                      color: Colors.teal[50],
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: ListTile(
                          leading: const Icon(Icons.medical_services, color: Colors.teal, size: 36),
                          title: Text(groupName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.teal)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(data['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 16)),
                              const SizedBox(height: 2),
                              Text('ID: ${data['ID']}', style: const TextStyle(color: Colors.grey, fontSize: 14)),
                            ]
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, color: Colors.red, size: 28),
                            onPressed: () => _confirmRemoveItem(index),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('סרוק פריט נוסף', textAlign: TextAlign.center),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
                      onPressed: _scanNextItem,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.person),
                      label: const Text('סרוק מטופל\n(סיום)', textAlign: TextAlign.center),
                      onPressed: _goToPatientScan,
                    ),
                  ),
                ],
              )
            ],
          ),
        );
      }
    );
  }

  Widget _buildReturnConfirmationScreen() {
    final data = _returnCandidate!.data() as Map<String, dynamic>;
    String name = data['name'] ?? 'Unknown';
    String id = data['ID'] ?? 'Unknown';
    String groupId = data['GroupID'] ?? '';
      
    String encryptedPid = data['patientId'] ?? 'Unknown';
    String realPid = SecurityService.decryptID(encryptedPid);

    return StreamBuilder<DocumentSnapshot>(
      stream: groupId.isNotEmpty 
          ? FirebaseFirestore.instance.collection('items_groups').doc(groupId).snapshots()
          : null,
      builder: (context, snapshot) {
        String groupName = data['group'] ?? 'טוען...';
        if (data['group'] == null) {
          if (snapshot.hasData && snapshot.data!.exists) {
            groupName = (snapshot.data!.data() as Map<String, dynamic>)['name'] ?? 'קבוצה לא ידועה';
          } else if (groupId.isEmpty) {
            groupName = 'ללא קבוצה';
          }
        }

        return Container(
          color: Colors.white,
          padding: const EdgeInsets.all(20),
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 80),
              const SizedBox(height: 20),
              const Text('אישור החזרה', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
                
              Text(groupName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.teal), textAlign: TextAlign.center),
              const SizedBox(height: 5),
              Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              Text('ID: $id', style: const TextStyle(fontSize: 16, color: Colors.grey), textAlign: TextAlign.center),

              const SizedBox(height: 20),
              const Text('נמצא כרגע אצל מטופל:', style: TextStyle(fontSize: 18)),
              Text(realPid, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue)),
                
              const SizedBox(height: 30),
              const Text('האם להחזיר למלאי?', textAlign: TextAlign.center),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(onPressed: _isProcessing ? null : _resetScan, child: const Text('ביטול (לא)', style: TextStyle(fontSize: 18, color: Colors.grey))),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: _isProcessing ? null : _confirmReturn,
                    child: _isProcessing 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('כן, החזר', style: TextStyle(fontSize: 18)),
                  ),
                ],
              )
            ],
          ),
        );
      }
    );
  }

  // --- ERROR SCREENS ---

  Widget _buildErrorScreenInvalidFormat() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.qr_code_scanner, color: Colors.red, size: 80),
          const SizedBox(height: 20),
          const Text('ברקוד לא תקין', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red)),
          const SizedBox(height: 20),
          Text('נסרק: ${_lastScannedBarcode ?? ""}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text('הברקוד שנסרק אינו תואם לפורמט פריטי האינוונטר של בית החולים.', textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
          const SizedBox(height: 40),
          
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: _dismissError,
              child: const Text('אישור / סרוק שוב', style: TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorScreenAlreadyInList() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.info_outline, color: Colors.blue, size: 80),
          const SizedBox(height: 20),
          const Text('הפריט כבר ברשימה', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue)),
          const SizedBox(height: 20),
          Text('ברקוד: ${_lastScannedBarcode ?? ""}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text('פריט זה כבר נסרק ומופיע ברשימת האיסוף הנוכחית שלך.', textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
          const SizedBox(height: 40),
          
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: _dismissError,
              child: const Text('המשך לסרוק (חזור למצלמה)', style: TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.blue, width: 2)),
              onPressed: _backToList,
              child: const Text('חזור לרשימת הפריטים', style: TextStyle(fontSize: 18, color: Colors.blue)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorScreenNotFound() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off, color: Colors.orange, size: 80),
          const SizedBox(height: 20),
          const Text('פריט לא נמצא', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.orange)),
          const SizedBox(height: 20),
          Text('ברקוד: ${_lastScannedBarcode ?? ""}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text('הברקוד שנסרק לא קיים במערכת.\nאנא ודא שהסריקה תקינה ונסה שוב.', textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
          const SizedBox(height: 40),
          
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: _dismissError,
              child: const Text('אישור / סרוק שוב', style: TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorScreenInUse() {
    return _buildGenericError(
      title: 'הפריט בשימוש!',
      icon: Icons.error,
      content: Column(children: [
        if (_errorItemGroup != null)
          Text("קבוצה: $_errorItemGroup", style: TextStyle(color: Colors.grey[700], fontSize: 16)),
        Text(_errorItemName ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text('כבר משויך למטופל:', style: TextStyle(fontSize: 18)),
        Text(_errorPatientId ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red)),
      ]),
    );
  }

  Widget _buildErrorScreenFree() {
    return _buildGenericError(
      title: 'שגיאה: הפריט פנוי',
      icon: Icons.info,
      content: Column(children: [
        if (_errorItemGroup != null)
          Text("קבוצה: $_errorItemGroup", style: TextStyle(color: Colors.grey[700], fontSize: 16)),
        Text(_errorItemName ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text('ID: ${_errorItemId ?? ""}', style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 20),
        const Text('פריט זה כבר נמצא במלאי (סטטוס available).\nאין צורך להחזיר אותו.', textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
      ]),
    );
  }

  Widget _buildErrorScreenBroken() {
    return _buildGenericError(
      title: 'שגיאה: הפריט יצא משימוש',
      icon: Icons.build_circle_outlined,
      content: Column(children: [
        if (_errorItemGroup != null)
          Text("קבוצה: $_errorItemGroup", style: TextStyle(color: Colors.grey[700], fontSize: 16)),
        Text(_errorItemName ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text('ID: ${_errorItemId ?? ""}', style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 20),
        const Text('הפריט מסומן במערכת כ-תקול/נאבד/נמכר.\nנא לקחת פריט אחר.', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: Colors.red)),
      ]),
    );
  }

  Widget _buildGenericError({required String title, required IconData icon, required Widget content}) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.red, size: 80),
          const SizedBox(height: 20),
          Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red)),
          const SizedBox(height: 20),
          content,
          const SizedBox(height: 40),
            
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: _dismissError,
              child: const Text('אישור / סרוק אחר', style: TextStyle(fontSize: 18)),
            ),
          ),
            
          if (_sessionItems.isNotEmpty) ...[
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.grey, width: 2)),
                onPressed: _backToList,
                child: const Text('חזור לרשימה', style: TextStyle(color: Colors.grey, fontSize: 18)),
              ),
            ),
          ]
        ],
      ),
    );
  }
}

