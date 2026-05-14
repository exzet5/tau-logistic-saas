import 'package:flutter/material.dart';

/// A collection of global utility functions used across the application.
class AppHelpers {
  
  /// Validates email format using Regex.
  static bool isValidEmail(String email) {
    return RegExp(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$").hasMatch(email);
  }

  /// Validates the barcode structure and its checksum.
  /// Standard hospital inventory barcode starts with '88', is 8 digits long.
  static bool isValidItemBarcode(String barcode) {
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

  /// Generates a valid 8-digit barcode consisting of a base string ('88' + sequence) and a calculated check digit.
  static String generateBarcodeWithChecksum(int sequence) {
    String base = "88${sequence.toString().padLeft(5, '0')}"; 
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
    int checkDigit = (10 - (sum % 10)) % 10;
    return "$base$checkDigit";
  }

  /// Returns the appropriate background color based on item status.
  static Color getStatusColor(String status) {
    if (status == 'available') return Colors.green.shade100;
    if (status == 'sold') return Colors.purple.shade100;
    if (status == 'broken' || status == 'lost' || status == 'other') return Colors.red.shade100;
    return Colors.blue.shade100;
  }

  /// Returns human-readable Hebrew text for a given status code.
  static String getStatusText(String status) {
    if (status == 'available') return 'פנוי';
    if (status == 'sold') return 'במחסן מכירה';
    if (status == 'lost') return 'נאבד';
    if (status == 'broken') return 'תקול';
    if (status == 'other') return 'יצא משימוש';
    return 'בשימוש';
  }

  /// Returns the Hebrew label for the selected payment method.
  static String getPaymentMethodText(String method) {
    if (method == 'cash') return 'מזומן';
    if (method == 'check') return "צ'ק";
    return 'אשראי';
  }

  /// Returns the corresponding icon for the selected payment method.
  static IconData getPaymentMethodIcon(String method) {
    if (method == 'cash') return Icons.money;
    if (method == 'check') return Icons.receipt;
    return Icons.credit_card;
  }
}