import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart' hide Address;
import '../../utils/helpers.dart';
import '../../services/inventory_service.dart';
import '../../services/security_service.dart';

/// Handles the scanning process for taking and returning medical equipment.
/// Supports both camera scanning and manual barcode entry.
class ScannerScreen extends StatefulWidget {
  final String mode;

  const ScannerScreen({super.key, required this.mode});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  MobileScannerController controller = MobileScannerController();
  final TextEditingController _manualInputController = TextEditingController();
    
  bool _isProcessing = false;
  List<DocumentSnapshot> _sessionItems = [];
  bool _isAddingMoreItems = false;
  bool _isScanningPatient = false;
  DocumentSnapshot? _returnCandidate;
  bool _showReturnConfirmation = false;
  
  // Error flags
  bool _itemInUseError = false;
  bool _itemFreeError = false; 
  bool _itemBrokenError = false;
  bool _itemAlreadyInListError = false;
  bool _itemNotFoundError = false; 
  bool _invalidBarcodeFormatError = false; 
  
  // Data for error screens
  String? _errorItemName;
  String? _errorItemGroup; 
  String? _errorPatientId;
  String? _errorItemId;
  String? _lastScannedBarcode; 

  @override
  void dispose() {
    controller.dispose();
    _manualInputController.dispose();
    super.dispose();
  }

  /// Fetches the group name from the item data or from the 'items_groups' collection.
  Future<String> _getGroupName(Map<String, dynamic> data) async {
    if (data.containsKey('group') && data['group'] != null && data['group'].toString().isNotEmpty) {
      return data['group'].toString();
    }
    String gId = data['GroupID'] ?? '';
    if (gId.isEmpty) return 'לא הוגדר';
    try {
      var doc = await FirebaseFirestore.instance.collection('items_groups').doc(gId).get();
      if (doc.exists) return (doc.data() as Map<String, dynamic>)['name'] ?? 'לא הוגדר';
    } catch (_) {}
    return 'לא הוגדר';
  }



  /// Fully resets the scanning state and all active error flags.
  void _resetScan() {
    setState(() {
      _sessionItems.clear();
      _isAddingMoreItems = false;
      _isScanningPatient = false;
      _returnCandidate = null;
      _showReturnConfirmation = false;
      
      _itemInUseError = false;
      _itemFreeError = false;
      _itemBrokenError = false;
      _itemAlreadyInListError = false;
      _itemNotFoundError = false;
      _invalidBarcodeFormatError = false;
      
      _errorItemName = null;
      _errorItemGroup = null; 
      _errorPatientId = null;
      _errorItemId = null;
      _lastScannedBarcode = null;
      _isProcessing = false;
    });
  }

  /// Clears only error flags to allow continuing the current session.
  void _dismissError() {
    setState(() {
      _itemInUseError = false;
      _itemFreeError = false;
      _itemBrokenError = false;
      _itemAlreadyInListError = false;
      _itemNotFoundError = false;
      _invalidBarcodeFormatError = false;
      
      _errorItemName = null;
      _errorItemGroup = null;
      _errorPatientId = null;
      _errorItemId = null;
      _lastScannedBarcode = null;
      _isProcessing = false;
    });
  }

  /// Returns to the list of currently scanned items without clearing them.
  void _backToList() {
    setState(() {
      _itemInUseError = false;
      _itemFreeError = false;
      _itemBrokenError = false;
      _itemAlreadyInListError = false;
      _itemNotFoundError = false;
      _invalidBarcodeFormatError = false;
      
      _lastScannedBarcode = null;
      _errorItemGroup = null;
      _isProcessing = false;
      _isAddingMoreItems = false; 
    });
  }

  /// Activates the camera to scan the next item in the session.
  void _scanNextItem() {
    setState(() {
      _isAddingMoreItems = true;
      _isProcessing = false;
    });
  }

  /// Switches the scanner context to expect a patient ID instead of an item barcode.
  void _goToPatientScan() {
    setState(() {
      _isScanningPatient = true;
      _isAddingMoreItems = false;
      _isProcessing = false;
    });
  }

