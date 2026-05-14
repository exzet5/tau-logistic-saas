import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../utils/helpers.dart';
import 'scanner_screen.dart';

/// Displays the main interface for standard users (doctors/nurses) 
/// providing options to take or return medical equipment.
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