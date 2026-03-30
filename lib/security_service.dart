import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:cloud_firestore/cloud_firestore.dart';

class PikadonLogic {
  static Future<void> addToPendingPikadon(
      String patientId, 
      String itemId, 
      String itemName, 
      String group, // <--- НОВЫЙ АРГУМЕНТ!
      double cost, 
      String? staffUid) async {
      
    var existingDocs = await FirebaseFirestore.instance.collection('Pikadon')
        .where('patientId', isEqualTo: patientId)
        .where('status', isEqualTo: 'pending')
        .get();

    WriteBatch batch = FirebaseFirestore.instance.batch();

    if (existingDocs.docs.isNotEmpty) {
      var doc = existingDocs.docs.first;
      var data = doc.data();
      List items = List.from(data['items'] ?? []);
      
      bool exists = items.any((i) => i['itemId'] == itemId);
      if (!exists) {
        items.add({
          'itemId': itemId,
          'itemName': itemName,
          'group': group, // <--- СОХРАНЯЕМ ГРУППУ
          'cost': cost
        });
        double currentTotal = (data['totalCost'] ?? 0).toDouble();
        
        batch.update(doc.reference, {
          'items': items,
          'totalCost': currentTotal + cost,
        });
      }
    } else {
      batch.set(FirebaseFirestore.instance.collection('Pikadon').doc(), {
        'patientId': patientId,
        'status': 'pending',
        'totalCost': cost,
        'createdAt': FieldValue.serverTimestamp(),
        'staffUid': staffUid,
        'items': [
          {
            'itemId': itemId,
            'itemName': itemName,
            'group': group, // <--- СОХРАНЯЕМ ГРУППУ
            'cost': cost
          }
        ]
      });
    }

    await batch.commit();
  }
}

class SecurityService {
  static final _key = encrypt.Key.fromUtf8('MySecretKeyForHospitalApp1234567'); 
  static final _iv = encrypt.IV.fromUtf8('1234567890123456'); 
  static final _encrypter = encrypt.Encrypter(encrypt.AES(_key));

  static String encryptID(String plainText) {
    if (plainText.isEmpty) return "";
    try {
      return _encrypter.encrypt(plainText, iv: _iv).base64;
    } catch (e) {
      return plainText; 
    }
  }

  // ВЕРНУЛ ЗАЩИТУ TRY-CATCH, ИЗ-ЗА КОТОРОЙ ПАДАЛА ИСТОРИЯ!
  static String decryptID(String encryptedText) {
    if (encryptedText.isEmpty) return "";
    try {
      return _encrypter.decrypt(encrypt.Encrypted.fromBase64(encryptedText), iv: _iv);
    } catch (e) {
      return encryptedText; // Если не получилось расшифровать, возвращаем как есть
    }
  }
}