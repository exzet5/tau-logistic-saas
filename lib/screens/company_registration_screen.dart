import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/email_service.dart';

/// Screen for onboarding a new company into the TAU Logistic platform.
class CompanyRegistrationScreen extends StatefulWidget {
  const CompanyRegistrationScreen({super.key});

  @override
  State<CompanyRegistrationScreen> createState() => _CompanyRegistrationScreenState();
}

class _CompanyRegistrationScreenState extends State<CompanyRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _companyNameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  /// Handles the complex registration process across multiple Firestore collections.
  Future<void> _registerCompany() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final String companyName = _companyNameController.text.trim();
      final String firstName = _firstNameController.text.trim();
      final String lastName = _lastNameController.text.trim();
      final String email = _emailController.text.trim().toLowerCase();

      // 1. Check if user already exists
      var existing = await FirebaseFirestore.instance
          .collection('allowed_users')
          .where('email', isEqualTo: email)
          .get();

      if (existing.docs.isNotEmpty) {
        throw 'משתמש עם אימייל זה כבר רשום במערכת.';
      }

      final batch = FirebaseFirestore.instance.batch();

      // 2. Create Company Document
      final companyRef = FirebaseFirestore.instance.collection('companies').doc();
      final String companyId = companyRef.id;

      batch.set(companyRef, {
        'name': companyName,
        'createdAt': FieldValue.serverTimestamp(),
        'isActive': true,
        'subscriptionType': 'trial',
      });

      // 3. Initialize essential sub-collections structure (empty placeholders)
      // Note: Subcollections aren't physically created until a doc is added.
      // We add a 'settings' doc to create the 'system' path.
      batch.set(companyRef.collection('system').doc('settings'), {
        'companyName': companyName,
        'setupCompleted': true,
        'setupDate': FieldValue.serverTimestamp(),
      });

      // 4. Create Entry in 'allowed_users' (For Login Screen Verification)
      final allowedRef = FirebaseFirestore.instance.collection('allowed_users').doc();
      batch.set(allowedRef, {
        'email': email,
        'name': firstName,
        'surname': lastName,
        'role': 'admin',
        'company_id': companyId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 5. Create Entry in 'users' (User Profile)
      // Since we don't have a UID yet (OTP logic), we'll use email as a temporary doc ID
      // or let it be created upon first real login. To be safe, we rely on allowed_users.

      await batch.commit();

      // 6. Send Welcome Email via Google Apps Script
      await EmailService.sendWelcomeEmail(
        name: '$firstName $lastName',
        email: email,
        role: 'admin',
      );

      if (mounted) {
        _showSuccessDialog();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('נרשמת בהצלחה!'),
          content: const Text(
            'החברה והמנהל הוגדרו במערכת.\nכעת ניתן לחזור למסך הראשי ולהיכנס באמצעות הקוד שישלח לאימייל שלך.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx); // Close dialog
                Navigator.pop(context); // Back to Login
              },
              child: const Text('חזור למסך כניסה'),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required String description,
    required TextEditingController controller,
    required IconData icon,
    TextInputType type = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4.0, bottom: 4.0),
          child: Text(description, style: const TextStyle(fontSize: 14, color: Colors.blueGrey)),
        ),
        TextFormField(
          controller: controller,
          keyboardType: type,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, color: const Color(0xFF004D40)),
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
          validator: (v) => (v == null || v.isEmpty) ? 'שדה חובה' : null,
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7F7),
        appBar: AppBar(
          title: const Text('רישום חברה חדשה'),
          backgroundColor: const Color(0xFF004D40),
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 650),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // --- Инфо-блок (Explanation Frame) ---
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.teal.shade200, width: 1.5),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
                        ],
                      ),
                      child: Column(
                        children: const [
                          Text(
                            'ברוכים הבאים ל-TAU Logistic',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF004D40)),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'אפליקציה זו מאפשרת ליצור קשר חכם בין פריטי המלאי ללקוחות לצורך מעקב ובקרה על כל התהליכים באמצעות סריקת ברקודים.\n\n'
                            'לאחר ההרשמה, ייפתח עבורך ממשק מנהל (Admin) המאפשר להוסיף ולנהל משתמשים נוספים בחברה שלך, וכן לעקוב אחר כל הפעילויות בזמן אמת.\n\n'
                            'בסיום הרישום, יישלח אליך אימייל הכולל קישור להורדת האפליקציה והוראות התקנה.',
                            style: TextStyle(fontSize: 15, height: 1.5),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),

                    // --- Поля ввода ---
                    _buildInputField(
                      description: 'הזן את שם החברה או הארגון שלך',
                      label: 'שם החברה',
                      controller: _companyNameController,
                      icon: Icons.business,
                    ),
                    _buildInputField(
                      description: 'מה השם הפרטי שלך?',
                      label: 'שם פרטי',
                      controller: _firstNameController,
                      icon: Icons.person,
                    ),
                    _buildInputField(
                      description: 'מה שם המשפחה שלך?',
                      label: 'שם משפחה',
                      controller: _lastNameController,
                      icon: Icons.person_outline,
                    ),
                    _buildInputField(
                      description: 'כתובת האימייל שתשמש אותך לכניסה למערכת',
                      label: 'אימייל מנהל',
                      controller: _emailController,
                      icon: Icons.email,
                      type: TextInputType.emailAddress,
                    ),

                    const SizedBox(height: 20),

                    // --- Кнопка регистрации ---
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00796B),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isLoading ? null : _registerCompany,
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text(
                                'סיים רישום וצור חברה',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                      ),
                    ),
                    const SizedBox(height: 50), // Bottom padding
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}