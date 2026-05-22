import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../utils/helpers.dart';
import '../../services/security_service.dart';
import '../../services/pdf_service.dart';

/// Screen for managing inventory items, including listing, creating new items,
/// managing item groups/SKUs, and generating printable PDF barcodes.
class ItemsManagementScreen extends StatefulWidget {
  // NEW: Add companyId parameter
  final String companyId; 

  const ItemsManagementScreen({super.key, required this.companyId}); // UPDATED

  @override
  State<ItemsManagementScreen> createState() => _ItemsManagementScreenState();
}

class _ItemsManagementScreenState extends State<ItemsManagementScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // --- CONTROLLERS ---
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _manualQuantityController = TextEditingController(text: "1");
  final TextEditingController _costController = TextEditingController();

  // --- FILTERS ---
  int _filterResetKey = 0;
  String _searchQuery = "";
  Map<String, dynamic>? _filterGroup;
  Map<String, dynamic>? _filterSku;
  String _sortOption = 'default';

  // --- PAGINATION ---
  int _currentPage = 0;
  final int _itemsPerPage = 6; 

  // --- ADDING ---
  int _formResetKey = 0;
  Map<String, dynamic>? _selectedGroupForAdd;
  Map<String, dynamic>? _selectedSkuForAdd;
  int _bulkQuantity = 1;
  bool _submittedAndInvalid = false;
  
  // --- SUCCESS SCREEN ---
  bool _showSuccessScreen = false;
  List<String> _generatedBarcodes = [];
  String _lastAddedItemName = "";

  // --- BARCODE PRINTING MODE ---
  bool _isBarcodeMode = false;
  Map<String, Map<String, String>> _selectedBarcodes = {};
  double barcodeLabelWidthMm = 40;
  double barcodeLabelHeightMm = 30;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadBarcodePrintSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _manualQuantityController.dispose();
    _costController.dispose();
    super.dispose();
  }

  // NEW: Helper getter for the current company document reference
  DocumentReference get _companyRef => FirebaseFirestore.instance.collection('companies').doc(widget.companyId);

  Future<void> _loadBarcodePrintSettings() async {
    try {
      // ИСПРАВЛЕНО: Теперь настройки грузятся для конкретной фирмы
      final doc = await _companyRef
          .collection('system')
          .doc('barcodePrintSettings')
          .get();
      if (!doc.exists) return;

      final data = doc.data() as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          barcodeLabelWidthMm = data['widthMm'] is num
              ? (data['widthMm'] as num).toDouble()
              : 40;
          barcodeLabelHeightMm = data['heightMm'] is num
              ? (data['heightMm'] as num).toDouble()
              : 30;
        });
      }
    } catch (e) {
      debugPrint('Error loading barcode print settings: $e');
    }
  }

  Future<void> _showBarcodePrintSettingsDialog() async {
    final widthCtrl = TextEditingController(text: barcodeLabelWidthMm.toStringAsFixed(0));
    final heightCtrl = TextEditingController(text: barcodeLabelHeightMm.toStringAsFixed(0));

    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('הגדרות גודל מדבקה (מ"מ)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: widthCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'רוחב (Width)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: heightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'גובה (Height)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('שמור'),
            ),
          ],
        ),
      ),
    );

    if (save != true) return;

    final parsedWidth = double.tryParse(widthCtrl.text.trim());
    final parsedHeight = double.tryParse(heightCtrl.text.trim());

    if (parsedWidth == null || parsedHeight == null || parsedWidth <= 0 || parsedHeight <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('נא להזין ערכים תקינים')),
        );
      }
      return;
    }

    _showLoadingDialog();
    try {
      // ИСПРАВЛЕНО: Теперь настройки сохраняются в конкретную фирму
      await _companyRef
          .collection('system')
          .doc('barcodePrintSettings')
          .set({
        'widthMm': parsedWidth,
        'heightMm': parsedHeight,
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          barcodeLabelWidthMm = parsedWidth;
          barcodeLabelHeightMm = parsedHeight;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בשמירת הגדרות: $e')),
        );
      }
    } finally {
      _hideLoadingDialog();
    }
  }

  // --- HELPERS ---

  /// Displays a non-dismissible loading indicator dialog.
  void _showLoadingDialog() {
    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: Colors.white))
    );
  }

  /// Closes the loading indicator dialog if it is currently open.
  void _hideLoadingDialog() {
    if (Navigator.canPop(context)) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  /// Resets the form used for adding new inventory items.
  void _resetForm() {
    setState(() {
      _formResetKey++;
      _selectedGroupForAdd = null;
      _selectedSkuForAdd = null;
      _bulkQuantity = 1;
      _manualQuantityController.text = "1";
      _costController.clear();
      _submittedAndInvalid = false;
      _showSuccessScreen = false;
      _generatedBarcodes = [];
    });
  }

  /// Safely extracts the item name from document data.
  String _getName(Map<String, dynamic>? data, String docId) {
    if (data == null) return docId;
    if (data['name'] != null) return data['name'].toString();
    return docId;
  }

  /// Fetches the cost associated with a specific SKU to pre-fill the cost input field.
  Future<void> _fetchCostForSku(String skuId) async {
    try {
      var snap = await _companyRef.collection('items').where('SKU_ID', isEqualTo: skuId).get();
      for (var doc in snap.docs) {
        var data = doc.data() as Map<String, dynamic>;
        if (data['cost'] != null) {
          if (mounted) {
            setState(() {
              double c = (data['cost'] as num).toDouble();
              _costController.text = (c % 1 == 0) ? c.toInt().toString() : c.toString();
            });
          }
          return;
        }
      }
      if (mounted) setState(() => _costController.clear());
    } catch (e) { 
      debugPrint(e.toString()); 
    }
  }

  /// Delegates the generation and downloading of the Barcodes PDF to PdfService.
  Future<void> _generateBarcodesPdfFromList(List<Map<String, String>> itemsToPrint, String fileNameLabel) async {
    _showLoadingDialog();
    try {
      await PdfService.generateBarcodesPdf(
        items: itemsToPrint,
        fileNameLabel: fileNameLabel,
        labelWidthMm: barcodeLabelWidthMm,
        labelHeightMm: barcodeLabelHeightMm,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('שגיאת יצירת PDF: $e')));
    } finally {
      _hideLoadingDialog();
    }
  }

  Stream<QuerySnapshot> _getGroupsStream() => _companyRef.collection('items_groups').snapshots();
  Stream<QuerySnapshot> _getSkusStream(String groupId) => _companyRef.collection('SKU').where('GroupID', isEqualTo: groupId).snapshots();

  /// Marks a specific item as deleted (assigning a loss reason) and updates the History log.
  Future<void> _deleteItem(String docId, String itemName, String currentStatus, String itemId) async {
    String selectedReason = 'broken'; 
    
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => Directionality(
          textDirection: TextDirection.rtl, 
          child: AlertDialog(
            title: const Text('מחיקת פריט אינוונטר', style: TextStyle(color: Colors.red)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('בחר סיבת מחיקה עבור "$itemName":', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                DropdownButtonFormField<String>(
                  value: selectedReason,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'sold', child: Text('הועבר למחסן מכירה')),
                    DropdownMenuItem(value: 'lost', child: Text('נאבד')),
                    DropdownMenuItem(value: 'broken', child: Text('תקול')),
                    DropdownMenuItem(value: 'other', child: Text('אחר')),
                  ],
                  onChanged: (val) => setStateDialog(() => selectedReason = val!),
                ),
                if (currentStatus == 'in_use' || currentStatus == 'taken') ...[
                  const SizedBox(height: 15),
                  const Text("שים לב: הפריט משוייך לקוח. המחיקה תנתק את השיוך.", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                ]
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red), 
                onPressed: () => Navigator.pop(ctx, true), 
                child: const Text('אישור מחיקה')
              ),
            ],
          )
        )
      ),
    );

    if (confirm == true) {
      String? uid = FirebaseAuth.instance.currentUser?.uid;
      
      await _companyRef.collection('items').doc(docId).update({
        'status': selectedReason, 
        'dateDeleted': FieldValue.serverTimestamp(),
        'patientId': null, 
      });

      await _companyRef.collection('History').add({
        'action': selectedReason,
        'itemId': itemId,
        'itemName': itemName,
        'timestamp': FieldValue.serverTimestamp(),
        'staffUid': uid,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('הפריט הוסר והסטטוס עודכן'), backgroundColor: Colors.orange)
        );
      }
    }
  }

  /// Opens a dialog to edit an individual inventory item's properties (ID, cost, assigned SKU).
  Future<void> _editItemDetails(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final TextEditingController idCtrl = TextEditingController(text: data['ID']);
    String currentCost = '';
    if (data['cost'] != null) {
      double c = (data['cost'] as num).toDouble();
      currentCost = (c % 1 == 0) ? c.toInt().toString() : c.toString();
    }
    final TextEditingController costEditCtrl = TextEditingController(text: currentCost);
    Map<String, dynamic>? selectedGroup;
    Map<String, dynamic>? selectedSku;

    await showDialog(
      context: context, barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setStateDialog) {
          return Directionality(
            textDirection: TextDirection.rtl, 
            child: AlertDialog(
              title: const Text("עריכת פריט אינוונטר"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min, 
                  children: [
                    TextField(
                      controller: idCtrl, 
                      decoration: const InputDecoration(labelText: "ברקוד (ID)", border: OutlineInputBorder())
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: costEditCtrl, 
                      keyboardType: const TextInputType.numberWithOptions(decimal: true), 
                      decoration: const InputDecoration(labelText: "עלות (₪) - תשנה לכל הפריטים מסוג זה!", border: OutlineInputBorder())
                    ),
                    const SizedBox(height: 20),
                    _buildSearchableSelector(
                      label: "בחר קבוצה חדשה (אופציונלי)", 
                      stream: _getGroupsStream(), 
                      selectedName: selectedGroup?['name'], 
                      allowCreate: false, 
                      onSelected: (sel) => setStateDialog(() { selectedGroup = sel; selectedSku = null; })
                    ),
                    const SizedBox(height: 10),
                    if (selectedGroup != null) 
                      _buildSearchableSelector(
                        label: "בחר מק\"ט חדש", 
                        stream: _getSkusStream(selectedGroup!['id']), 
                        selectedName: selectedSku?['name'], 
                        allowCreate: false, 
                        onSelected: (sel) => setStateDialog(() => selectedSku = sel)
                      ),
                  ]
                )
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ביטול")),
                ElevatedButton(
                  onPressed: () async {
                    if (idCtrl.text.isEmpty) return;
                    _showLoadingDialog();
                    try {
                      WriteBatch batch = FirebaseFirestore.instance.batch();
                      Map<String, dynamic> updates = {};
                      
                      if (idCtrl.text.trim() != data['ID']) {
                        final check = await _companyRef.collection('items').where('ID', isEqualTo: idCtrl.text.trim()).get();
                        if (check.docs.isNotEmpty) { 
                          _hideLoadingDialog(); 
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("שגיאה: ID זה כבר קיים"), backgroundColor: Colors.red));
                          return; 
                        }
                        updates['ID'] = idCtrl.text.trim();
                      }

                      double? newCost = double.tryParse(costEditCtrl.text.trim());
                      String? targetSkuId = selectedSku != null ? selectedSku!['id'] : data['SKU_ID'];

                      if (selectedGroup != null && selectedSku != null) {
                        updates['GroupID'] = selectedGroup!['id'];
                        updates['SKU_ID'] = selectedSku!['id'];
                        updates['name'] = selectedSku!['name'];
                      }

                      if (newCost != null) {
                        updates['cost'] = newCost; 
                        if (targetSkuId != null && targetSkuId.isNotEmpty) {
                          var existingItems = await _companyRef.collection('items').where('SKU_ID', isEqualTo: targetSkuId).get();
                          for (var itemDoc in existingItems.docs) {
                            if (itemDoc.id != doc.id) {
                              batch.update(itemDoc.reference, {'cost': newCost});
                            }
                          }
                        }
                      }

                      if (updates.isNotEmpty) {
                        batch.update(doc.reference, updates);
                      }
                      
                      await batch.commit();
                      _hideLoadingDialog(); 
                      Navigator.pop(ctx);
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("עודכן בהצלחה"), backgroundColor: Colors.green));
                      }
                    } catch (e) { 
                      _hideLoadingDialog(); 
                      debugPrint("Error editing item: $e");
                    }
                  }, 
                  child: const Text("שמור")
                ),
              ],
            )
          );
        });
      },
    );
  }

  /// Parses manual input for bulk quantity creation.
  void _onManualQuantityChanged(String value) {
    int? v = int.tryParse(value);
    if (v != null && v > 0 && v <= 200) {
      setState(() { _bulkQuantity = v; });
    }
  }

  /// Dialog to create a new category (group).
  Future<void> _createNewGroupDialog() async {
    TextEditingController ctrl = TextEditingController();
    await showDialog(
      context: context, 
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl, 
        child: AlertDialog(
          title: const Text("קבוצה חדשה"), 
          content: TextField(
            controller: ctrl, 
            decoration: const InputDecoration(labelText: "שם")
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                if (ctrl.text.isNotEmpty) {
                  await _companyRef.collection('items_groups').add({'name': ctrl.text.trim()});
                  if (mounted) Navigator.pop(ctx);
                }
              }, 
              child: const Text("צור")
            )
          ],
        )
      )
    );
  }

  /// Dialog to create a new SKU within a specific group.
  Future<void> _createNewSkuDialog({String? preselectedGroupId}) async {
    TextEditingController ctrl = TextEditingController();
    String? currentGroupId = preselectedGroupId ?? (_selectedGroupForAdd != null ? _selectedGroupForAdd!['id'] : null);
    
    if (currentGroupId == null && preselectedGroupId == null) return;

    await showDialog(
      context: context, 
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl, 
        child: AlertDialog(
          title: const Text("מק\"ט חדש"), 
          content: TextField(
            controller: ctrl, 
            decoration: const InputDecoration(labelText: "שם המק\"ט")
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                if (ctrl.text.isNotEmpty) {
                  DocumentReference ref = await _companyRef.collection('SKU').add({'name': ctrl.text.trim(), 'GroupID': currentGroupId});
                  if (preselectedGroupId == null) {
                     setState(() { 
                       _selectedSkuForAdd = {'id': ref.id, 'name': ctrl.text.trim()}; 
                     });
                     _costController.clear();
                  }
                  Navigator.pop(ctx);
                }
              }, 
              child: const Text("צור")
            )
          ],
        )
      )
    );
  }

  /// Dialog to rename a specific document in a collection (used for renaming groups).
  Future<void> _editNameDialog(String collection, String docId, String currentName) async {
    TextEditingController ctrl = TextEditingController(text: currentName);
    await showDialog(
      context: context, 
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl, 
        child: AlertDialog(
          title: const Text("עריכת שם"), 
          content: TextField(
            controller: ctrl, 
            decoration: const InputDecoration(labelText: "שם חדש")
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx), 
              child: const Text("ביטול")
            ),
            ElevatedButton(
              onPressed: () async {
                if (ctrl.text.isNotEmpty) {
                  await _companyRef.collection(collection).doc(docId).update({'name': ctrl.text.trim()});
                  Navigator.pop(ctx);
                }
              }, 
              child: const Text("שמור")
            )
          ],
        )
      )
    );
  }

  /// Dialog to edit a SKU, enabling the user to rename it or move it to a different group.
  Future<void> _editSkuDialog(String skuId, String currentName, String currentGroupId) async {
    TextEditingController nameCtrl = TextEditingController(text: currentName);
    Map<String, dynamic>? selectedNewGroup;
    String currentGroupName = 'טוען...';
    
    try {
      var gDoc = await _companyRef.collection('items_groups').doc(currentGroupId).get();
      if (gDoc.exists) {
        currentGroupName = gDoc.data()?['name'] ?? 'Unknown';
      }
    } catch (_) {}

    selectedNewGroup = {'id': currentGroupId, 'name': currentGroupName};

    await showDialog(
      context: context, 
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Directionality(
              textDirection: TextDirection.rtl, 
              child: AlertDialog(
                title: const Text("עריכת מק\"ט"),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl, 
                        decoration: const InputDecoration(labelText: "שם המק\"ט", border: OutlineInputBorder())
                      ),
                      const SizedBox(height: 20),
                      _buildSearchableSelector(
                        label: "שינוי קבוצה (אופציונלי)", 
                        stream: _getGroupsStream(), 
                        selectedName: selectedNewGroup?['name'], 
                        allowCreate: false, 
                        onSelected: (sel) => setStateDialog(() => selectedNewGroup = sel)
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "שים לב: שינוי הקבוצה יעביר את כל הפריטים תחת מק\"ט זה לקבוצה החדשה.", 
                        style: TextStyle(fontSize: 12, color: Colors.grey)
                      ),
                    ]
                  )
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx), 
                    child: const Text("ביטול")
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      if (nameCtrl.text.isEmpty) return;
                      _showLoadingDialog();
                      try {
                        WriteBatch batch = FirebaseFirestore.instance.batch();
                        DocumentReference skuRef = _companyRef.collection('SKU').doc(skuId);
                        Map<String, dynamic> updates = {'name': nameCtrl.text.trim()};
                        
                        bool groupChanged = selectedNewGroup != null && selectedNewGroup!['id'] != currentGroupId;
                        if (groupChanged) {
                          updates['GroupID'] = selectedNewGroup!['id'];
                        }
                        batch.update(skuRef, updates);

                        if (nameCtrl.text.trim() != currentName || groupChanged) {
                          var items = await _companyRef.collection('items').where('SKU_ID', isEqualTo: skuId).get();
                          for (var doc in items.docs) {
                            Map<String, dynamic> itemUpdates = {};
                            if (nameCtrl.text.trim() != currentName) {
                              itemUpdates['name'] = nameCtrl.text.trim();
                            }
                            if (groupChanged) {
                              itemUpdates['GroupID'] = selectedNewGroup!['id'];
                            }
                            if (itemUpdates.isNotEmpty) {
                              batch.update(doc.reference, itemUpdates);
                            }
                          }
                        }
                        
                        await batch.commit();
                        _hideLoadingDialog();
                        Navigator.pop(ctx);
                        
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("עודכן בהצלחה"), backgroundColor: Colors.green));
                        }
                      } catch (e) {
                        _hideLoadingDialog();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                      }
                    }, 
                    child: const Text("שמור")
                  )
                ],
              )
            );
          }
        );
      }
    );
  }

  /// Deletes a Group or SKU, safely archiving associated items if permitted.
  Future<void> _deleteGroupOrSku(String collection, String docId, String name, {bool isGroup = false}) async {
    _showLoadingDialog();
    try {
      Query query = _companyRef.collection('items');
      if (isGroup) {
        query = query.where('GroupID', isEqualTo: docId);
      } else {
        query = query.where('SKU_ID', isEqualTo: docId);
      }

      final allItemsSnapshot = await query.get();
      final allDocs = allItemsSnapshot.docs;

      final inUseList = allDocs.where((d) {
        final st = d['status'] as String?;
        return st == 'in_use' || st == 'taken';
      }).toList();

      if (isGroup) {
        var skusInGroup = await _companyRef.collection('SKU').where('GroupID', isEqualTo: docId).get();
        if (skusInGroup.docs.isNotEmpty) {
          _hideLoadingDialog();
          if (!mounted) return;
          showDialog(
            context: context, 
            builder: (ctx) => Directionality(
              textDirection: TextDirection.rtl, 
              child: AlertDialog(
                title: const Text("שגיאה", style: TextStyle(color: Colors.red)),
                content: const Text("לא ניתן למחוק קבוצה זו כי יש בה מק\"טים.\nיש למחוק או להעביר את המק\"טים קודם."),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("אישור"))],
              )
            )
          );
          return;
        }
      }

      _hideLoadingDialog(); 

      if (inUseList.isNotEmpty) {
        if (!mounted) return;
        showDialog(
          context: context, 
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl, 
            child: AlertDialog(
              title: const Text("לא ניתן למחוק!", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              content: Text("ישנם ${inUseList.length} פריטים מקבוצה/מק\"ט זה שנמצאים כרגע אצל לקוח.\nאנא שחרר אותם (החזר למלאי) לפני המחיקה."),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("אישור"))],
            )
          )
        );
        return;
      }

      if (!mounted) return;
      
      bool? confirm = await showDialog(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl, 
          child: AlertDialog(
            title: const Text("אישור מחיקה", style: TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("האם למחוק את \"$name\"?"),
                const SizedBox(height: 10),
                if (allDocs.any((d) => d['status'] != 'broken' && d['status'] != 'sold' && d['status'] != 'lost' && d['status'] != 'other')) ...[
                   Text("שים לב: קיימים ${allDocs.where((d) => d['status'] != 'broken' && d['status'] != 'sold' && d['status'] != 'lost' && d['status'] != 'other').length} פריטים פעילים במלאי.", style: const TextStyle(fontWeight: FontWeight.bold)),
                   const Text("הם יועברו לסטטוס 'תקול' (Broken).", style: TextStyle(color: Colors.red)),
                ] else 
                   const Text("אין פריטים פעילים (רשימה ריקה).", style: TextStyle(color: Colors.green)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false), 
                child: const Text("ביטול")
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true), 
                child: const Text("מחק")
              ),
            ],
          )
        ),
      );

      if (confirm == true) {
        _showLoadingDialog();
        WriteBatch batch = FirebaseFirestore.instance.batch();

        for (var doc in allDocs) {
          if (doc['status'] != 'broken' && doc['status'] != 'sold' && doc['status'] != 'lost' && doc['status'] != 'other') {
             batch.update(doc.reference, {'status': 'broken', 'dateDeleted': FieldValue.serverTimestamp()});
          }
        }
        
        batch.delete(_companyRef.collection(collection).doc(docId));
        await batch.commit();
        
        _hideLoadingDialog();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("נמחק בהצלחה"), backgroundColor: Colors.green));
        }
      }

    } catch (e) {
      try { _hideLoadingDialog(); } catch (_) {}
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  /// Handles the generation of multiple new inventory items within a transaction, 
  /// ensuring unique sequential barcodes and updating shared properties.
  Future<void> _saveBulkItems() async {
    setState(() => _submittedAndInvalid = true);
    if (_selectedGroupForAdd == null || _selectedSkuForAdd == null) return;
    
    double cost = double.tryParse(_costController.text.trim()) ?? 0.0;
    _showLoadingDialog();
    
    try {
      final systemRef = _companyRef.collection('system').doc('settings');
      List<String> newBarcodes = [];

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot sysDoc = await transaction.get(systemRef);
        int currentSeq = 1;
        if (sysDoc.exists && sysDoc.data() != null) {
          var data = sysDoc.data() as Map<String, dynamic>;
          if (data.containsKey('lastBarcodeSeq')) currentSeq = data['lastBarcodeSeq'];
        }
        
        for (int i = 0; i < _bulkQuantity; i++) {
          newBarcodes.add(AppHelpers.generateBarcodeWithChecksum(currentSeq + i));
        }
        
        transaction.set(systemRef, {'lastBarcodeSeq': currentSeq + _bulkQuantity}, SetOptions(merge: true));
      });

      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (String id in newBarcodes) {
        batch.set(_companyRef.collection('items').doc(), {
          'ID': id, 
          'GroupID': _selectedGroupForAdd!['id'], 
          'SKU_ID': _selectedSkuForAdd!['id'], 
          'name': _selectedSkuForAdd!['name'], 
          'status': 'available', 
          'dateAdded': FieldValue.serverTimestamp(), 
          'cost': cost, 
        });
      }

      var existingItems = await _companyRef.collection('items').where('SKU_ID', isEqualTo: _selectedSkuForAdd!['id']).get();
      for (var doc in existingItems.docs) {
        batch.update(doc.reference, {'cost': cost});
      }
      
      await batch.commit();
      _hideLoadingDialog();
      
      setState(() {
        _lastAddedItemName = _selectedSkuForAdd!['name'];
        _generatedBarcodes = newBarcodes;
        _showSuccessScreen = true;
      });
      
    } catch (e) { 
      _hideLoadingDialog(); 
      debugPrint(e.toString());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("שגיאה: $e"), backgroundColor: Colors.red));
    }
  }

  /// Builds a dynamic dropdown selector with built-in search filtering.
  Widget _buildSearchableSelector({
    Key? key, 
    required String label, 
    required Stream<QuerySnapshot> stream, 
    required Function(Map<String, dynamic>?) onSelected, 
    VoidCallback? onCreateNew, 
    required String? selectedName, 
    bool showError = false, 
    bool allowCreate = true, 
    bool showAllOption = false
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, 
      children: [
        StreamBuilder<QuerySnapshot>(
          stream: stream, 
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const LinearProgressIndicator();
            
            List<Map<String, dynamic>> options = snapshot.data!.docs.map((doc) => {'id': doc.id, 'name': _getName(doc.data() as Map<String, dynamic>, doc.id)}).toList();
            
            if (options.isEmpty && allowCreate) {
              return Container(
                width: double.infinity, 
                padding: const EdgeInsets.symmetric(vertical: 5), 
                child: OutlinedButton.icon(
                  onPressed: onCreateNew, 
                  icon: const Icon(Icons.add_circle, color: Colors.green), 
                  label: Text("אין אפשרויות. צור $label חדש", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green))
                )
              );
            }
            
            return LayoutBuilder(builder: (context, constraints) {
              return Autocomplete<Map<String, dynamic>>(
                key: key,
                optionsBuilder: (v) {
                  List<Map<String, dynamic>> filtered = v.text == '' ? List.from(options) : options.where((o) => o['name'].toString().toLowerCase().contains(v.text.toLowerCase())).toList();
                  if (allowCreate && onCreateNew != null) {
                    filtered.insert(0, {'id': 'CREATE_NEW_ACTION', 'name': '➕ צור חדש...'});
                  }
                  if (showAllOption) {
                    filtered.insert(0, {'id': 'ALL_ACTION', 'name': '⭐️ הכל'});
                  }
                  return filtered;
                },
                displayStringForOption: (o) {
                  if (o['id'] == 'CREATE_NEW_ACTION' || o['id'] == 'ALL_ACTION') return ''; 
                  return o['name'];
                },
                onSelected: (selection) {
                  if (selection['id'] == 'CREATE_NEW_ACTION') { 
                    if (onCreateNew != null) onCreateNew(); 
                  } else if (selection['id'] == 'ALL_ACTION') { 
                    onSelected(null); 
                  } else { 
                    onSelected(selection); 
                  }
                },
                fieldViewBuilder: (ctx, ctrl, focus, submit) {
                  if (selectedName != null && ctrl.text.isEmpty) ctrl.text = selectedName;
                  return TextField(
                    controller: ctrl, 
                    focusNode: focus, 
                    onTap: () { 
                      if (ctrl.text.isNotEmpty) ctrl.clear(); 
                    }, 
                    decoration: InputDecoration(
                      labelText: label, 
                      border: const OutlineInputBorder(), 
                      suffixIcon: const Icon(Icons.arrow_drop_down), 
                      errorText: showError && selectedName == null ? 'חובה' : null, 
                      isDense: true
                    )
                  );
                },
                optionsViewBuilder: (ctx, onSel, opts) => Align(
                  alignment: Alignment.topRight, 
                  child: Material(
                    elevation: 4, 
                    child: SizedBox(
                      width: constraints.maxWidth, 
                      height: 250, 
                      child: ListView.builder(
                        padding: EdgeInsets.zero, 
                        itemCount: opts.length, 
                        itemBuilder: (ctx, i) {
                          final o = opts.elementAt(i);
                          TextStyle? style;
                          if (o['id'] == 'CREATE_NEW_ACTION') style = const TextStyle(fontWeight: FontWeight.bold, color: Colors.green);
                          if (o['id'] == 'ALL_ACTION') style = const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue);
                          return ListTile(title: Text(o['name'], style: style), onTap: () => onSel(o));
                        }
                      )
                    )
                  )
                ),
              );
            });
          }
        )
      ]
    );
  }

  @override
  Widget build(BuildContext context) {
    const TextStyle bigTextStyle = TextStyle(fontSize: 16, color: Colors.black87);
    const TextStyle bigBoldStyle = TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFE0F2F1),
        appBar: AppBar(
          title: const Text('ניהול מלאי'), 
          backgroundColor: const Color(0xFF004D40), 
          foregroundColor: Colors.white, 
          bottom: TabBar(
            controller: _tabController, 
            indicatorColor: Colors.white, 
            labelColor: Colors.white, 
            unselectedLabelColor: Colors.white70, 
            tabs: const [
              Tab(text: 'רשימת פריטי אינוונטר', icon: Icon(Icons.list)), 
              Tab(text: 'הוספת פריטי אינוונטר', icon: Icon(Icons.add_box)), 
              Tab(text: 'ניהול קבוצות ומק"טים', icon: Icon(Icons.folder_copy)),
            ]
          )
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            // --- TAB 1: LIST ---
            StreamBuilder<QuerySnapshot>(
              stream: _companyRef.collection('items_groups').snapshots(),
              builder: (context, groupsSnapshot) {
                Map<String, String> groupNamesMap = {};
                if (groupsSnapshot.hasData) {
                  for (var gDoc in groupsSnapshot.data!.docs) {
                    groupNamesMap[gDoc.id] = (gDoc.data() as Map)['name']?.toString() ?? 'לא ידוע';
                  }
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: _companyRef.collection('items').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                    var docs = snapshot.data!.docs;
                    var filtered = docs.where((doc) {
                      var d = doc.data() as Map<String, dynamic>;
                      if (d['status'] == 'broken' || d['status'] == 'sold' || d['status'] == 'lost' || d['status'] == 'other') return false;
                      
                      bool mId = _searchQuery.isEmpty || (d['ID'] ?? '').toString().contains(_searchQuery);
                      bool mG = _filterGroup == null || d['GroupID'] == _filterGroup!['id'];
                      bool mS = _filterSku == null || d['SKU_ID'] == _filterSku!['id'];
                      
                      bool mSort = true;
                      if (_sortOption == 'available') mSort = (d['status'] == 'available');
                      if (_sortOption == 'taken') mSort = (d['status'] != 'available');
                      
                      return mId && mG && mS && mSort;
                    }).toList();

                    // --- ALPHABETICAL SORTING (Group -> SKU -> ID) ---
                    filtered.sort((a, b) {
                      var da = a.data() as Map<String, dynamic>;
                      var db = b.data() as Map<String, dynamic>;
                      
                      // 1. By Group
                      String groupA = groupNamesMap[da['GroupID']] ?? 'תת'; 
                      String groupB = groupNamesMap[db['GroupID']] ?? 'תת';
                      int groupCmp = groupA.compareTo(groupB);
                      if (groupCmp != 0) return groupCmp;
                      
                      // 2. By SKU Name
                      String skuA = (da['name'] ?? '').toString();
                      String skuB = (db['name'] ?? '').toString();
                      int skuCmp = skuA.compareTo(skuB);
                      if (skuCmp != 0) return skuCmp;
                      
                      // 3. By ID
                      String idA = (da['ID'] ?? '').toString();
                      String idB = (db['ID'] ?? '').toString();
                      return idA.compareTo(idB);
                    });

                    // PAGINATION
                    int total = filtered.length;
                    int pages = (total / _itemsPerPage).ceil(); 
                    if (pages == 0) pages = 1;
                    if (_currentPage >= pages) _currentPage = pages - 1;
                    if (_currentPage < 0) _currentPage = 0;

                    int start = _currentPage * _itemsPerPage;
                    int end = start + _itemsPerPage;
                    if (end > total) end = total;
                    var currentItems = total > 0 ? filtered.sublist(start, end) : [];

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(20), 
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(15), 
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)), 
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: _searchController, 
                                            decoration: const InputDecoration(labelText: 'חפש ID', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true), 
                                            onChanged: (val) => setState(() { _searchQuery = val.trim(); _currentPage = 0; })
                                          )
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: DropdownButtonFormField<String>(
                                            value: _sortOption, 
                                            decoration: const InputDecoration(labelText: 'מיון', border: OutlineInputBorder(), isDense: true), 
                                            items: const [
                                              DropdownMenuItem(value: 'default', child: Text('הכל')), 
                                              DropdownMenuItem(value: 'available', child: Text('פנויים')), 
                                              DropdownMenuItem(value: 'taken', child: Text('תפוסים'))
                                            ], 
                                            onChanged: (val) => setState(() { _sortOption = val!; _currentPage = 0; })
                                          )
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.refresh), 
                                          onPressed: () { 
                                            _searchController.clear(); 
                                            setState(() { 
                                              _searchQuery = ""; 
                                              _filterGroup = null; 
                                              _filterSku = null; 
                                              _sortOption = 'default'; 
                                              _filterResetKey++; 
                                              _currentPage = 0; 
                                            }); 
                                          }
                                        )
                                      ]
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildSearchableSelector(
                                            key: ValueKey("g_$_filterResetKey"), 
                                            label: "קבוצה", 
                                            stream: _getGroupsStream(), 
                                            selectedName: _filterGroup?['name'], 
                                            allowCreate: false, 
                                            showAllOption: true, 
                                            onSelected: (sel) => setState(() { _filterGroup = sel; _filterSku = null; _filterResetKey++; _currentPage = 0; })
                                          )
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: _filterGroup == null 
                                          ? const Opacity(
                                              opacity: 0.5, 
                                              child: TextField(decoration: InputDecoration(labelText: "מק\"ט", border: OutlineInputBorder(), enabled: false, isDense: true))
                                            ) 
                                          : _buildSearchableSelector(
                                              key: ValueKey("s_$_filterResetKey"), 
                                              label: "מק\"ט", 
                                              stream: _getSkusStream(_filterGroup!['id']), 
                                              selectedName: _filterSku?['name'], 
                                              allowCreate: false, 
                                              showAllOption: true, 
                                              onSelected: (sel) => setState(() { 
                                                _filterSku = sel; 
                                                _currentPage = 0; 
                                                _filterResetKey++; 
                                              })
                                            )
                                        )
                                      ]
                                    ),
                                  ]
                                )
                              ),
                              
                              const SizedBox(height: 10),

                              // --- PAGINATION AND BARCODE CONTROLS ---
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                                child: Row(
                                  children: [
                                    const Expanded(child: SizedBox()),
                                    
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ElevatedButton.icon(
                                          onPressed: _currentPage < pages - 1 ? () => setState(() => _currentPage++) : null, 
                                          icon: const Icon(Icons.arrow_back), 
                                          label: const Text("הבא"), 
                                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF004D40), foregroundColor: Colors.white)
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 10), 
                                          child: Text("עמוד ${_currentPage + 1} מתוך $pages", style: const TextStyle(fontWeight: FontWeight.bold))
                                        ),
                                        ElevatedButton.icon(
                                          onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null, 
                                          icon: const Icon(Icons.arrow_forward), 
                                          label: const Text("הקודם"), 
                                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF004D40), foregroundColor: Colors.white)
                                        ),
                                      ],
                                    ),

                                    Expanded(
                                      child: Align(
                                        alignment: Alignment.centerLeft, 
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (!_isBarcodeMode)
                                                ElevatedButton.icon(
                                                  icon: const Icon(Icons.qr_code_scanner),
                                                  label: const Text("הדפסת ברקודים"),
                                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white),
                                                  onPressed: () => setState(() => _isBarcodeMode = true),
                                                )
                                              else ...[
                                                ElevatedButton.icon(
                                                  icon: const Icon(Icons.print),
                                                  label: Text("הדפס (${_selectedBarcodes.length})"),
                                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[700], foregroundColor: Colors.white),
                                                  onPressed: _selectedBarcodes.isEmpty ? null : () async {
                                                    await _generateBarcodesPdfFromList(_selectedBarcodes.values.toList(), "Selected");
                                                    setState(() {
                                                      _isBarcodeMode = false;
                                                      _selectedBarcodes.clear();
                                                    });
                                                  },
                                                ),
                                                const SizedBox(width: 8),
                                                IconButton(
                                                  icon: const Icon(Icons.settings),
                                                  color: Colors.blueGrey,
                                                  onPressed: _showBarcodePrintSettingsDialog,
                                                  tooltip: 'הגדרות הדפסה',
                                                ),
                                                const SizedBox(width: 8),
                                                OutlinedButton.icon(
                                                  icon: const Icon(Icons.select_all),
                                                  label: const Text("בחר הכל"),
                                                  onPressed: () {
                                                    setState(() {
                                                      for (var doc in filtered) {
                                                        var d = doc.data() as Map<String, dynamic>;
                                                        _selectedBarcodes[doc.id] = {
                                                          'id': d['ID']?.toString() ?? '',
                                                          'name': d['name']?.toString() ?? 'Unknown'
                                                        };
                                                      }
                                                    });
                                                  },
                                                ),
                                                const SizedBox(width: 8),
                                                TextButton(
                                                  onPressed: () => setState(() {
                                                    _isBarcodeMode = false;
                                                    _selectedBarcodes.clear();
                                                  }),
                                                  child: const Text("ביטול", style: TextStyle(color: Colors.red)),
                                                )
                                              ]
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 10),
                              
                              Container(
                                padding: const EdgeInsets.all(10), 
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5)), 
                                child: Row(
                                  children: [
                                    if (_isBarcodeMode) const SizedBox(width: 48), 
                                    const Expanded(flex: 2, child: Text('קבוצה', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))), 
                                    const Expanded(flex: 2, child: Text('מק"ט', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))), 
                                    const Expanded(flex: 1, child: Text('ID', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))), 
                                    const Expanded(flex: 1, child: Text('סטטוס', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))), 
                                    const Expanded(flex: 2, child: Text('מספר לקוח', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))), 
                                    const SizedBox(width: 120, child: Text('פעולות', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)))
                                  ]
                                )
                              ),
                            ]
                          )
                        ),
                        
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 100), 
                            itemCount: currentItems.length,
                            itemBuilder: (context, index) {
                              var doc = currentItems[index];
                              var d = doc.data() as Map<String, dynamic>;
                              
                              String displayCost = '';
                              if (d['cost'] != null) {
                                double c = (d['cost'] as num).toDouble();
                                displayCost = "₪${c % 1 == 0 ? c.toInt() : c}";
                              }

                              String groupName = groupNamesMap[d['GroupID']] ?? 'לא ידוע';
                              
                              return Card(
                                margin: const EdgeInsets.only(bottom: 5), 
                                color: Colors.white, 
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10), 
                                  child: Row(
                                    children: [
                                      if (_isBarcodeMode)
                                        Checkbox(
                                          value: _selectedBarcodes.containsKey(doc.id),
                                          onChanged: (val) {
                                            setState(() {
                                              if (val == true) {
                                                _selectedBarcodes[doc.id] = {
                                                  'id': d['ID']?.toString() ?? '',
                                                  'name': d['name']?.toString() ?? 'Unknown'
                                                };
                                              } else {
                                                _selectedBarcodes.remove(doc.id);
                                              }
                                            });
                                          },
                                        ),
                                      
                                      Expanded(
                                        flex: 2, 
                                        child: SelectableText(groupName, style: bigBoldStyle, textAlign: TextAlign.center)
                                      ),

                                      Expanded(
                                        flex: 2, 
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min, 
                                          crossAxisAlignment: CrossAxisAlignment.center, 
                                          children: [
                                            SelectableText(d['name'] ?? '', style: bigBoldStyle, textAlign: TextAlign.center), 
                                            if (displayCost.isNotEmpty) 
                                              SelectableText(displayCost, style: const TextStyle(fontSize: 14, color: Colors.grey), textAlign: TextAlign.center)
                                          ]
                                        )
                                      ), 
                                      Expanded(
                                        flex: 1, 
                                        child: SelectableText(d['ID'] ?? '', style: bigTextStyle, textAlign: TextAlign.center)
                                      ), 
                                      Expanded(
                                        flex: 1, 
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), 
                                          decoration: BoxDecoration(color: AppHelpers.getStatusColor(d['status'] ?? ''), borderRadius: BorderRadius.circular(4)), 
                                          child: SelectableText(AppHelpers.getStatusText(d['status'] ?? ''), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), textAlign: TextAlign.center)
                                        )
                                      ),
                                      Expanded(
                                        flex: 2, 
                                        child: SelectableText((d['patientId'] != null) ? SecurityService.decryptID(d['patientId']) : '-', textAlign: TextAlign.center, style: bigTextStyle)
                                      ), 
                                      SizedBox(
                                        width: 120, 
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.end, 
                                          children: [
                                            IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _editItemDetails(doc)), 
                                            const SizedBox(width: 15), 
                                            IconButton(icon: const Icon(Icons.delete_forever, color: Colors.red, size: 28), onPressed: () => _deleteItem(doc.id, d['name'] ?? '', d['status'] ?? '', d['ID'] ?? ''))
                                          ]
                                        )
                                      )
                                    ]
                                  )
                                )
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                );
              }
            ),

            // --- TAB 2: ADD ---
            _showSuccessScreen 
            ? _buildSuccessScreen() 
            : SingleChildScrollView(
                padding: const EdgeInsets.all(30), 
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, 
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                      children: [
                        const Text("יצירת פריטים וברקודים", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF004D40))), 
                        TextButton.icon(onPressed: _resetForm, icon: const Icon(Icons.refresh), label: const Text("ניקוי"))
                      ]
                    ),
                    const SizedBox(height: 20),
                    _buildSearchableSelector(
                      key: ValueKey("g_$_formResetKey"), 
                      label: "קבוצה", 
                      stream: _getGroupsStream(), 
                      selectedName: _selectedGroupForAdd?['name'], 
                      showError: _submittedAndInvalid, 
                      showAllOption: false, 
                      onSelected: (sel) => setState(() { _selectedGroupForAdd = sel; _selectedSkuForAdd = null; }), 
                      onCreateNew: _createNewGroupDialog
                    ),
                    const SizedBox(height: 20),
                    if (_selectedGroupForAdd != null) 
                      _buildSearchableSelector(
                        key: ValueKey("s_$_formResetKey"), 
                        label: "מק\"ט", 
                        stream: _getSkusStream(_selectedGroupForAdd!['id']), 
                        selectedName: _selectedSkuForAdd?['name'], 
                        showError: _submittedAndInvalid, 
                        showAllOption: false, 
                        onSelected: (sel) { 
                          setState(() => _selectedSkuForAdd = sel); 
                          if (sel != null) { 
                            _fetchCostForSku(sel['id']); 
                          } 
                        }, 
                        onCreateNew: () => _createNewSkuDialog()
                      ),
                    if (_selectedSkuForAdd != null) ...[
                      const SizedBox(height: 30),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end, 
                        children: [
                          const Text("כמות (עד 200):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          const SizedBox(width: 10),
                          Container(
                            decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)), 
                            child: Row(
                              children: [
                                IconButton(icon: const Icon(Icons.remove), onPressed: () { if (_bulkQuantity > 1) { setState(() { _bulkQuantity--; _manualQuantityController.text = _bulkQuantity.toString(); }); } }), 
                                SizedBox(
                                  width: 50, 
                                  child: TextField(
                                    controller: _manualQuantityController, 
                                    keyboardType: TextInputType.number, 
                                    textAlign: TextAlign.center, 
                                    decoration: const InputDecoration(border: InputBorder.none), 
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly], 
                                    onChanged: _onManualQuantityChanged
                                  )
                                ), 
                                IconButton(icon: const Icon(Icons.add), onPressed: () { if (_bulkQuantity < 200) { setState(() { _bulkQuantity++; _manualQuantityController.text = _bulkQuantity.toString(); }); } })
                              ]
                            )
                          ),
                          const SizedBox(width: 30),
                          Expanded(
                            child: TextField(
                              controller: _costController, 
                              keyboardType: const TextInputType.numberWithOptions(decimal: true), 
                              decoration: const InputDecoration(labelText: "עלות ליחידה (₪)", border: OutlineInputBorder(), isDense: true)
                            )
                          ),
                        ]
                      ),
                      const SizedBox(height: 30),
                      SizedBox(
                        width: double.infinity, 
                        height: 55, 
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.auto_awesome), 
                          label: Text("צור $_bulkQuantity פריטים אוטומטית"), 
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF004D40), 
                            foregroundColor: Colors.white, 
                            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                          ), 
                          onPressed: _saveBulkItems
                        )
                      ),
                      const SizedBox(height: 100),
                    ]
                  ]
                )
              ),

            // --- TAB 3: GROUPS MANAGEMENT ---
            Container(
              color: Colors.grey[50], 
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                    children: [
                      const Text("עץ קטגוריות ופריטים", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF004D40))), 
                      ElevatedButton.icon(
                        onPressed: _createNewGroupDialog, 
                        icon: const Icon(Icons.create_new_folder), 
                        label: const Text("קבוצה חדשה"), 
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF004D40), foregroundColor: Colors.white)
                      )
                    ]
                  ),
                  const Divider(thickness: 1, height: 30),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _companyRef.collection('items').snapshots(),
                      builder: (ctx, itemSnapshot) {
                        if (!itemSnapshot.hasData) return const Center(child: CircularProgressIndicator());
                        var allItems = itemSnapshot.data!.docs;
                        Map<String, int> groupCounts = {}; 
                        Map<String, int> skuCounts = {}; 
                        Map<String, double> groupCosts = {}; 
                        Map<String, double> skuCosts = {}; 
                        Map<String, Set<String>> skusInGroup = {};

                        for (var doc in allItems) {
                          var d = doc.data() as Map<String, dynamic>;
                          if (d['status'] == 'broken' || d['status'] == 'sold' || d['status'] == 'lost' || d['status'] == 'other') continue; 
                          String gId = d['GroupID'] ?? ''; 
                          String sId = d['SKU_ID'] ?? ''; 
                          double cost = (d['cost'] ?? 0).toDouble();
                          
                          if (gId.isNotEmpty) {
                            groupCounts[gId] = (groupCounts[gId] ?? 0) + 1; 
                            groupCosts[gId] = (groupCosts[gId] ?? 0) + cost;
                            if (skusInGroup[gId] == null) skusInGroup[gId] = {};
                            if (sId.isNotEmpty) skusInGroup[gId]!.add(sId);
                          }
                          if (sId.isNotEmpty) { 
                            skuCounts[sId] = (skuCounts[sId] ?? 0) + 1; 
                            skuCosts[sId] = (skuCosts[sId] ?? 0) + cost; 
                          }
                        }

                        return StreamBuilder<QuerySnapshot>(
                          stream: _getGroupsStream(),
                          builder: (context, groupSnapshot) {
                            if (!groupSnapshot.hasData) return const Center(child: CircularProgressIndicator());
                            var groups = groupSnapshot.data!.docs;
                            if (groups.isEmpty) return const Center(child: Text("אין קבוצות. צור קבוצה חדשה."));

                            return ListView.builder(
                              padding: const EdgeInsets.only(bottom: 100), 
                              itemCount: groups.length,
                              itemBuilder: (context, i) {
                                var groupDoc = groups[i]; 
                                var gData = groupDoc.data() as Map<String, dynamic>; 
                                String gName = gData['name'] ?? 'Unknown';
                                int gCount = groupCounts[groupDoc.id] ?? 0; 
                                double gCost = groupCosts[groupDoc.id] ?? 0; 
                                int skuCountInGroup = skusInGroup[groupDoc.id]?.length ?? 0;

                                return Card(
                                  elevation: 2, 
                                  margin: const EdgeInsets.only(bottom: 10), 
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  child: ExpansionTile(
                                    leading: const Icon(Icons.folder, color: Colors.amber, size: 30),
                                    title: Text(gName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                    subtitle: Text("סה\"כ פריטי אינוונטר: $gCount | מק\"טים: $skuCountInGroup | שווי: ₪${gCost.toStringAsFixed(0)}", style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                                    childrenPadding: const EdgeInsets.all(10),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min, 
                                      children: [
                                        IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _editNameDialog('items_groups', groupDoc.id, gName)), 
                                        IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteGroupOrSku('items_groups', groupDoc.id, gName, isGroup: true)), 
                                        const Icon(Icons.expand_more)
                                      ]
                                    ),
                                    children: [
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 5), 
                                        decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(5)), 
                                        child: ListTile(
                                          leading: const Icon(Icons.add_circle, color: Colors.green), 
                                          title: const Text("הוסף מק\"ט", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)), 
                                          onTap: () => _createNewSkuDialog(preselectedGroupId: groupDoc.id)
                                        )
                                      ),
                                      StreamBuilder<QuerySnapshot>(
                                        stream: _getSkusStream(groupDoc.id),
                                        builder: (ctx, skuSnapshot) {
                                          if (!skuSnapshot.hasData) return const LinearProgressIndicator();
                                          var skus = skuSnapshot.data!.docs;
                                          if (skus.isEmpty) return const Padding(padding: EdgeInsets.all(8.0), child: Text("אין פריטים בקבוצה זו", style: TextStyle(color: Colors.grey)));

                                          return ListView.builder(
                                            shrinkWrap: true, 
                                            physics: const NeverScrollableScrollPhysics(), 
                                            itemCount: skus.length,
                                            itemBuilder: (ctx, j) {
                                              var skuDoc = skus[j]; 
                                              var sData = skuDoc.data() as Map<String, dynamic>; 
                                              String sName = sData['name'] ?? 'Unknown';
                                              int sCount = skuCounts[skuDoc.id] ?? 0; 
                                              double sCost = skuCosts[skuDoc.id] ?? 0;

                                              return Container(
                                                margin: const EdgeInsets.symmetric(vertical: 4), 
                                                decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(5), border: Border.all(color: Colors.grey[300]!)),
                                                child: ListTile(
                                                  leading: const Icon(Icons.description, color: Colors.teal),
                                                  title: Text(sName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                                  subtitle: Text("פריטי אינוונטר: $sCount | שווי: ₪${sCost.toStringAsFixed(0)}"),
                                                  trailing: Row(
                                                    mainAxisSize: MainAxisSize.min, 
                                                    children: [
                                                      IconButton(icon: const Icon(Icons.edit, size: 20, color: Colors.blueGrey), onPressed: () => _editSkuDialog(skuDoc.id, sName, groupDoc.id)), 
                                                      IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.redAccent), onPressed: () => _deleteGroupOrSku('SKU', skuDoc.id, sName, isGroup: false))
                                                    ]
                                                  )
                                                ),
                                              );
                                            },
                                          );
                                        },
                                      )
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        );
                      }
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

  /// Builds the success screen displayed immediately after bulk generating new barcodes.
  Widget _buildSuccessScreen() {
    return Container(
      width: double.infinity, 
      padding: const EdgeInsets.all(30),
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 80),
          const SizedBox(height: 10),
          Text("${_generatedBarcodes.length} פריטים מסוג '$_lastAddedItemName' נוצרו בהצלחה!", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          SizedBox(
            width: 300, 
            height: 60, 
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[700], foregroundColor: Colors.white), 
              onPressed: () {
                List<Map<String, String>> toPrint = _generatedBarcodes.map((c) => {'id': c, 'name': _lastAddedItemName}).toList();
                _generateBarcodesPdfFromList(toPrint, _lastAddedItemName);
              }, 
              icon: const Icon(Icons.print), 
              label: const Text("הדפס ברקודים (PDF)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
            )
          ),
          const SizedBox(height: 30),
          const Text("רשימת הברקודים שנוצרו:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              width: 300, 
              decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(10), color: Colors.white), 
              child: ListView.separated(
                itemCount: _generatedBarcodes.length, 
                separatorBuilder: (ctx, i) => const Divider(height: 1), 
                itemBuilder: (ctx, i) => ListTile(
                  leading: CircleAvatar(backgroundColor: Colors.teal[50], child: Text('${i+1}')), 
                  title: SelectableText(_generatedBarcodes[i], style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)), 
                  trailing: const Icon(Icons.qr_code_2, color: Colors.grey)
                )
              )
            )
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _resetForm, 
            icon: const Icon(Icons.add), 
            label: const Text("צור פריטים נוספים")
          )
        ],
      ),
    );
  }
}