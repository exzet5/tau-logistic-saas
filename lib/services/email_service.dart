import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service responsible for sending automated emails via EmailJS API.
class EmailService {
  // --- EMAILJS CONFIGURATION ---
  static const String _serviceId = 'service_sy28x2a';
  static const String _userId = 'cena3ADJA-VpQkwqw';
  
  // App links for welcome emails
  static const String _apkLink = 'https://drive.google.com/file/d/1qDLI0zx13iCYcIKTB_rDXXc6cDIG5b-t/view?usp=sharing';
  static const String _webLink = 'https://reot-logistic-warehouse.web.app/';

  /// Sends an email containing the verification code (OTP) to the user.
  static Future<void> sendVerificationCode({
    required String name,
    required String email,
    required String code,
    required String updateLink,
  }) async {
    const String templateId = 'template_je2ry6c'; // OTP Template
    final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'service_id': _serviceId,
        'template_id': templateId,
        'user_id': _userId,
        'template_params': {
          'to_name': name,
          'to_email': email,
          'message': code, 
          'app_link': updateLink,
        }
      }),
    );

    if (response.statusCode != 200) {
      throw 'EmailJS Error: ${response.body}';
    }
  }

  /// Sends a welcome email to a newly registered user containing platform links.
  /// If the user is an admin, a special web link is appended to the message.
  static Future<void> sendWelcomeEmail({
    required String name,
    required String email,
    required String role,
  }) async {
    const String templateId = 'template_f8npr5p'; // Welcome Template
    final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');

    String adminMsg = "";
    if (role == 'admin') {
      adminMsg = "\n\nקישור לממשק מנהלים (Admin):\n$_webLink";
    }

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'service_id': _serviceId,
        'template_id': templateId,
        'user_id': _userId,
        'template_params': {
          'to_name': name,
          'to_email': email,
          'android_link': _apkLink, 
          'ios_link': _webLink,     
          'admin_info': adminMsg   
        }
      }),
    );
      
    if (response.statusCode != 200) {
      throw 'EmailJS Error: ${response.body}';
    }
  }
}