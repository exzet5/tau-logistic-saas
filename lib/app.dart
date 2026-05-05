import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main.dart';
import 'app_screens.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reuth Logistic',
      debugShowCheckedModeBanner: false,
      
      // --- LOCALIZATION ---
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('he', 'IL'), // Hebrew
        Locale('en', 'US'),
      ],

      theme: ThemeData(
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFFE0F2F1),
        fontFamily: 'Roboto',
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00796B),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
        ),
      ),
      builder: (context, child) {
        return Directionality(textDirection: TextDirection.rtl, child: child!);
      },
      
      // === WRAPPING THE INITIAL SCREEN HERE ===
      home: UpdateCheckerWrapper(
        child: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            // Wait for the auth state to load
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            // If the user exists in the stream, go to the home screen
            if (snapshot.hasData) {
              return const HomeScreen();
            }

            // Additional check if the stream is active but data hasn't loaded yet (prevents accidental logouts)
            if (snapshot.connectionState == ConnectionState.active && !snapshot.hasData) {
              final currentUser = FirebaseAuth.instance.currentUser;
              if (currentUser != null) {
                return const HomeScreen();
              }
            }

            return const LoginScreen();
          },
        ),
      ),
    );
  }
}