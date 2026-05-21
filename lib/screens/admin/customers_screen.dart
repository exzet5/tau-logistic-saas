import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/security_service.dart';
import '../../services/inventory_service.dart';
import '../../utils/helpers.dart';
/// Screen for managing patient data. Allows searching for a patient by ID,
/// viewing the items they currently hold, adding new items, and returning them.
class PatientsManagementScreen extends StatefulWidget {
  // NEW: Add companyId parameter
  final String companyId; 

  const PatientsManagementScreen({super.key, required this.companyId}); // UPDATED

  @override
  State<PatientsManagementScreen> createState() => _PatientsManagementScreenState();
}

class _PatientsManagementScreenState extends State<PatientsManagementScreen> {
  final TextEditingController _tzController = TextEditingController();
  final TextEditingController _addItemController = TextEditingController();

  String? _currentPatientTZRaw;
  String? _currentPatientTZEncoded;
  
  bool _isSearching = false;
  bool _hasSearched = false;
  List<Map<String, dynamic>> _patientItems = [];
  double _totalCost = 0.0; 
  
  // Cache to map GroupID to human-readable names
  Map<String, String> _groupNamesCache = {};

  // NEW: Helper getter for the current company document reference
  DocumentReference get _companyRef => FirebaseFirestore.instance.collection('companies').doc(widget.companyId);

  @override
  void initState() {
    super.initState();
    _loadGroupNames();
  }

  @override
  void dispose() {
    _tzController.dispose();
    _addItemController.dispose();
    super.dispose();
  }

  /// Loads group names from Firestore into a local cache to avoid 
  /// querying the DB for every single list item.
  Future<void> _loadGroupNames() async {
    try {
      // NEW: Use _companyRef
      var snap = await _companyRef.collection('items_groups').get();
      for (var doc in snap.docs) {
        _groupNamesCache[doc.id] = (doc.data())['name'] ?? 'לא ידוע';
      }
    } catch (e) {
      debugPrint("Error loading group names: $e");
    }
  }

  /// Calculates the total number of days an item has been held by the patient.
  int _calculateDaysHeld(Timestamp? takenDate) {
    if (takenDate == null) return 0;
    final taken = takenDate.toDate();
    final now = DateTime.now();
    return now.difference(taken).inDays;
  }

  /// Helper to get the UID of the currently logged-in user (staff member).
  String? _getCurrentUserId() {
    return FirebaseAuth.instance.currentUser?.uid;
  }