  /// Displays a confirmation dialog to remove a specific item from the pending list.
  void _confirmRemoveItem(int index) {
    final item = _sessionItems[index];
    final data = item.data() as Map<String, dynamic>;
    String name = data['name'] ?? 'Unknown';

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת פריט'),
          content: Text('האם להסיר את "$name" מהרשימה?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('לא'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _sessionItems.removeAt(index);
                  if (_sessionItems.isEmpty) {
                    _isAddingMoreItems = false;
                    _isProcessing = false;
                  }
                });
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('כן, מחק'),
            ),
          ],
        ),
      ),
    );
  }

  /// Shows the final confirmation dialog before assigning scanned items to the patient.
  Future<void> _showFinalAssignmentDialog(String patientId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('items_groups').snapshots(),
          builder: (context, snapshot) {
            Map<String, String> groupNamesMap = {};
            if (snapshot.hasData) {
              for (var doc in snapshot.data!.docs) {
                groupNamesMap[doc.id] = (doc.data() as Map<String, dynamic>)['name']?.toString() ?? 'לא ידוע';
              }
            }

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text('אישור שיוך למטופל'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       Text('המטופל (ID): $patientId', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
                       const SizedBox(height: 10),
                       const Text('הפריטים לשיוך:'),
                       const Divider(),
                       ..._sessionItems.map((doc) {
                          final d = doc.data() as Map<String, dynamic>;
                          String groupId = d['GroupID'] ?? '';
                          String groupName = d['group'] ?? groupNamesMap[groupId] ?? 'לא הוגדר';
                          
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (groupName.isNotEmpty) 
                                  Text("קבוצה: $groupName", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 15)),
                                Text(d['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text('ID: ${d['ID']}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                              ],
                            ),
                          );
                       }).toList(),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                       Navigator.pop(ctx); 
                       setState(() { _isProcessing = false; });
                    },
                    child: const Text('ביטול'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _executeAssignment(patientId, groupNamesMap);
                    },
                    child: const Text('אישור (החל)'),
                  ),
                ],
              ),
            );
          }
        );
      },
    );
  }

  /// Processes the assignment, updates item status in Firestore, writes history, 
  /// and calculates required deposits (Pikadon).
  Future<void> _executeAssignment(String patientId, Map<String, String> groupNamesMap) async {
    try {
      String encryptedPatientId = SecurityService.encryptID(patientId);
      final user = FirebaseAuth.instance.currentUser;
        
      WriteBatch batch = FirebaseFirestore.instance.batch();

      for (var doc in _sessionItems) {
        batch.update(doc.reference, {
          'status': 'in_use',
          'patientId': encryptedPatientId,
          'lastTaken': FieldValue.serverTimestamp(),
        });

        final itemData = doc.data() as Map<String, dynamic>;
        String groupName = itemData['group'] ?? groupNamesMap[itemData['GroupID']] ?? 'לא הוגדר';

        final historyRef = FirebaseFirestore.instance.collection('History').doc();
        batch.set(historyRef, {
          'itemId': itemData['ID'],
          'itemName': itemData['name'],
          'group': groupName, 
          'action': 'take',
          'patientId': encryptedPatientId,
          'timestamp': FieldValue.serverTimestamp(),
          'staffUid': user?.uid,
        });
      }

      await batch.commit();

      for (var doc in _sessionItems) {
        final itemData = doc.data() as Map<String, dynamic>;
        double itemCost = double.tryParse(itemData['cost']?.toString() ?? '0') ?? 0.0;
        String groupName = itemData['group'] ?? groupNamesMap[itemData['GroupID']] ?? 'לא הוגדר';

        if (itemCost > 0) {
          await PikadonLogic.addToPendingPikadon(
            encryptedPatientId, 
            itemData['ID'].toString(), 
            itemData['name'] ?? 'Unknown', 
            groupName, 
            itemCost,
            user?.uid 
          );
        }
      }

      _showSnack('הפעולה בוצעה בהצלחה!');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showSnack('שגיאה בשמירה: $e');
      setState(() { _isProcessing = false; });
    }
  }

  /// Looks up an item in Firestore using its barcode.
  Future<DocumentSnapshot?> _findItemSnapshot(String barcode) async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('items')
          .where('ID', isEqualTo: barcode)
          .limit(1)
          .get();
      if (querySnapshot.docs.isNotEmpty) return querySnapshot.docs.first;
    } catch (e) { 
      debugPrint("Error: $e"); 
    }
    return null;
  }

  /// Main handler for camera detections. Triggers the appropriate flow based on the screen mode.
  void _handleBarcode(BarcodeCapture capture) async {
    if (_isProcessing) return;

    bool hasAnyError = _itemInUseError || _itemFreeError || _itemBrokenError || _itemAlreadyInListError || _itemNotFoundError || _invalidBarcodeFormatError;
    bool isCameraHidden = hasAnyError || 
                          (widget.mode == 'take' && _sessionItems.isNotEmpty && !_isAddingMoreItems && !_isScanningPatient) || 
                          (widget.mode == 'return' && _showReturnConfirmation);
                          
    if (isCameraHidden) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String barcode = barcodes.first.rawValue ?? "Unknown";
      setState(() { _isProcessing = true; });

      if (widget.mode == 'take') {
        await _handleTakeFlow(barcode);
      } else {
        await _handleReturnFlow(barcode);
      }
    }
  }

  /// Validates and handles barcodes scanned during the 'take' equipment flow.
  Future<void> _handleTakeFlow(String barcode) async {
    if (_isScanningPatient) {
      if (barcode.trim().isEmpty) {
        _showSnack('שגיאה: ברקוד ריק');
        await Future.delayed(const Duration(seconds: 2));
        setState(() { _isProcessing = false; });
        return;
      }
      await _showFinalAssignmentDialog(barcode);
      return;
    }

    if (!AppHelpers.isValidItemBarcode(barcode)) {
      setState(() {
        _invalidBarcodeFormatError = true;
        _lastScannedBarcode = barcode;
        _isProcessing = false;
      });
      return;
    }

    bool alreadyInList = _sessionItems.any((doc) => doc['ID'] == barcode);
    if (alreadyInList) {
      setState(() {
        _itemAlreadyInListError = true;
        _lastScannedBarcode = barcode;
        _isProcessing = false;
      });
      return;
    }

    DocumentSnapshot? doc = await _findItemSnapshot(barcode);
    
    if (doc == null) {
      setState(() {
         _itemNotFoundError = true;
         _lastScannedBarcode = barcode;
         _isProcessing = false;
      });
      return;
    }

    final data = doc.data() as Map<String, dynamic>;
    String status = data['status'] ?? 'available';

    if (status == 'broken' || status == 'lost' || status == 'sold' || status == 'other') {
      String groupName = await _getGroupName(data);
      setState(() {
        _itemBrokenError = true;
        _errorItemName = data['name'];
        _errorItemGroup = groupName;
        _errorItemId = data['ID'];
        _isProcessing = false;
      });
      return;
    }

    if (status == 'in_use') {
      String encryptedPid = data['patientId'] ?? '';
      String realPid = SecurityService.decryptID(encryptedPid);
      String groupName = await _getGroupName(data);

      setState(() {
        _itemInUseError = true;
        _errorItemName = data['name'];
        _errorItemGroup = groupName;
        _errorPatientId = realPid;
        _isProcessing = false;
      });
      return;
    }

    setState(() {
      _sessionItems.add(doc);
      _itemInUseError = false;
      _itemBrokenError = false;
      _itemAlreadyInListError = false;
      _itemNotFoundError = false;
      _invalidBarcodeFormatError = false;
      _isAddingMoreItems = false;
      _isProcessing = false;
    });
  }

  /// Validates and handles barcodes scanned during the 'return' equipment flow.
  Future<void> _handleReturnFlow(String barcode) async {
    if (!AppHelpers.isValidItemBarcode(barcode)) {
      setState(() {
        _invalidBarcodeFormatError = true;
        _lastScannedBarcode = barcode;
        _isProcessing = false;
      });
      return;
    }

    DocumentSnapshot? doc = await _findItemSnapshot(barcode);

    if (doc == null) {
      setState(() {
         _itemNotFoundError = true;
         _lastScannedBarcode = barcode;
         _isProcessing = false;
      });
      return;
    }

    final data = doc.data() as Map<String, dynamic>;
    String status = data['status'] ?? 'available';

    if (status == 'available') {
      String groupName = await _getGroupName(data);
      setState(() {
         _itemFreeError = true;
         _errorItemName = data['name'];
         _errorItemGroup = groupName;
         _errorItemId = data['ID'];
         _isProcessing = false;
      });
      return;
    }

    setState(() {
      _returnCandidate = doc;
      _showReturnConfirmation = true;
      _isProcessing = false;
    });
  }

  /// Submits the return operation, updates Firestore status to available, and writes to History.
  Future<void> _confirmReturn() async {
    if (_returnCandidate == null || _isProcessing) return;

    setState(() { _isProcessing = true; });

    final data = _returnCandidate!.data() as Map<String, dynamic>;
    String encryptedPid = data['patientId'] ?? 'Unknown';
    String iId = data['ID'] ?? 'Unknown';
    String itemName = data['name'] ?? 'Unknown';
    String groupName = await _getGroupName(data);

    try {
      final user = FirebaseAuth.instance.currentUser;
      WriteBatch batch = FirebaseFirestore.instance.batch();
        
      batch.update(_returnCandidate!.reference, {
        'status': 'available',
        'patientId': null,
      });

      final historyRef = FirebaseFirestore.instance.collection('History').doc();
      batch.set(historyRef, {
        'itemId': iId,
        'itemName': itemName,
        'group': groupName, 
        'action': 'return',
        'patientId': encryptedPid,
        'timestamp': FieldValue.serverTimestamp(),
        'staffUid': user?.uid,
      });

      await batch.commit();

      _showSnack('הפריט הוחזר בהצלחה!');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showSnack('שגיאה: $e');
      setState(() { _isProcessing = false; });
    }
  }

  /// Opens a dialog to manually enter a barcode or patient ID.
  void _showManualEntryDialog() {
    _manualInputController.clear();
    
    String dialogTitle = _isScanningPatient ? 'הכנס מספר מטופל' : 'הכנס קוד פריט';
    String hintText = _isScanningPatient ? 'מספר מטופל (לדוגמה: 123456789)' : 'סרוק קוד (לדוגמה: 88000013)';

    showDialog(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(dialogTitle),
            content: TextField(
              controller: _manualInputController,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(hintText: hintText),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ביטול'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  String code = _manualInputController.text.trim();
                  if (code.isNotEmpty) {
                    setState(() { _isProcessing = true; });
                    if (widget.mode == 'take') {
                       _handleTakeFlow(code);
                    } else {
                       _handleReturnFlow(code);
                    }
                  }
                },
                child: const Text('אישור'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Displays a brief notification snackbar.
  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    String title = widget.mode == 'take' ? 'קח ציוד' : 'החזר ציוד';
    
    Color headerColor = const Color(0xFF004D40); 
    if (_itemInUseError || _itemFreeError || _itemBrokenError || _invalidBarcodeFormatError) {
      headerColor = Colors.red[900]!;
    } else if (_itemAlreadyInListError) {
      headerColor = Colors.blue[800]!; 
    } else if (_itemNotFoundError) {
      headerColor = Colors.orange[800]!; 
    }

    String fabLabel = _isScanningPatient ? 'הכנס מספר מטופל' : 'הכנס קוד ידנית';

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(color: Colors.white)),
        backgroundColor: headerColor,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _resetScan)],
      ),
      floatingActionButton: _shouldShowManualButton() 
        ? FloatingActionButton.extended(
            backgroundColor: const Color(0xFF00796B),
            onPressed: _showManualEntryDialog,
            icon: const Icon(Icons.keyboard, color: Colors.white),
            label: Text(fabLabel, style: const TextStyle(color: Colors.white)),
          )
        : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: Column(
        children: [
          Expanded(flex: 5, child: _buildMainContent()),
          if (!_shouldHideBottomText())
            Expanded(flex: 2, child: _buildInstructionArea()),
        ],
      ),
    );
  }

  /// Determines if the manual entry Floating Action Button should be visible.
  bool _shouldShowManualButton() {
    bool hasAnyError = _itemInUseError || _itemFreeError || _itemBrokenError || _itemAlreadyInListError || _itemNotFoundError || _invalidBarcodeFormatError;
    if (hasAnyError) return false;
    if (_showReturnConfirmation) return false;
    
    if (widget.mode == 'take' && _sessionItems.isNotEmpty && !_isAddingMoreItems && !_isScanningPatient) {
      return false;
    }
    
    return true;
  }

  /// Determines if the bottom instruction text area should be hidden.
  bool _shouldHideBottomText() {
    bool hasAnyError = _itemInUseError || _itemFreeError || _itemBrokenError || _itemAlreadyInListError || _itemNotFoundError || _invalidBarcodeFormatError;
    if (hasAnyError) return true;
    if (widget.mode == 'take' && _sessionItems.isNotEmpty && !_isAddingMoreItems && !_isScanningPatient) return true;
    if (widget.mode == 'return' && _showReturnConfirmation) return true;
    return false;
  }

  /// Builds the main content area, toggling between the camera view and overlay screens.
  Widget _buildMainContent() {
    bool hasAnyError = _itemInUseError || _itemFreeError || _itemBrokenError || _itemAlreadyInListError || _itemNotFoundError || _invalidBarcodeFormatError;
    bool showCamera = !(hasAnyError || 
                        (widget.mode == 'take' && _sessionItems.isNotEmpty && !_isAddingMoreItems && !_isScanningPatient) || 
                        (widget.mode == 'return' && _showReturnConfirmation));

    return Stack(
      children: [
        Offstage(
          offstage: !showCamera,
          child: MobileScanner(
            controller: controller,
            onDetect: _handleBarcode,
          ),
        ),

        if (!showCamera)
          Container(
            color: Colors.white,
            width: double.infinity,
            height: double.infinity,
            child: _buildOverlayScreens(),
          ),

        if (showCamera && _sessionItems.isNotEmpty)
           Positioned(
             bottom: 20,
             left: 0,
             right: 0,
             child: Center(
               child: ElevatedButton.icon(
                 style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                 icon: const Icon(Icons.list),
                 label: const Text('ביטול (חזור לרשימה)'),
                 onPressed: () {
                   setState(() {
                     _isAddingMoreItems = false;
                     _isScanningPatient = false;
                   });
                 },
               ),
             ),
           )
      ],
    );
  }

  /// Renders the appropriate overlay screen based on the current state or error.
  Widget _buildOverlayScreens() {
    if (_itemInUseError) return _buildErrorScreenInUse();
    if (_itemFreeError) return _buildErrorScreenFree();
    if (_itemBrokenError) return _buildErrorScreenBroken();
    if (_itemAlreadyInListError) return _buildErrorScreenAlreadyInList();
    if (_itemNotFoundError) return _buildErrorScreenNotFound();
    if (_invalidBarcodeFormatError) return _buildErrorScreenInvalidFormat(); 
      
    if (widget.mode == 'take' && _sessionItems.isNotEmpty && !_isAddingMoreItems && !_isScanningPatient) {
      return _buildTakeListScreen();
    }

    if (widget.mode == 'return' && _showReturnConfirmation) {
      return _buildReturnConfirmationScreen();
    }
    
    return const SizedBox.shrink();
  }

  /// Builds the instruction text area at the bottom of the scanner.
  Widget _buildInstructionArea() {
    String text = '';
    if (widget.mode == 'take') {
      text = _isScanningPatient ? 'נא לסרוק מספר מטופל' : 'נא לסרוק ברקוד פריט';
    } else {
      text = 'נא לסרוק פריט להחזרה';
    }

    return Container(
      color: Colors.white,
      width: double.infinity,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            text,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF004D40)),
            textAlign: TextAlign.center,
          ),
          if (_isProcessing)
            const Padding(padding: EdgeInsets.only(top: 20), child: CircularProgressIndicator())
        ],
      ),
    );
  }

  /// Displays the list of items currently staged for the 'take' operation.
  Widget _buildTakeListScreen() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('items_groups').snapshots(),
      builder: (context, snapshot) {
        Map<String, String> groupNamesMap = {};
        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            groupNamesMap[doc.id] = (doc.data() as Map<String, dynamic>)['name']?.toString() ?? 'לא ידוע';
          }
        }

        return Container(
          color: Colors.white,
          padding: const EdgeInsets.all(20),
          width: double.infinity,
          child: Column(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 60),
              const SizedBox(height: 10),
              const Text(
                'פריטים ברשימה:',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: _sessionItems.length,
                  itemBuilder: (context, index) {
                    final data = _sessionItems[index].data() as Map<String, dynamic>;
                    String groupId = data['GroupID'] ?? '';
                    String groupName = data['group'] ?? groupNamesMap[groupId] ?? 'לא הוגדר';

                    return Card(
                      color: Colors.teal[50],
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: ListTile(
                          leading: const Icon(Icons.medical_services, color: Colors.teal, size: 36),
                          title: Text(groupName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.teal)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(data['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 16)),
                              const SizedBox(height: 2),
                              Text('ID: ${data['ID']}', style: const TextStyle(color: Colors.grey, fontSize: 14)),
                            ]
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, color: Colors.red, size: 28),
                            onPressed: () => _confirmRemoveItem(index),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('סרוק פריט נוסף', textAlign: TextAlign.center),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
                      onPressed: _scanNextItem,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.person),
                      label: const Text('סרוק מטופל\n(סיום)', textAlign: TextAlign.center),
                      onPressed: _goToPatientScan,
                    ),
                  ),
                ],
              )
            ],
          ),
        );
      }
    );
  }

  /// Displays the confirmation screen when attempting to return an item.
  Widget _buildReturnConfirmationScreen() {
    final data = _returnCandidate!.data() as Map<String, dynamic>;
    String name = data['name'] ?? 'Unknown';
    String id = data['ID'] ?? 'Unknown';
    String groupId = data['GroupID'] ?? '';
      
    String encryptedPid = data['patientId'] ?? 'Unknown';
    String realPid = SecurityService.decryptID(encryptedPid);

    return StreamBuilder<DocumentSnapshot>(
      stream: groupId.isNotEmpty 
          ? FirebaseFirestore.instance.collection('items_groups').doc(groupId).snapshots()
          : null,
      builder: (context, snapshot) {
        String groupName = data['group'] ?? 'טוען...';
        if (data['group'] == null) {
          if (snapshot.hasData && snapshot.data!.exists) {
            groupName = (snapshot.data!.data() as Map<String, dynamic>)['name'] ?? 'קבוצה לא ידועה';
          } else if (groupId.isEmpty) {
            groupName = 'ללא קבוצה';
          }
        }

        return Container(
          color: Colors.white,
          padding: const EdgeInsets.all(20),
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 80),
              const SizedBox(height: 20),
              const Text('אישור החזרה', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
                
              Text(groupName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.teal), textAlign: TextAlign.center),
              const SizedBox(height: 5),
              Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              Text('ID: $id', style: const TextStyle(fontSize: 16, color: Colors.grey), textAlign: TextAlign.center),

              const SizedBox(height: 20),
              const Text('נמצא כרגע אצל מטופל:', style: TextStyle(fontSize: 18)),
              Text(realPid, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue)),
                
              const SizedBox(height: 30),
              const Text('האם להחזיר למלאי?', textAlign: TextAlign.center),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(onPressed: _isProcessing ? null : _resetScan, child: const Text('ביטול (לא)', style: TextStyle(fontSize: 18, color: Colors.grey))),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: _isProcessing ? null : _confirmReturn,
                    child: _isProcessing 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('כן, החזר', style: TextStyle(fontSize: 18)),
                  ),
                ],
              )
            ],
          ),
        );
      }
    );
  }

  // --- ERROR SCREENS ---

  /// Builds the error screen shown when a scanned barcode does not match hospital standards.
  Widget _buildErrorScreenInvalidFormat() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.qr_code_scanner, color: Colors.red, size: 80),
          const SizedBox(height: 20),
          const Text('ברקוד לא תקין', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red)),
          const SizedBox(height: 20),
          Text('נסרק: ${_lastScannedBarcode ?? ""}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text('הברקוד שנסרק אינו תואם לפורמט פריטי האינוונטר של בית החולים.', textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
          const SizedBox(height: 40),
          
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: _dismissError,
              child: const Text('אישור / סרוק שוב', style: TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the error screen shown when the user scans an item already present in their staging list.
  Widget _buildErrorScreenAlreadyInList() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.info_outline, color: Colors.blue, size: 80),
          const SizedBox(height: 20),
          const Text('הפריט כבר ברשימה', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue)),
          const SizedBox(height: 20),
          Text('ברקוד: ${_lastScannedBarcode ?? ""}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text('פריט זה כבר נסרק ומופיע ברשימת האיסוף הנוכחית שלך.', textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
          const SizedBox(height: 40),
          
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: _dismissError,
              child: const Text('המשך לסרוק (חזור למצלמה)', style: TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.blue, width: 2)),
              onPressed: _backToList,
              child: const Text('חזור לרשימת הפריטים', style: TextStyle(fontSize: 18, color: Colors.blue)),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the error screen shown when a scanned barcode is not found in the database.
  Widget _buildErrorScreenNotFound() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off, color: Colors.orange, size: 80),
          const SizedBox(height: 20),
          const Text('פריט לא נמצא', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.orange)),
          const SizedBox(height: 20),
          Text('ברקוד: ${_lastScannedBarcode ?? ""}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text('הברקוד שנסרק לא קיים במערכת.\nאנא ודא שהסריקה תקינה ונסה שוב.', textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
          const SizedBox(height: 40),
          
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: _dismissError,
              child: const Text('אישור / סרוק שוב', style: TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the error screen shown when attempting to take an item that is already assigned to a patient.
  Widget _buildErrorScreenInUse() {
    return _buildGenericError(
      title: 'הפריט בשימוש!',
      icon: Icons.error,
      content: Column(children: [
        if (_errorItemGroup != null)
          Text("קבוצה: $_errorItemGroup", style: TextStyle(color: Colors.grey[700], fontSize: 16)),
        Text(_errorItemName ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text('כבר משויך למטופל:', style: TextStyle(fontSize: 18)),
        Text(_errorPatientId ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red)),
      ]),
    );
  }

  /// Builds the error screen shown when attempting to return an item that is already available.
  Widget _buildErrorScreenFree() {
    return _buildGenericError(
      title: 'שגיאה: הפריט פנוי',
      icon: Icons.info,
      content: Column(children: [
        if (_errorItemGroup != null)
          Text("קבוצה: $_errorItemGroup", style: TextStyle(color: Colors.grey[700], fontSize: 16)),
        Text(_errorItemName ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text('ID: ${_errorItemId ?? ""}', style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 20),
        const Text('פריט זה כבר נמצא במלאי (סטטוס available).\nאין צורך להחזיר אותו.', textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
      ]),
    );
  }

  /// Builds the error screen shown when an item is marked as broken, lost, or sold.
  Widget _buildErrorScreenBroken() {
    return _buildGenericError(
      title: 'שגיאה: הפריט יצא משימוש',
      icon: Icons.build_circle_outlined,
      content: Column(children: [
        if (_errorItemGroup != null)
          Text("קבוצה: $_errorItemGroup", style: TextStyle(color: Colors.grey[700], fontSize: 16)),
        Text(_errorItemName ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text('ID: ${_errorItemId ?? ""}', style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 20),
        const Text('הפריט מסומן במערכת כ-תקול/נאבד/נמכר.\nנא לקחת פריט אחר.', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: Colors.red)),
      ]),
    );
  }

  /// A helper widget to consistently format generic error screens.
  Widget _buildGenericError({required String title, required IconData icon, required Widget content}) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.red, size: 80),
          const SizedBox(height: 20),
          Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red)),
          const SizedBox(height: 20),
          content,
          const SizedBox(height: 40),
            
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: _dismissError,
              child: const Text('אישור / סרוק אחר', style: TextStyle(fontSize: 18)),
            ),
          ),
            
          if (_sessionItems.isNotEmpty) ...[
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.grey, width: 2)),
                onPressed: _backToList,
                child: const Text('חזור לרשימה', style: TextStyle(color: Colors.grey, fontSize: 18)),
              ),
            ),
          ]
        ],
      ),
    );
  }
}