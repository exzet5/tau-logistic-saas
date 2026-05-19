import 'package:cloud_firestore/cloud_firestore.dart';

/// Handles inventory-related business logic, specifically the deposit (Pikadon) system.
class PikadonLogic {
  
  /// Adds a scanned item to a patient's pending deposit list for a specific company.
  /// If a pending session already exists for the patient, the item is appended.
  /// Otherwise, a new pending deposit record is created.
  static Future<void> addToPendingPikadon(
      // NEW: Added companyId
      String companyId, 
      String patientId, 
      String itemId, 
      String itemName, 
      String group, 
      double cost, 
      String? staffUid) async {
      
    // NEW: Pointing to the specific company's subcollection
    CollectionReference pikadonCollection = FirebaseFirestore.instance
        .collection('companies')
        .doc(companyId)
        .collection('Pikadon');

    var existingDocs = await pikadonCollection
        .where('patientId', isEqualTo: patientId)
        .where('status', isEqualTo: 'pending')
        .get();

    WriteBatch batch = FirebaseFirestore.instance.batch();

    if (existingDocs.docs.isNotEmpty) {
      var doc = existingDocs.docs.first;
      var data = doc.data() as Map<String, dynamic>; // Added cast for safety
      List items = List.from(data['items'] ?? []);
      
      bool exists = items.any((i) => i['itemId'] == itemId);
      if (!exists) {
        items.add({
          'itemId': itemId,
          'itemName': itemName,
          'group': group, 
          'cost': cost
        });
        double currentTotal = (data['totalCost'] ?? 0).toDouble();
        
        batch.update(doc.reference, {
          'items': items,
          'totalCost': currentTotal + cost,
        });
      }
    } else {
      batch.set(pikadonCollection.doc(), {
        'patientId': patientId,
        'status': 'pending',
        'totalCost': cost,
        'createdAt': FieldValue.serverTimestamp(),
        'staffUid': staffUid,
        'items': [
          {
            'itemId': itemId,
            'itemName': itemName,
            'group': group, 
            'cost': cost
          }
        ]
      });
    }

    await batch.commit();
  }
}