  /// Searches for a patient using their raw ID, encrypts it, and fetches 
  /// all items currently assigned to them from Firestore.
  Future<void> _searchPatient() async {
    final rawTZ = _tzController.text.trim();
    
    if (rawTZ.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("שגיאה: מספר לקוח לא יכול להיות ריק"), 
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final encodedTZ = SecurityService.encryptID(rawTZ);

    setState(() {
      _isSearching = true;
      _currentPatientTZRaw = rawTZ;
      _currentPatientTZEncoded = encodedTZ;
      _hasSearched = true;
      _patientItems = [];
      _totalCost = 0.0;
    });

    try {
      // NEW: Use _companyRef
      final snapshot = await _companyRef
          .collection('items')
          .where('patientId', isEqualTo: encodedTZ)
          .where('status', isEqualTo: 'in_use')
          .get();

      final List<Map<String, dynamic>> loadedItems = [];
      double tempTotal = 0.0;

      for (var doc in snapshot.docs) {
        var data = doc.data();
        data['docId'] = doc.id;
        loadedItems.add(data);
        
        if (data['cost'] != null) {
          tempTotal += (data['cost'] as num).toDouble();
        }
      }

      setState(() {
        _patientItems = loadedItems;
        _totalCost = tempTotal;
        _isSearching = false;
      });
    } catch (e) {
      setState(() => _isSearching = false);
      debugPrint("Search Error: $e");
    }
  }

  /// Processes the return of an item, updating its status to 'available' 
  /// and logging the action in the History collection.
  Future<void> _returnItem(String docId, String itemName, String itemId, String itemGroup) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('שחרור פריט'),
          content: Text('האם אתה בטוח שברצונך לשחרר את הפריט "$itemName" (קבוצה: $itemGroup)?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('שחרר פריט'),
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    try {
      final uid = _getCurrentUserId();
      WriteBatch batch = FirebaseFirestore.instance.batch();
        
      // NEW: Use _companyRef
      DocumentReference itemRef = _companyRef.collection('items').doc(docId);
      batch.update(itemRef, {
        'status': 'available',
        'patientId': null,
      });

      // NEW: Use _companyRef
      DocumentReference historyRef = _companyRef.collection('History').doc();
      batch.set(historyRef, {
        'action': 'return',
        'itemId': itemId,
        'itemName': itemName,
        'group': itemGroup,
        'patientId': _currentPatientTZEncoded,
        'timestamp': FieldValue.serverTimestamp(),
        'staffUid': uid, 
      });

      await batch.commit();

      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("הפריט שוחרר בהצלחה"), backgroundColor: Colors.green));
      }
      _searchPatient();
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    }
  }

  /// Manually assigns a new item to the currently searched patient based on the provided barcode.
  Future<void> _addItemToPatient() async {
    final itemId = _addItemController.text.trim();
    if (itemId.isEmpty) return;
    Navigator.pop(context);

    try {
      // NEW: Use _companyRef
      final snapshot = await _companyRef
          .collection('items')
          .where('ID', isEqualTo: itemId)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("פריט לא נמצא במערכת"), backgroundColor: Colors.red));
        return;
      }

      var itemDoc = snapshot.docs.first;
      var itemData = itemDoc.data() as Map<String, dynamic>;
      
      // Extract group using fallback to cache
      String itemGroup = itemData['group'] ?? _groupNamesCache[itemData['GroupID']] ?? 'לא הוגדר';

      if (itemData['status'] == 'broken') {
          bool? fix = await showDialog<bool>(
            context: context,
            builder: (ctx) => Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text('פריט תקול'),
                content: Text('הפריט (קבוצה: $itemGroup) מסומן במערכת כ-Broken (תקול).\nהאם תרצה לסמן אותו כתקין ולשייך ללקוח?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('הפריט תקין (שייך ללקוח)'),
                  ),
                ],
              ),
            ),
          );
          
          if (fix != true) return;
      } 
      else if (itemData['status'] == 'in_use' || itemData['status'] == 'taken') {
          String holderEncoded = itemData['patientId'] ?? '';
          String holderDecoded = SecurityService.decryptID(holderEncoded);
          
          if(mounted) {
            showDialog(
              context: context,
              builder: (ctx) => Directionality(
                textDirection: TextDirection.rtl,
                child: AlertDialog(
                  title: const Text('הפריט תפוס!'),
                  content: SelectableText('פריט זה כבר נמצא אצל לקוח אחר.\n\nמספר לקוח המחזיק:\n$holderDecoded'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('אישור')),
                  ],
                ),
              ),
            );
          }
          return;
      }

      final uid = _getCurrentUserId();
      WriteBatch batch = FirebaseFirestore.instance.batch();
        
      batch.update(itemDoc.reference, {
        'status': 'in_use',
        'patientId': _currentPatientTZEncoded,
        'lastTaken': FieldValue.serverTimestamp(),
      });

      // NEW: Use _companyRef
      DocumentReference historyRef = _companyRef.collection('History').doc();
      batch.set(historyRef, {
        'action': 'take',
        'itemId': itemId,
        'itemName': itemData['name'] ?? 'Unknown',
        'group': itemGroup,
        'patientId': _currentPatientTZEncoded,
        'timestamp': FieldValue.serverTimestamp(),
        'staffUid': uid,
      });

      await batch.commit();

      double itemCost = double.tryParse(itemData['cost']?.toString() ?? '0') ?? 0.0;
      if (itemCost > 0) {
        await PikadonLogic.addToPendingPikadon(
          widget.companyId, // NEW: Pass the companyId here
          _currentPatientTZEncoded!, 
          itemId, 
          itemData['name'] ?? 'Unknown', 
          itemGroup,
          itemCost,
          FirebaseAuth.instance.currentUser?.uid 
        );
      }

      _addItemController.clear();
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("הפריט נוסף לקוח בהצלחה"), backgroundColor: Colors.green));
      _searchPatient();

    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  /// Displays the dialog for manually adding an item to the patient via Barcode ID.
  void _showAddItemDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('הוספת פריט לקוח'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('נא להזין את הברקוד (ID) של הפריט:'),
              const SizedBox(height: 10),
              TextField(
                controller: _addItemController,
                decoration: const InputDecoration(
                  labelText: 'מזהה פריט (Item ID)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ביטול')),
            ElevatedButton(
              onPressed: _addItemToPatient,
              child: const Text('הוסף פריט'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 5)],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tzController,
                      keyboardType: TextInputType.text, 
                      decoration: const InputDecoration(
                        labelText: 'הכנס מספר לקוח', 
                        prefixIcon: Icon(Icons.person_search),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _searchPatient(),
                    ),
                  ),
                  const SizedBox(width: 15),
                  ElevatedButton.icon(
                    onPressed: _searchPatient,
                    icon: _isSearching 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                        : const Icon(Icons.search),
                    label: const Text('חפש לקוח'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                      backgroundColor: const Color(0xFF004D40),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),

            Expanded(
              child: !_hasSearched 
                  ? Center(child: Text("נא לחפש לקוח כדי לראות ציוד", style: TextStyle(color: Colors.grey[500], fontSize: 18)))
                  : _patientItems.isEmpty
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 60, color: Colors.grey),
                          const SizedBox(height: 10),
                          Text(
                            "אין ציוד משויך לקוח זה (${_currentPatientTZRaw ?? ''})",
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: _showAddItemDialog,
                            icon: const Icon(Icons.add),
                            label: const Text('הוסף פריט לקוח זה'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                          )
                        ],
                      )
                    : Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                            decoration: BoxDecoration(
                              color: Colors.teal[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.teal.shade100)
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SelectableText("לקוח: ${_currentPatientTZRaw}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 5),
                                    SelectableText(
                                      "שווי ציוד כולל: ₪${_totalCost.toStringAsFixed(2)}", 
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal[800])
                                    ),
                                  ],
                                ),
                                ElevatedButton.icon(
                                  onPressed: _showAddItemDialog,
                                  icon: const Icon(Icons.add),
                                  label: const Text('הוסף פריט'),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                )
                              ],
                            ),
                          ),
                          const SizedBox(height: 15),
                          
                          Expanded(
                            child: ListView.builder(
                              itemCount: _patientItems.length,
                              itemBuilder: (context, index) {
                                final item = _patientItems[index];
                                
                                Timestamp? takenTs = item['lastTaken']; 
                                if (takenTs == null && item['lastUpdated'] != null) {
                                   takenTs = item['lastUpdated'];
                                }

                                final daysHeld = _calculateDaysHeld(takenTs);
                                final cost = item['cost'] != null ? "₪${item['cost']}" : "-"; 
                                
                                // Group extraction with cache fallback
                                String groupName = item['group'] ?? _groupNamesCache[item['GroupID']] ?? 'לא הוגדר';

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  elevation: 3,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.teal[100],
                                      child: const Icon(Icons.medical_services, color: Colors.teal),
                                    ),
                                    title: SelectableText("${item['name'] ?? 'שם לא ידוע'} [$groupName]", style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SelectableText("קבוצה: $groupName", style: const TextStyle(color: Colors.blueGrey)),
                                        SelectableText("ID: ${item['ID']}"), 
                                        SelectableText("עלות: $cost"), 
                                        SelectableText("נלקח בתאריך: ${takenTs != null ? takenTs.toDate().toString().substring(0, 10) : '---'}"),
                                        SelectableText("נמצא אצל לקוח: $daysHeld ימים", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    trailing: ElevatedButton.icon(
                                      onPressed: () => _returnItem(item['docId'], item['name'] ?? '', item['ID'] ?? '', groupName),
                                      icon: const Icon(Icons.undo, size: 16),
                                      label: const Text("שחרר"),
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
            ),
          ],
        ),
      ),
    );
  }
}