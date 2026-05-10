import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options.dart';
import 'app.dart';

// ==========================================
// IMPORTANT: Update these two every time 
// you release a new version for Reuth!
// ==========================================
const int CURRENT_APP_VERSION = 2; 
const String LATEST_UPDATE_URL = "https://drive.google.com/file/d/1n6HBPIIDPEQRtm6EaiD1YW0KUDR4XGUE/view?usp=drive_link";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase with platform-specific options
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Set persistence to LOCAL so the user stays logged in after restart
  try {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  } catch (e) {
    debugPrint("Error setting auth persistence: $e");
  }

  // Attempt to sync the version info to Firestore 
  // We wait a bit to ensure Auth is ready to provide credentials if logged in
  Future.delayed(const Duration(milliseconds: 500), () {
    syncAppVersion();
  });

  runApp(const MyApp());
}

/// Automatically updates Firestore with the latest version info from this code.
/// This only succeeds if the current user has write permissions (Authorized staff).
Future<void> syncAppVersion() async {
  // Wait until Firebase Auth actually loads the user session
  // We check for up to 5 seconds
  for (int i = 0; i < 10; i++) {
    if (FirebaseAuth.instance.currentUser != null) break;
    await Future.delayed(const Duration(milliseconds: 500));
  }

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    debugPrint("Version sync failed: No authorized user found.");
    return;
  }

  try {
    final docRef = FirebaseFirestore.instance.collection('app_config').doc('version_info');
    final snapshot = await docRef.get();

    if (snapshot.exists) {
      int firestoreVersion = snapshot.data()?['required_version'] ?? 0;

      // Update ONLY if code version is higher
      if (CURRENT_APP_VERSION > firestoreVersion) {
        await docRef.update({
          'required_version': CURRENT_APP_VERSION,
          'download_url': LATEST_UPDATE_URL,
          'updated_at': FieldValue.serverTimestamp(),
        });
        debugPrint("SUCCESS: Firestore updated to version $CURRENT_APP_VERSION");
      } else {
        debugPrint("Version in DB is already up to date ($firestoreVersion)");
      }
    } else {
      await docRef.set({
        'required_version': CURRENT_APP_VERSION,
        'download_url': LATEST_UPDATE_URL,
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
  } catch (e) {
    debugPrint("Firestore Error during sync: $e");
  }
}

// ==========================================
// WIDGET WRAPPER FOR UPDATE CHECKING
// ==========================================
class UpdateCheckerWrapper extends StatefulWidget {
  final Widget child;
  const UpdateCheckerWrapper({super.key, required this.child});

  @override
  State<UpdateCheckerWrapper> createState() => _UpdateCheckerWrapperState();
}

class _UpdateCheckerWrapperState extends State<UpdateCheckerWrapper> {
  @override
  void initState() {
    super.initState();
    // Run the check right after the first frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }

  Future<void> _checkForUpdates() async {
    // Skip version check on Web
    if (kIsWeb) return; 

    try {
      final doc = await FirebaseFirestore.instance.collection('app_config').doc('version_info').get();
      
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        int requiredVersion = data['required_version'] ?? 1;
        String downloadUrl = data['download_url'] ?? '';

        // If the installed version is older than required, show mandatory dialog
        if (CURRENT_APP_VERSION < requiredVersion) {
          if (!mounted) return;
          
          showDialog(
            context: context,
            barrierDismissible: false, // User must update to proceed
            builder: (BuildContext context) {
              return PopScope(
                canPop: false, // Disable system back button
                child: Directionality(
                  textDirection: TextDirection.rtl, // Hebrew support
                  child: AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: const Row(
                      children: [
                        Icon(Icons.system_update, color: Color(0xFF00796B), size: 30),
                        SizedBox(width: 10),
                        Text('עדכון גרסה חובה', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    content: const Text(
                      'יצאה גרסה חדשה ומשופרת של האפליקציה.\nכדי להמשיך להשתמש במערכת, אנא הורד והתקן את העדכון כעת.',
                      style: TextStyle(fontSize: 16),
                    ),
                    actions: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00796B),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        onPressed: () async {
                          final Uri url = Uri.parse(downloadUrl);
                          if (await canLaunchUrl(url)) {
                            // Opens external browser to ensure APK downloads correctly
                            await launchUrl(url, mode: LaunchMode.externalApplication);
                          }
                        },
                        child: const Text('הורד עדכון', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }
      }
    } catch (e) {
      debugPrint("Update check error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}