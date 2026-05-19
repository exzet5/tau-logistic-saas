import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/helpers.dart';
import '../utils/app_constants.dart';
import '../services/email_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // To check if it's running on web
import 'company_registration_screen.dart'; // Your new screen

/// Handles user authentication, OTP generation, and Firestore role verification.
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
  
  String? _fetchedCompanyId; 

  /// Verifies if the email exists in the 'allowed_users' collection and sends an OTP.
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
      
      // NEW: Fetch company_id from allowed_users
      _fetchedCompanyId = data['company_id']; 

      if (_fetchedName == null || _fetchedCompanyId == null) {
        _showSnack('שגיאה: חסר שם או שיוך לחברה בהגדרות המערכת');
        setState(() { _isLoading = false; });
        return;
      }

      var rng = Random();
      _generatedCode = (rng.nextInt(900000) + 100000).toString();

      await EmailService.sendVerificationCode(
        name: _fetchedName!,
        email: email,
        code: _generatedCode!,
        updateLink: AppConstants.latestUpdateUrl, 
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

  /// Verifies the entered OTP and logs the user into Firebase Auth.
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
          throw e; // ignore: use_rethrow_when_possible
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
          'company_id': _fetchedCompanyId, 
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

  /// Displays a snackbar with the provided message.
  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
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
                  ],

                  // --- NEW: SaaS Company Registration Link (Web ONLY) ---
                  if (kIsWeb) ...[
                    const SizedBox(height: 30), 
                    SizedBox(
                      width: double.infinity, // Makes the tap area as wide as the input fields
                      child: TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const CompanyRegistrationScreen()),
                          );
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16), // Matches the height of other fields
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text(
                          'רישום חברה חדשה (למנהלי מערכת)',
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 16, // Larger, more harmonious font size
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.underline,
                            decorationColor: Colors.blue,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}