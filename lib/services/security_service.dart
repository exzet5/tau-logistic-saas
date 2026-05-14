import 'package:encrypt/encrypt.dart' as encrypt;

/// Provides cryptographic functions for securing sensitive user and patient data.
class SecurityService {
  static final _key = encrypt.Key.fromUtf8('MySecretKeyForHospitalApp1234567'); 
  static final _iv = encrypt.IV.fromUtf8('1234567890123456'); 
  static final _encrypter = encrypt.Encrypter(encrypt.AES(_key));

  /// Encrypts a plain text string using AES.
  /// Returns the original string if encryption fails or input is empty.
  static String encryptID(String plainText) {
    if (plainText.isEmpty) return "";
    try {
      return _encrypter.encrypt(plainText, iv: _iv).base64;
    } catch (e) {
      return plainText; 
    }
  }

  /// Decrypts an AES encrypted base64 string back to plain text.
  /// Fallbacks to returning the encrypted string if decryption fails 
  /// (e.g., dealing with legacy unencrypted data).
  static String decryptID(String encryptedText) {
    if (encryptedText.isEmpty) return "";
    try {
      return _encrypter.decrypt(encrypt.Encrypted.fromBase64(encryptedText), iv: _iv);
    } catch (e) {
      return encryptedText; 
    }
  }
}