import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service responsible for sending automated emails via Google Apps Script Web App API.
/// Replaces the legacy EmailJS implementation to bypass CORS issues on Flutter Web 
/// and to support higher daily email volumes natively via Gmail.
class EmailService {
  // --- GOOGLE APPS SCRIPT CONFIGURATION ---
  // The endpoint URL of the deployed Google Apps Script Web App.
  static const String _scriptUrl = 'https://script.google.com/macros/s/AKfycbzls4Kmo73P0KkD2GYwWDqu_Y-UciOPFDt5TZwEbSBVs_n4URc9K-XtsfSZqiOOoH1B/exec';
  
  // App links for welcome emails
  static const String _apkLink = 'https://drive.google.com/file/d/1qDLI0zx13iCYcIKTB_rDXXc6cDIG5b-t/view?usp=sharing';
  static const String _webLink = 'https://tau-logistic-app.web.app/';

  /// Sends an HTML email containing the verification code (OTP) to the user.
  static Future<void> sendVerificationCode({
    required String name,
    required String email,
    required String code,
    required String updateLink,
  }) async {
    final url = Uri.parse(_scriptUrl);

    // Build stylish HTML layout for OTP Verification with TAU Logistic branding
    final String htmlContent = '''
      <div dir="rtl" style="font-family: Arial, sans-serif; color: #333; line-height: 1.6; max-width: 600px; margin: 0 auto; border: 1px solid #e0e0e0; border-radius: 10px; overflow: hidden; text-align: right;">
        <div style="background-color: #004D40; color: white; padding: 20px; text-align: center;">
          <h2 style="margin: 0;">קוד אימות למערכת</h2>
        </div>
        <div style="padding: 30px; background-color: #f9fdfc;">
          <p style="font-size: 16px;">שלום <b>$name</b>,</p>
          <p style="font-size: 16px;">להלן קוד האימות שלך לכניסה למערכת <strong>TAU Logistic</strong>:</p>
          <div style="text-align: center; margin: 30px 0;">
            <span style="font-size: 36px; font-weight: bold; letter-spacing: 8px; color: #00796B; background-color: #e0f2f1; padding: 15px 30px; border-radius: 8px; border: 2px dashed #004D40; display: inline-block;">
              $code
            </span>
          </div>
          <p style="font-size: 14px; color: #666; text-align: center;">הקוד בתוקף לזמן מוגבל. אין להעביר את הקוד לאדם אחר.</p>
          <div style="text-align: center; margin-top: 30px; border-top: 1px solid #eee; padding-top: 20px;">
            <p style="font-size: 14px;">אם האפליקציה אינה מעודכנת, באפשרותך להוריד את הגרסה האחרונה מכאן:</p>
            <a href="$updateLink" style="background-color: #004D40; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px; display: inline-block; font-weight: bold;">הורד עדכון</a>
          </div>
        </div>
        <div style="background-color: #f1f1f1; padding: 15px; text-align: center; font-size: 12px; color: #777;">
          <p style="margin: 0;">הודעה זו נשלחה אוטומטית ממערכת TAU Logistic.</p>
        </div>
      </div>
    ''';

    // Use text/plain to avoid pre-flight OPTIONS requests (CORS fix for Flutter Web)
    final response = await http.post(
      url,
      headers: {'Content-Type': 'text/plain'},
      body: json.encode({
        'to_email': email,
        'to_name': name,
        'subject': 'קוד אימות כניסה למערכת TAU Logistic',
        'html_body': htmlContent,
      }),
    );

    if (response.statusCode != 200) {
      throw 'Server connection failed: ${response.statusCode}';
    }

    final result = json.decode(response.body);
    if (result['status'] == 'error') {
      throw 'Google Script Error: ${result['message']}';
    }
  }

