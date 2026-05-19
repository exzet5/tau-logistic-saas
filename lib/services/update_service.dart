import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/app_constants.dart';

/// Service responsible for checking and enforcing application updates.
class UpdateService {
  
  /// Automatically updates Firestore with the latest version info from this code.
  /// This only succeeds if the current user has write permissions (Authorized staff).
  static Future<void> syncAppVersion() async {
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
      // NEW: Get user's company_id first
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!userDoc.exists || userDoc.data()?['company_id'] == null) {
         debugPrint("Version sync failed: User has no company assigned.");
         return;
      }
      String companyId = userDoc.data()!['company_id'];

      // NEW: Point to the specific company's settings
      final docRef = FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .collection('system')
          .doc('settings');
          
      final snapshot = await docRef.get();

      if (snapshot.exists) {
        int firestoreVersion = snapshot.data()?['required_version'] ?? 0;

        // Update ONLY if code version is higher
        if (AppConstants.currentAppVersion > firestoreVersion) {
          await docRef.update({
            'required_version': AppConstants.currentAppVersion,
            'download_url': AppConstants.latestUpdateUrl,
            'updated_at': FieldValue.serverTimestamp(),
          });
          debugPrint("SUCCESS: Firestore updated to version ${AppConstants.currentAppVersion}");
        } else {
          debugPrint("Version in DB is already up to date ($firestoreVersion)");
        }
      } else {
        await docRef.set({
          'required_version': AppConstants.currentAppVersion,
          'download_url': AppConstants.latestUpdateUrl,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)); // Use merge in case other settings exist
      }
    } catch (e) {
      debugPrint("Firestore Error during sync: $e");
    }
  }
}

/// A widget wrapper that checks for required app updates on startup.
/// If an update is required, it locks the screen and forces a download.
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

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // NEW: Get user's company_id first
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!userDoc.exists || userDoc.data()?['company_id'] == null) return;
      String companyId = userDoc.data()!['company_id'];

      // NEW: Point to the specific company's settings
      final doc = await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .collection('system')
          .doc('settings')
          .get();
      
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        int requiredVersion = data['required_version'] ?? 1;
        String downloadUrl = data['download_url'] ?? '';

        // If the installed version is older than required, show mandatory dialog
        if (AppConstants.currentAppVersion < requiredVersion) {
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