import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'app.dart';
import 'services/update_service.dart';

/// The main entry point of the Reuth Hospital Logistics Application.
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
    UpdateService.syncAppVersion();
  });

  runApp(const MyApp());
}