  /// Sends an HTML welcome email to a newly registered user containing platform links and detailed installation steps.
  static Future<void> sendWelcomeEmail({
    required String name,
    required String email,
    required String role,
  }) async {
    final url = Uri.parse(_scriptUrl);

    // Build robust, stylish HTML structure for the SaaS welcome email
    final String htmlContent = '''
      <div dir="rtl" style="font-family: Arial, sans-serif; color: #333; line-height: 1.6; max-width: 600px; margin: 0 auto; border: 1px solid #e0e0e0; border-radius: 10px; overflow: hidden; text-align: right;">
        <div style="background-color: #004D40; color: white; padding: 20px; text-align: center;">
          <h2 style="margin: 0;">ברוכים הבאים למערכת TAU Logistic</h2>
        </div>
        <div style="padding: 30px; background-color: #f9fdfc;">
          <p style="font-size: 16px;">שלום <b>$name</b>,</p>
          <p style="font-size: 16px;">אנו שמחים לבשר שהוגדרת בהצלחה במערכת ניהול המלאי שלנו. כעת תוכל לנהל ולעקוב אחר פריטים ולקוחות ביעילות באמצעות טכנולוגיית ברקוד.</p>
          
          <div style="background-color: #e0f2f1; padding: 15px; border-radius: 8px; margin: 20px 0; border-right: 4px solid #004D40;">
            <p style="margin-top: 0; font-weight: bold; color: #004D40;">פרטי הגישה שלך:</p>
            <ul style="margin-bottom: 0; padding-right: 20px;">
              <li><b>אימייל מורשה:</b> $email</li>
              <li><b>רמת הרשאה:</b> $role</li>
            </ul>
          </div>

          <h3 style="color: #00796B; margin-top: 30px; border-bottom: 1px solid #ddd; padding-bottom: 5px;">איך מתחילים?</h3>
          <p>כדי שיהיה לך נוח להשתמש במערכת לסריקת ברקודים וניהול שוטף, בחר את הדרך המתאימה לך:</p>
          
          <div style="margin: 20px 0; padding: 15px; background-color: white; border: 1px solid #eee; border-radius: 8px;">
            <b style="color: #333; font-size: 15px;">🍏 למשתמשי iPhone (iOS) - התקנה מהירה:</b><br/>
            1. פתח את הדפדפן Safari.<br/>
            2. היכנס לכתובת המערכת (<a href="$_webLink">לחץ כאן</a>).<br/>
            3. לחץ על כפתור <b>'שיתוף'</b> (ריבוע עם חץ) בתחתית המסך.<br/>
            4. בחר <b>'הוסף למסך הבית'</b> (Add to Home Screen).
          </div>

          <div style="margin: 20px 0; padding: 15px; background-color: white; border: 1px solid #eee; border-radius: 8px;">
            <b style="color: #333; font-size: 15px;">🤖 למשתמשי Android - התקנת אפליקציה:</b><br/>
            <div style="margin-top: 10px; line-height: 1.8;">
              1. <a href="$_apkLink" style="color: #00796B; font-weight: bold; text-decoration: underline;">לחץ כאן להורדת קובץ ההתקנה (APK)</a>.<br/>
              2. לאחר סיום ההורדה, פתח את הקובץ שהורד.<br/>
              3. <b>אישור מקורות:</b> אם מופיעה הודעת אבטחה שחוסמת את ההתקנה, לחץ על 'הגדרות' (Settings) ואשר 'התקנה ממקור זה' (Allow from this source).<br/>
              4. <b>Play Protect:</b> אם קופצת אזהרת אבטחה של גוגל, לחץ על 'פרטים נוספים' (More details) ואז בחר ב-'התקן בכל זאת' (Install anyway).
            </div>
          </div>
          
          <div style="margin: 20px 0; padding: 15px; background-color: white; border: 1px solid #eee; border-radius: 8px;">
            <b style="color: #333; font-size: 15px;">💻 כניסה מהמחשב (למנהלים):</b><br/>
            להפקת דוחות והוספת משתמשים, מומלץ להיכנס לממשק דרך הדפדפן במחשב: <br/>
            <a href="$_webLink" style="color: #00796B; font-weight: bold;">$_webLink</a>
          </div>

          <div style="text-align: center; margin-top: 35px;">
            <a href="$_webLink" style="background-color: #00796B; color: white; padding: 14px 30px; text-decoration: none; border-radius: 5px; font-weight: bold; display: inline-block; font-size: 16px;">היכנס למערכת עכשיו</a>
          </div>
        </div>
        <div style="background-color: #f1f1f1; padding: 15px; text-align: center; font-size: 12px; color: #777;">
          <p style="margin: 0;">צוות TAU Logistic מאחל לך עבודה פורייה ויעילה!</p>
          <p style="margin: 5px 0 0 0;">מכתב זה נשלח באופן אוטומטי, נא לא להשיב להודעה זו.</p>
        </div>
      </div>
    ''';

    // Send request using text/plain to bypass browser CORS policies
    final response = await http.post(
      url,
      headers: {'Content-Type': 'text/plain'},
      body: json.encode({
        'to_email': email,
        'to_name': name,
        'subject': 'ברוכים הבאים למערכת TAU Logistic',
        'html_body': htmlContent,
      }),
    );

    if (response.statusCode != 200) {
      throw 'Server connection failed: ${response.statusCode}';
    }

    final result = json.decode(response.body);
    if (result['status'] == 'error') {
      throw 'Google Script Error: ${result['message']}';
    }
  }
}