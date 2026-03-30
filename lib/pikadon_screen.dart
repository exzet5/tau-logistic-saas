import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:calendar_date_picker2/calendar_date_picker2.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:universal_html/html.dart' as html;
import 'package:excel/excel.dart' hide Border, TextSpan;
import 'security_service.dart';

class PikadonScreen extends StatefulWidget {
  const PikadonScreen({super.key});

  @override
  State<PikadonScreen> createState() => _PikadonScreenState();
}

class _PikadonScreenState extends State<PikadonScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  final TextEditingController _searchPendingController = TextEditingController();
  final TextEditingController _searchActiveController = TextEditingController();
  final TextEditingController _searchHistoryController = TextEditingController();

  String _pendingSearchQuery = "";
  String _activeSearchQuery = "";
  String _historySearchQuery = "";
  
  List<DateTime?> _pendingDates = [];
  List<DateTime?> _activeDates = [];
  List<DateTime?> _historyDates = [];
  
  String _historyTypeFilter = 'all';

  bool _isProcessing = false;

  bool _isLoadingData = true;
  Map<String, String> _usersCache = {};
  Map<String, String> _groupNamesCache = {}; // Кэш имен групп

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAuxiliaryData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchPendingController.dispose();
    _searchActiveController.dispose();
    _searchHistoryController.dispose();
    super.dispose();
  }

  Future<void> _loadAuxiliaryData() async {
    try {
      var usersSnap = await FirebaseFirestore.instance.collection('users').get();
      for (var doc in usersSnap.docs) {
        var data = doc.data();
        String name = data['displayName'] ?? data['name'] ?? 'Unknown';
        _usersCache[doc.id] = name;
      }

      var groupsSnap = await FirebaseFirestore.instance.collection('items_groups').get();
      for (var doc in groupsSnap.docs) {
        _groupNamesCache[doc.id] = (doc.data())['name'] ?? doc.id;
      }

      if (mounted) {
        setState(() {
          _isLoadingData = false;
        });
      }
    } catch (e) {
      print("Error loading aux data: $e");
      if (mounted) {
        setState(() {
          _isLoadingData = false;
        });
      }
    }
  }

  // Перевод ID в имя
  String _getReadableGroupName(String rawGroup) {
    if (rawGroup.isEmpty) return 'לא הוגדר';
    if (rawGroup.length == 20 && !rawGroup.contains(' ')) {
      return _groupNamesCache[rawGroup] ?? 'לא הוגדר';
    }
    return rawGroup;
  }

  void _showLoading() {
    setState(() => _isProcessing = true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }

  void _hideLoading() {
    setState(() => _isProcessing = false);
    if (Navigator.canPop(context)) Navigator.pop(context);
  }

  Future<void> _showDateRangePicker(int tabIndex) async {
    final config = CalendarDatePicker2WithActionButtonsConfig(
      calendarType: CalendarDatePicker2Type.range,
      selectedDayHighlightColor: const Color(0xFF004D40),
      weekdayLabels: ['א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ש'],
      okButtonTextStyle: const TextStyle(color: Color(0xFF004D40), fontWeight: FontWeight.bold),
      cancelButtonTextStyle: const TextStyle(color: Colors.red),
    );

    List<DateTime?> currentValue = [];
    if (tabIndex == 0) currentValue = _pendingDates;
    else if (tabIndex == 1) currentValue = _activeDates;
    else if (tabIndex == 2) currentValue = _historyDates;

    final values = await showCalendarDatePicker2Dialog(
      context: context,
      config: config,
      dialogSize: const Size(325, 400),
      borderRadius: BorderRadius.circular(15),
      value: currentValue,
      dialogBackgroundColor: Colors.white,
    );

    if (values != null) {
      setState(() {
        if (tabIndex == 0) _pendingDates = values;
        else if (tabIndex == 1) _activeDates = values;
        else if (tabIndex == 2) _historyDates = values;
      });
    }
  }

  void _setQuickDate(int tabIndex, String filterType) {
    DateTime now = DateTime.now();
    DateTime start;
    DateTime end;

    if (filterType == 'today') {
      start = DateTime(now.year, now.month, now.day);
      end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    } else if (filterType == 'yesterday') {
      DateTime yesterday = now.subtract(const Duration(days: 1));
      start = DateTime(yesterday.year, yesterday.month, yesterday.day);
      end = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
    } else if (filterType == 'this_month') {
      start = DateTime(now.year, now.month, 1);
      end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    } else if (filterType == 'last_month') {
      start = DateTime(now.year, now.month - 1, 1);
      end = DateTime(now.year, now.month, 0, 23, 59, 59);
    } else if (filterType == 'this_year') {
      start = DateTime(now.year, 1, 1);
      end = DateTime(now.year + 1, 1, 0, 23, 59, 59);
    } else {
      return;
    }

    setState(() {
      if (tabIndex == 0) _pendingDates = [start, end];
      else if (tabIndex == 1) _activeDates = [start, end];
      else if (tabIndex == 2) _historyDates = [start, end];
    });
  }

  String _getPaymentMethodText(String method) {
    if (method == 'cash') return 'מזומן';
    if (method == 'check') return 'צ\'ק';
    return 'אשראי';
  }

  IconData _getPaymentMethodIcon(String method) {
    if (method == 'cash') return Icons.money;
    if (method == 'check') return Icons.receipt;
    return Icons.credit_card;
  }

  Future<void> _approveWithoutDeposit(String docId) async {
    TextEditingController reasonCtrl = TextEditingController();
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('אישור ללא פיקדון'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('האם לאשר לקיחת ציוד זה ללא חיוב פיקדון?'),
              const SizedBox(height: 15),
              TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'סיבה (אופציונלי)', border: OutlineInputBorder()), maxLines: 2)
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.orange), onPressed: () => Navigator.pop(ctx, true), child: const Text('אישור ללא פיקדון')),
          ],
        ),
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('Pikadon').doc(docId).update({
        'status': 'no_deposit',
        'reason': reasonCtrl.text.trim(),
        'actionDate': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _takeDeposit(String docId, double amount, String patientId, List pendingItems) async {
    String selectedMethod = 'card'; 

    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('אישור קבלת פיקדון'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('קבלת פיקדון בסך ₪$amount', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                const Text('בחר אמצעי תשלום:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 10),
                RadioListTile<String>(
                  title: Row(children: const [Icon(Icons.credit_card, color: Colors.blue), SizedBox(width: 10), Text('אשראי')]),
                  value: 'card',
                  groupValue: selectedMethod,
                  onChanged: (val) => setStateDialog(() => selectedMethod = val!),
                ),
                RadioListTile<String>(
                  title: Row(children: const [Icon(Icons.money, color: Colors.green), SizedBox(width: 10), Text('מזומן')]),
                  value: 'cash',
                  groupValue: selectedMethod,
                  onChanged: (val) => setStateDialog(() => selectedMethod = val!),
                ),
                RadioListTile<String>(
                  title: Row(children: const [Icon(Icons.receipt, color: Colors.purple), SizedBox(width: 10), Text('צ\'ק')]),
                  value: 'check',
                  groupValue: selectedMethod,
                  onChanged: (val) => setStateDialog(() => selectedMethod = val!),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)), 
                onPressed: () => Navigator.pop(ctx, true), 
                child: const Text('אישור ושמירה', style: TextStyle(fontSize: 16))
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm != true) return;

    _showLoading();
    try {
      var activeSnap = await FirebaseFirestore.instance.collection('Pikadon')
          .where('status', isEqualTo: 'active')
          .where('patientId', isEqualTo: patientId)
          .get();

      WriteBatch batch = FirebaseFirestore.instance.batch();

      if (activeSnap.docs.isNotEmpty) {
        var activeDoc = activeSnap.docs.first;
        var activeData = activeDoc.data() as Map<String, dynamic>;
        
        List activeItems = List.from(activeData['items'] ?? []);
        Set<String> existingIds = activeItems.map((e) => e['itemId'].toString()).toSet();
        List newItemsToMerge = [];
        double extraCost = 0.0;

        for (var item in pendingItems) {
          String itemId = item['itemId'].toString();
          if (!existingIds.contains(itemId)) {
            newItemsToMerge.add(item);
            extraCost += (item['cost'] ?? 0).toDouble();
            existingIds.add(itemId);
          }
        }
        
        activeItems.addAll(newItemsToMerge);
        double activeCost = (activeData['totalCost'] ?? 0).toDouble() + extraCost;

        batch.update(activeDoc.reference, {
          'items': activeItems,
          'totalCost': activeCost,
          'actionDate': FieldValue.serverTimestamp(),
          'paymentMethod': selectedMethod, 
        });
        
        batch.delete(FirebaseFirestore.instance.collection('Pikadon').doc(docId));
      } else {
        List cleanItems = [];
        double cleanCost = 0.0;
        Set<String> existingIds = {};

        for (var item in pendingItems) {
          String itemId = item['itemId'].toString();
          if (!existingIds.contains(itemId)) {
            cleanItems.add(item);
            cleanCost += (item['cost'] ?? 0).toDouble();
            existingIds.add(itemId);
          }
        }

        batch.update(FirebaseFirestore.instance.collection('Pikadon').doc(docId), {
          'status': 'active',
          'actionDate': FieldValue.serverTimestamp(),
          'items': cleanItems,
          'totalCost': cleanCost,
          'paymentMethod': selectedMethod, 
        });
      }

      await batch.commit();
    } finally {
      _hideLoading();
    }
  }

  Future<void> _handlePartialAction(DocumentSnapshot doc, String actionType, Map<String, String?> itemPatientMap) async {
    var data = doc.data() as Map<String, dynamic>;
    List items = List.from(data['items'] ?? []);
    if (items.isEmpty) return;

    String encryptedPatientId = data['patientId'];
    String paymentMethod = data['paymentMethod'] ?? 'card'; 

    List<bool> checked = List.generate(items.length, (index) {
      if (actionType == 'return') {
        String itemId = items[index]['itemId'].toString();
        bool isStillWithPatient = itemPatientMap[itemId] == encryptedPatientId;
        return !isStillWithPatient; 
      } else {
        return true; 
      }
    });

    String title = actionType == 'return' ? 'החזרת פיקדון' : 'חילוץ פיקדון (לא הוחזר)';
    Color color = actionType == 'return' ? Colors.teal : Colors.red;

    bool? proceed = await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(actionType == 'return' ? 'סמן את הפריטים עבורם מוחזר הפיקדון:' : 'סמן את הפריטים עבורם מחולט הפיקדון:'),
                  const Divider(),
                  ...List.generate(items.length, (i) {
                    String itemId = items[i]['itemId'].toString();
                    String rawGroup = items[i]['group'] ?? 'לא הוגדר';
                    String groupName = _getReadableGroupName(rawGroup); // ИЗВЛЕЧЕНИЕ
                    
                    bool isStillWithPatient = itemPatientMap[itemId] == encryptedPatientId;
                    
                    String statusText = isStillWithPatient ? " (עדיין אצל המטופל)" : " (הוחזר למלאי)";
                    Color statusColor = isStillWithPatient ? Colors.orange.shade800 : Colors.green.shade800;

                    return CheckboxListTile(
                      activeColor: color,
                      title: RichText(
                        text: TextSpan(
                          text: items[i]['itemName'] ?? 'לא ידוע',
                          style: const TextStyle(color: Colors.black, fontSize: 16),
                          children: [
                            TextSpan(text: statusText, style: TextStyle(color: statusColor, fontSize: 13, fontWeight: FontWeight.bold))
                          ]
                        )
                      ),
                      subtitle: Text("קבוצה: $groupName | ₪${items[i]['cost']} (ID: $itemId)"),
                      value: checked[i],
                      onChanged: (val) => setStateDialog(() => checked[i] = val!),
                    );
                  })
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: color),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('אישור'),
              ),
            ],
          ),
        ),
      )
    );

    if (proceed != true) return;

    List selectedItems = [];
    List remainingItems = [];
    double selectedCost = 0;
    double remainingCost = 0;

    for (int i = 0; i < items.length; i++) {
      if (checked[i]) {
        selectedItems.add(items[i]);
        selectedCost += (items[i]['cost'] ?? 0).toDouble();
      } else {
        remainingItems.add(items[i]);
        remainingCost += (items[i]['cost'] ?? 0).toDouble();
      }
    }

    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('לא נבחרו פריטים')));
      return;
    }

    List itemsToMarkBroken = [];
    String selectedReasonForInventory = 'broken'; 

    if (actionType == 'forfeit') {
      List<bool> brokenChecked = List.generate(selectedItems.length, (i) => true);
      
      bool? updateStatus = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setStateDialog) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('עדכון סטטוס למלאי', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('מה קרה לפריטים אלו? (הם יוצאו מהמלאי הפעיל)'),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      value: selectedReasonForInventory,
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'lost', child: Text('נאבד')),
                        DropdownMenuItem(value: 'broken', child: Text('תקול')),
                        DropdownMenuItem(value: 'other', child: Text('אחר')),
                      ],
                      onChanged: (val) => setStateDialog(() => selectedReasonForInventory = val!),
                    ),
                    const SizedBox(height: 15),
                    const Divider(),
                    const Text('בחר לאילו פריטים לעדכן סטטוס זה:', style: TextStyle(fontWeight: FontWeight.bold)),
                    ...List.generate(selectedItems.length, (i) {
                      String rawGroup = selectedItems[i]['group'] ?? 'לא הוגדר';
                      String groupName = _getReadableGroupName(rawGroup); // ИЗВЛЕЧЕНИЕ
                      
                      return CheckboxListTile(
                        activeColor: Colors.red,
                        title: Text(selectedItems[i]['itemName'] ?? 'לא ידוע'),
                        subtitle: Text("קבוצה: $groupName | ID: ${selectedItems[i]['itemId']}"),
                        value: brokenChecked[i],
                        onChanged: (val) => setStateDialog(() => brokenChecked[i] = val!),
                      );
                    })
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false), 
                  child: const Text('ביטול', style: TextStyle(fontSize: 16))
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('אישור מחיקה', style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        )
      );

      if (updateStatus != true) return; 
      
      for (int i = 0; i < selectedItems.length; i++) {
        if (brokenChecked[i]) itemsToMarkBroken.add(selectedItems[i]);
      }
    }

    bool processRemainingAsReturn = false;

    if (actionType == 'forfeit' && remainingItems.isNotEmpty) {
      bool? returnRest = await showDialog(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('שארית הפיקדון'),
            content: Text('האם הפיקדון עבור שאר הפריטים שלא חולטו (${remainingItems.length} פריטים) הוחזר למטופל במלואו?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('לא, השאר ב"פעילים"')),
              ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), onPressed: () => Navigator.pop(ctx, true), child: const Text('כן, הוחזר')),
            ],
          ),
        )
      );

      if (returnRest == null) return; 
      processRemainingAsReturn = returnRest;
    }

    _showLoading();
    try {
      WriteBatch batch = FirebaseFirestore.instance.batch();
      String patientId = data['patientId'];
      final uid = FirebaseAuth.instance.currentUser?.uid;

      void processPikadon(List groupItems, double groupCost, String statusType) {
        batch.set(FirebaseFirestore.instance.collection('Pikadon').doc(), {
          'patientId': patientId,
          'status': statusType,
          'totalCost': groupCost,
          'items': groupItems,
          'paymentMethod': paymentMethod, 
          'returnDate': FieldValue.serverTimestamp(),
        });
      }

      processPikadon(selectedItems, selectedCost, actionType == 'forfeit' ? 'forfeited' : 'returned');

      if (remainingItems.isEmpty) {
        batch.delete(doc.reference); 
      } else {
        if (actionType == 'forfeit' && processRemainingAsReturn) {
          processPikadon(remainingItems, remainingCost, 'returned');
          batch.delete(doc.reference);
        } else {
          batch.update(doc.reference, {
            'items': remainingItems,
            'totalCost': remainingCost,
          });
        }
      }

      if (itemsToMarkBroken.isNotEmpty) {
        Map<String, DocumentReference> itemRefs = {};
        for (var item in itemsToMarkBroken) {
          var snap = await FirebaseFirestore.instance.collection('items').where('ID', isEqualTo: item['itemId']).limit(1).get();
          if (snap.docs.isNotEmpty) itemRefs[item['itemId'].toString()] = snap.docs.first.reference;
        }

        for (var item in itemsToMarkBroken) {
          String idStr = item['itemId'].toString();
          if (itemRefs.containsKey(idStr)) {
            batch.update(itemRefs[idStr]!, {
              'status': selectedReasonForInventory, 
              'patientId': null,
              'dateDeleted': FieldValue.serverTimestamp(), 
            });
          }
          
          batch.set(FirebaseFirestore.instance.collection('History').doc(), {
             'action': selectedReasonForInventory, 
             'itemId': idStr,
             'itemName': item['itemName'] ?? 'Unknown',
             'group': item['group'],
             'patientId': patientId,
             'timestamp': FieldValue.serverTimestamp(),
             'staffUid': uid,
          });
        }
      }

      await batch.commit();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('הפעולה בוצעה בהצלחה'), backgroundColor: Colors.green));

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red));
    } finally {
      _hideLoading();
    }
  }

  // ================= EXCEL EXPORT FUNCTION (ACTIVE) =================
  Future<void> _exportActiveToExcel(List<QueryDocumentSnapshot> docs) async {
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("אין נתונים לייצוא")));
      return;
    }

    _showLoading();
    try {
      var excel = Excel.createExcel();
      Sheet sheetObject = excel['פיקדונות פעילים'];
      excel.setDefaultSheet('פיקדונות פעילים');

      sheetObject.appendRow([
        TextCellValue('סכום ב-₪ (Total Cost)'), 
        TextCellValue('אמצעי תשלום'), 
        TextCellValue('פריטים (Items)'),
        TextCellValue('מטופל (Patient ID)'),
        TextCellValue('תאריך לקיחה (Date)')     
      ]);

      for (var doc in docs) {
        var data = doc.data() as Map<String, dynamic>;
        
        String encryptedPid = data['patientId'] ?? '';
        String patientId = SecurityService.decryptID(encryptedPid);
        
        double totalCost = (data['totalCost'] ?? 0).toDouble();
        String paymentMethod = _getPaymentMethodText(data['paymentMethod'] ?? 'card');
        
        Timestamp? ts = data['actionDate'];
        String timeStr = ts != null ? DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate()) : '';
        
        List itemsList = data['items'] ?? [];
        String itemsStr = itemsList.map((i) {
          String grp = _getReadableGroupName(i['group'] ?? '');
          return "${i['itemName']} [קבוצה: $grp] (ID: ${i['itemId']})";
        }).join(' | ');

        sheetObject.appendRow([
          DoubleCellValue(totalCost),
          TextCellValue(paymentMethod),
          TextCellValue(itemsStr),
          TextCellValue(patientId),
          TextCellValue(timeStr),
        ]);
      }

      var bytes = excel.encode();
      if (bytes != null) {
        String fileName = 'Active_Pikadons_${DateFormat('dd_MM_yyyy_HHmm').format(DateTime.now())}.xlsx';
        if (kIsWeb) {
          final blob = html.Blob([bytes], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
          final url = html.Url.createObjectUrlFromBlob(blob);
          final anchor = html.AnchorElement(href: url)
            ..setAttribute("download", fileName)
            ..click();
          html.Url.revokeObjectUrl(url);
        }
      }
    } catch (e) {
      print("Excel Export Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('שגיאה ביצירת Excel: $e'), backgroundColor: Colors.red));
    } finally {
      _hideLoading();
    }
  }

  // ================= EXCEL EXPORT FUNCTION (HISTORY) =================
  Future<void> _exportHistoryToExcel(List<Map<String, dynamic>> events) async {
    if (events.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("אין נתונים לייצוא")));
      return;
    }

    _showLoading();
    try {
      var excel = Excel.createExcel();
      Sheet sheetObject = excel['היסטוריה'];
      excel.setDefaultSheet('היסטוריה');

      sheetObject.appendRow([
        TextCellValue('סכום ב-₪ (Amount)'),      
        TextCellValue('סיבה/הערה (Reason)'),
        TextCellValue('אמצעי תשלום'), 
        TextCellValue('פעולה (Action)'),
        TextCellValue('פריטים (Items)'),
        TextCellValue('מטופל (Patient ID)'),
        TextCellValue('תאריך ושעה (Date)')       
      ]);

      for (var event in events) {
        var data = event['data'] as Map<String, dynamic>;
        String eventType = event['type'];

        String encryptedPid = data['patientId'] ?? '';
        String patientId = SecurityService.decryptID(encryptedPid);
        
        List itemsList = data['items'] ?? [];
        String itemsStr = itemsList.map((i) {
          String grp = _getReadableGroupName(i['group'] ?? '');
          return "${i['itemName']} [קבוצה: $grp] (ID: ${i['itemId']})";
        }).join(' | ');
        
        String reason = data['reason'] ?? '';
        double cost = eventType == 'no_deposit' ? 0.0 : (data['totalCost'] ?? 0).toDouble();
        String paymentMethod = eventType == 'no_deposit' ? 'ללא' : _getPaymentMethodText(data['paymentMethod'] ?? 'card');
        
        Timestamp ts = event['date'];
        String timeStr = DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate());

        String actionText = '';
        if (eventType == 'taken') actionText = 'נלקח (פעיל)';
        else if (eventType == 'returned') actionText = 'הוחזר';
        else if (eventType == 'no_deposit') actionText = 'ללא פיקדון';
        else if (eventType == 'forfeited') actionText = 'חולט';

        sheetObject.appendRow([
          DoubleCellValue(cost),
          TextCellValue(reason),
          TextCellValue(paymentMethod),
          TextCellValue(actionText),
          TextCellValue(itemsStr),
          TextCellValue(patientId),
          TextCellValue(timeStr),
        ]);
      }

      var bytes = excel.encode();
      if (bytes != null) {
        String fileName = 'History_Pikadons_${DateFormat('dd_MM_yyyy_HHmm').format(DateTime.now())}.xlsx';
        if (kIsWeb) {
          final blob = html.Blob([bytes], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
          final url = html.Url.createObjectUrlFromBlob(blob);
          final anchor = html.AnchorElement(href: url)
            ..setAttribute("download", fileName)
            ..click();
          html.Url.revokeObjectUrl(url);
        }
      }
    } catch (e) {
      print("Excel Export Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('שגיאה ביצירת Excel: $e'), backgroundColor: Colors.red));
    } finally {
      _hideLoading();
    }
  }


  // ================= ФУНКЦИЯ ГЕНЕРАЦИИ И СКАЧИВАНИЯ PDF =================
  Future<void> _generateAndDownloadPdf(String patientId, List items, double totalCost, String staffName) async {
    showDialog(
      context: context, 
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: Colors.white))
    );

    try {
      final pdf = pw.Document();
      final font = await PdfGoogleFonts.rubikRegular();
      final fontBold = await PdfGoogleFonts.rubikMedium();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          theme: pw.ThemeData(
            defaultTextStyle: pw.TextStyle(font: font, fontSize: 14),
          ),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: pw.Text('בית חולים שיקומי רעות', style: pw.TextStyle(font: fontBold, fontSize: 20, color: PdfColors.teal)),
                ),
                pw.SizedBox(height: 10),
                pw.Center(
                  child: pw.Text('טופס השאלת ציוד והתחייבות לפיקדון', style: pw.TextStyle(font: fontBold, fontSize: 24)),
                ),
                pw.SizedBox(height: 30),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('תאריך: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}'),
                    pw.Text('מספר מטופל: $patientId', style: pw.TextStyle(font: fontBold, fontSize: 16)),
                  ]
                ),
                pw.SizedBox(height: 10),
                pw.Text('נמסר ע"י (איש צוות): $staffName', style: pw.TextStyle(font: font, fontSize: 14)),
                pw.SizedBox(height: 15),
                pw.Divider(),
                pw.SizedBox(height: 15),
                pw.Text('אני החתום/ה מטה מאשר/ת בזאת כי קיבלתי לידי את הציוד הרפואי המפורט מטה, המהווה רכוש של בית החולים רעות.'),
                pw.SizedBox(height: 20),
                pw.Text('פירוט הציוד שהועבר לידיי:', style: pw.TextStyle(font: fontBold, decoration: pw.TextDecoration.underline)),
                pw.SizedBox(height: 10),
                ...items.map((item) {
                  String name = item['itemName'] ?? 'לא ידוע';
                  String group = _getReadableGroupName(item['group'] ?? ''); // ИЗВЛЕЧЕНИЕ
                  String id = item['itemId'] ?? '';
                  String cost = item['cost'].toString();
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 6),
                    child: pw.Text('• $name [$group]  (מזהה: $id)  -  שווי: ₪$cost'),
                  );
                }).toList(),
                pw.SizedBox(height: 20),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey200,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5))
                  ),
                  child: pw.Text('סך הכל דמי פיקדון להפקדה: ₪$totalCost', style: pw.TextStyle(font: fontBold, fontSize: 18)),
                ),
                pw.SizedBox(height: 20),
                pw.Divider(),
                pw.SizedBox(height: 20),
                pw.Text('תנאי ההשאלה והפיקדון:', style: pw.TextStyle(font: fontBold, fontSize: 16)),
                pw.SizedBox(height: 10),
                pw.Text('1. הציוד נמסר לי כהשאלה לתקופת הטיפול בלבד.'),
                pw.SizedBox(height: 5),
                pw.Text('2. אני מתחייב/ת לשמור על הציוד במצב תקין ולהחזירו לבית החולים עם סיום השימוש בו.'),
                pw.SizedBox(height: 5),
                pw.Text('3. ידוע לי כי דמי הפיקדון יוחזרו אליי במלואם רק עם החזרת הציוד בשלמותו.'),
                pw.SizedBox(height: 5),
                pw.Text('4. במקרה של אובדן או נזק משמעותי לציוד, בית החולים רשאי לחלט את הפיקדון.'),
                pw.Spacer(),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('_______________________'),
                        pw.SizedBox(height: 5),
                        pw.Text('חתימת המטופל', style: pw.TextStyle(font: fontBold)),
                      ]
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('_______________________'),
                        pw.SizedBox(height: 5),
                        pw.Text('חתימת בית חולים', style: pw.TextStyle(font: fontBold)), 
                      ]
                    )
                  ]
                ),
                pw.SizedBox(height: 40),
              ],
            );
          },
        ),
      );

      final bytes = await pdf.save();

      if (mounted) Navigator.pop(context); 

      String fileName = 'Tofes_Pikadon.pdf';

      if (kIsWeb) {
        final blob = html.Blob([bytes], 'application/pdf');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute("download", fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      }

    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('שגיאה ביצירת PDF: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFE0F2F1),
        appBar: AppBar(
          title: const Text('ניהול פיקדונות'),
          backgroundColor: const Color(0xFF004D40),
          foregroundColor: Colors.white,
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(text: 'הודעות חדשות', icon: Icon(Icons.notifications_active)),
              Tab(text: 'פיקדונות פעילים', icon: Icon(Icons.account_balance_wallet)),
              Tab(text: 'היסטוריית פיקדונות', icon: Icon(Icons.history)),
            ],
          ),
        ),
        body: _isLoadingData 
        ? const Center(child: CircularProgressIndicator()) 
        : TabBarView(
            controller: _tabController,
            children: [
              _buildPendingTab(),
              _buildActiveTab(),
              _buildHistoryTab(),
            ],
          ),
      ),
    );
  }

  // ================= TAB 1: PENDING =================
  Widget _buildPendingTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('Pikadon')
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        var docs = snapshot.data!.docs;

        var filteredDocs = docs.where((doc) {
          var data = doc.data() as Map<String, dynamic>;
          if (_pendingSearchQuery.isNotEmpty) {
            String pid = SecurityService.decryptID(data['patientId'] ?? '');
            if (!pid.contains(_pendingSearchQuery)) return false;
          }
          if (_pendingDates.isNotEmpty && _pendingDates[0] != null) {
            Timestamp? ts = data['createdAt'];
            if (ts == null) return false;
            DateTime date = ts.toDate();
            DateTime startDay = DateTime(_pendingDates[0]!.year, _pendingDates[0]!.month, _pendingDates[0]!.day);
            if (date.isBefore(startDay)) return false;
            if (_pendingDates.length > 1 && _pendingDates[1] != null) {
              DateTime endDay = DateTime(_pendingDates[1]!.year, _pendingDates[1]!.month, _pendingDates[1]!.day, 23, 59, 59);
              if (date.isAfter(endDay)) return false;
            }
          }
          return true;
        }).toList();

        return Column(
          children: [
            _buildSearchBar(_searchPendingController, _pendingDates, 0),
            
            Expanded(
              child: filteredDocs.isEmpty 
              ? const Center(child: Text("אין הודעות חדשות", style: TextStyle(fontSize: 20, color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 80),
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) {
                    var doc = filteredDocs[index];
                    var data = doc.data() as Map<String, dynamic>;
                    
                    String encryptedPid = data['patientId'] ?? '';
                    String patientId = SecurityService.decryptID(encryptedPid);
                    double totalCost = (data['totalCost'] ?? 0).toDouble();
                    List items = data['items'] ?? [];
                    Timestamp? ts = data['createdAt'];
                    String timeStr = ts != null ? DateFormat('HH:mm  dd/MM/yy').format(ts.toDate()) : '';

                    String staffUid = data['staffUid'] ?? '';
                    String staffName = _usersCache[staffUid] ?? 'לא ידוע';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 15),
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.orange, width: 2)),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      SelectableText("מטופל: $patientId", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                      SelectableText(timeStr, style: const TextStyle(color: Colors.grey)),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  SelectableText("נמסר ע\"י: $staffName", style: const TextStyle(fontSize: 14, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                                  const Divider(),
                                  const Text("פריטים שנלקחו:", style: TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 5),
                                  ...items.map((item) {
                                    String grp = _getReadableGroupName(item['group'] ?? ''); // ИЗВЛЕЧЕНИЕ
                                    return SelectableText("• ${item['itemName'] ?? 'לא ידוע'} [קבוצה: $grp] (ID: ${item['itemId']}) - ₪${item['cost']}");
                                  }).toList(),
                                  const SizedBox(height: 15),
                                  SelectableText("סך הכל פיקדון נדרש: ₪$totalCost", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red)),
                                  const SizedBox(height: 20),
                                  
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue[700],
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                                    ),
                                    onPressed: () => _generateAndDownloadPdf(patientId, items, totalCost, staffName),
                                    icon: const Icon(Icons.picture_as_pdf),
                                    label: const Text("הורד טופס לחתימה", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 30),
                            
                            Container(
                              width: 160, 
                              padding: const EdgeInsets.only(top: 10),
                              child: Column(
                                children: [
                                  SizedBox(
                                    width: double.infinity,
                                    height: 45, 
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                                      ),
                                      onPressed: () => _takeDeposit(doc.id, totalCost, encryptedPid, items), 
                                      icon: const Icon(Icons.check_circle, size: 20),
                                      label: const Text("פיקדון נלקח"),
                                    ),
                                  ),
                                  const SizedBox(height: 15),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 45, 
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.orange[800], 
                                        side: BorderSide(color: Colors.orange[800]!, width: 2),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                                      ),
                                      onPressed: () => _approveWithoutDeposit(doc.id),
                                      icon: const Icon(Icons.money_off, size: 20),
                                      label: const Text("ללא פיקדון"),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                    );
                  },
              ),
            )
          ],
        );
      },
    );
  }

  Widget _buildSumCol(String title, double amount, Color color, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey[600]),
            const SizedBox(width: 5),
            Text(title, style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 5),
        SelectableText("₪${amount.toStringAsFixed(0)}", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  // ================= TAB 2: ACTIVE =================
  Widget _buildActiveTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('Pikadon')
          .where('status', isEqualTo: 'active')
          .orderBy('actionDate', descending: true)
          .snapshots(),
      builder: (context, pikadonSnapshot) {
        if (!pikadonSnapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('items').snapshots(),
          builder: (context, itemsSnapshot) {
            if (!itemsSnapshot.hasData) return const Center(child: CircularProgressIndicator());

            Map<String, String?> itemPatientMap = {};
            for(var itemDoc in itemsSnapshot.data!.docs) {
              var d = itemDoc.data() as Map<String, dynamic>;
              itemPatientMap[d['ID'].toString()] = d['patientId'];
            }

            var docs = pikadonSnapshot.data!.docs;
            
            double totalActiveMoney = 0;
            double totalCash = 0;
            double totalCard = 0;
            double totalCheck = 0;
            
            for(var doc in docs) {
              var data = doc.data() as Map<String, dynamic>;
              double cost = (data['totalCost'] ?? 0).toDouble();
              String method = data['paymentMethod'] ?? 'card'; 

              totalActiveMoney += cost;
              if (method == 'cash') totalCash += cost;
              else if (method == 'check') totalCheck += cost;
              else totalCard += cost;
            }

            var filteredDocs = docs.where((doc) {
              var data = doc.data() as Map<String, dynamic>;
              if (_activeSearchQuery.isNotEmpty) {
                String pid = SecurityService.decryptID(data['patientId'] ?? '');
                if (!pid.contains(_activeSearchQuery)) return false;
              }
              if (_activeDates.isNotEmpty && _activeDates[0] != null) {
                Timestamp? ts = data['actionDate'];
                if (ts == null) return false;
                DateTime date = ts.toDate();
                DateTime startDay = DateTime(_activeDates[0]!.year, _activeDates[0]!.month, _activeDates[0]!.day);
                if (date.isBefore(startDay)) return false;
                if (_activeDates.length > 1 && _activeDates[1] != null) {
                  DateTime endDay = DateTime(_activeDates[1]!.year, _activeDates[1]!.month, _activeDates[1]!.day, 23, 59, 59);
                  if (date.isAfter(endDay)) return false;
                }
              }
              return true;
            }).toList();

            return Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  color: Colors.white,
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildSumCol("סה\"כ בקופה", totalActiveMoney, Colors.green, Icons.account_balance_wallet),
                            _buildSumCol("אשראי", totalCard, Colors.blue, Icons.credit_card),
                            _buildSumCol("מזומן", totalCash, Colors.orange, Icons.money),
                            _buildSumCol("צ'ק", totalCheck, Colors.purple, Icons.receipt),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15)
                        ),
                        onPressed: () => _exportActiveToExcel(filteredDocs),
                        icon: const Icon(Icons.table_view, color: Colors.white),
                        label: const Text("ייצא לאקסל", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                ),
                const Divider(height: 1),
                
                _buildSearchBar(_searchActiveController, _activeDates, 1),
                
                Expanded(
                  child: filteredDocs.isEmpty 
                  ? const Center(child: Text("לא נמצאו פיקדונות פעילים"))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 80),
                      itemCount: filteredDocs.length,
                      itemBuilder: (context, index) {
                        var doc = filteredDocs[index];
                        var data = doc.data() as Map<String, dynamic>;
                        
                        String encryptedPid = data['patientId'] ?? '';
                        String patientId = SecurityService.decryptID(encryptedPid);
                        double totalCost = (data['totalCost'] ?? 0).toDouble();
                        List items = data['items'] ?? [];
                        Timestamp? ts = data['actionDate'];
                        String timeStr = ts != null ? DateFormat('dd/MM/yyyy').format(ts.toDate()) : '';
                        
                        String pMethod = data['paymentMethod'] ?? 'card';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(15.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(backgroundColor: Colors.green[100], child: const Icon(Icons.account_balance_wallet, color: Colors.green)),
                                    const SizedBox(width: 15),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          SelectableText("מטופל: $patientId", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                          SelectableText("תאריך לקיחה: $timeStr", style: const TextStyle(color: Colors.grey)),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        SelectableText("₪$totalCost", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green)),
                                        Row(
                                          children: [
                                            Icon(_getPaymentMethodIcon(pMethod), size: 14, color: Colors.grey[700]),
                                            const SizedBox(width: 4),
                                            Text(_getPaymentMethodText(pMethod), style: TextStyle(fontSize: 14, color: Colors.grey[700], fontWeight: FontWeight.bold)),
                                          ],
                                        )
                                      ],
                                    ),
                                  ],
                                ),
                                const Divider(),
                                const Text("סטטוס פריטים נוכחי:", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: items.map((i) {
                                    String itemId = i['itemId'].toString();
                                    String rawGroup = i['group'] ?? 'לא הוגדר';
                                    String groupName = _getReadableGroupName(rawGroup); // ИЗВЛЕЧЕНИЕ
                                    bool isStillWithPatient = itemPatientMap[itemId] == encryptedPid;
                                    
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isStillWithPatient ? Colors.orange.shade50 : Colors.green.shade50,
                                        border: Border.all(color: isStillWithPatient ? Colors.orange.shade300 : Colors.green.shade300),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(isStillWithPatient ? Icons.person : Icons.check_circle, size: 16, color: isStillWithPatient ? Colors.orange.shade700 : Colors.green.shade700),
                                          const SizedBox(width: 4),
                                          Text("${i['itemName']} [$groupName] (ID: $itemId)", style: TextStyle(fontSize: 13, color: isStillWithPatient ? Colors.orange.shade900 : Colors.green.shade900, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 15),
                                
                                Row(
                                  children: [
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                                      onPressed: () => _handlePartialAction(doc, 'return', itemPatientMap),
                                      icon: const Icon(Icons.undo),
                                      label: const Text("החזר פיקדון"),
                                    ),
                                    const SizedBox(width: 15),
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red,
                                        side: const BorderSide(color: Colors.red),
                                      ),
                                      onPressed: () => _handlePartialAction(doc, 'forfeit', itemPatientMap),
                                      icon: const Icon(Icons.gavel),
                                      label: const Text("לא הוחזר / חולט"),
                                    ),
                                  ],
                                )
                              ],
                            ),
                          ),
                        );
                      },
                  ),
                )
              ],
            );
          }
        );
      },
    );
  }

  // ================= TAB 3: HISTORY =================
  Widget _buildHistoryTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('Pikadon')
          .where('status', whereIn: ['active', 'returned', 'no_deposit', 'forfeited'])
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        List<Map<String, dynamic>> allEvents = [];
        
        for (var doc in snapshot.data!.docs) {
          var data = doc.data() as Map<String, dynamic>;
          String status = data['status'];

          if (data['actionDate'] != null && (status == 'active' || status == 'no_deposit')) {
            allEvents.add({
              'type': status == 'no_deposit' ? 'no_deposit' : 'taken',
              'date': data['actionDate'],
              'data': data,
            });
          }

          if ((status == 'returned' || status == 'forfeited') && data['returnDate'] != null) {
            allEvents.add({
              'type': status,
              'date': data['returnDate'],
              'data': data,
            });
          }
        }

        allEvents.sort((a, b) {
           Timestamp tsA = a['date'];
           Timestamp tsB = b['date'];
           return tsB.compareTo(tsA);
        });

        var filteredEvents = allEvents.where((event) {
          var data = event['data'];
          if (_historySearchQuery.isNotEmpty) {
            String pid = SecurityService.decryptID(data['patientId'] ?? '');
            if (!pid.contains(_historySearchQuery)) return false;
          }
          if (_historyTypeFilter != 'all' && event['type'] != _historyTypeFilter) {
             return false;
          }
          if (_historyDates.isNotEmpty && _historyDates[0] != null) {
            DateTime date = (event['date'] as Timestamp).toDate();
            DateTime startDay = DateTime(_historyDates[0]!.year, _historyDates[0]!.month, _historyDates[0]!.day);
            if (date.isBefore(startDay)) return false;
            
            if (_historyDates.length > 1 && _historyDates[1] != null) {
              DateTime endDay = DateTime(_historyDates[1]!.year, _historyDates[1]!.month, _historyDates[1]!.day, 23, 59, 59);
              if (date.isAfter(endDay)) return false;
            }
          }
          return true;
        }).toList();

        return Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("היסטוריית פעולות:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15)
                    ),
                    onPressed: () => _exportHistoryToExcel(filteredEvents),
                    icon: const Icon(Icons.table_view, color: Colors.white),
                    label: const Text("ייצא לאקסל", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            ),
            const Divider(height: 1),

            _buildSearchBar(_searchHistoryController, _historyDates, 2),
            
            Expanded(
              child: filteredEvents.isEmpty 
              ? const Center(child: Text("לא נמצאה היסטוריה"))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 80),
                  itemCount: filteredEvents.length,
                  itemBuilder: (context, index) {
                    var event = filteredEvents[index];
                    var data = event['data'] as Map<String, dynamic>;
                    String eventType = event['type']; 
                    
                    String patientId = SecurityService.decryptID(data['patientId'] ?? '');
                    List items = data['items'] ?? [];
                    String reason = data['reason'] ?? '';
                    String pMethod = data['paymentMethod'] ?? 'card';
                    
                    double cost = eventType == 'no_deposit' ? 0 : (data['totalCost'] ?? 0).toDouble();
                    
                    Timestamp ts = event['date'];
                    String timeStr = DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate());

                    String actionText = '';
                    Color actionColor = Colors.grey;
                    
                    if (eventType == 'taken') {
                      actionText = 'נלקח (פעיל)';
                      actionColor = Colors.blue;
                    } else if (eventType == 'returned') {
                      actionText = 'הוחזר';
                      actionColor = Colors.teal;
                    } else if (eventType == 'no_deposit') {
                      actionText = 'ללא פיקדון';
                      actionColor = Colors.orange;
                    } else if (eventType == 'forfeited') {
                      actionText = 'חולט';
                      actionColor = Colors.red;
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Row(
                          children: [
                            Expanded(flex: 1, child: SelectableText(timeStr)),
                            Expanded(
                              flex: 3, 
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectableText("מטופל: $patientId", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  SelectableText("פריטים: ${items.map((i) {
                                    String grp = _getReadableGroupName(i['group'] ?? ''); // ИЗВЛЕЧЕНИЕ
                                    return "${i['itemName'] ?? 'לא ידוע'} [קבוצה: $grp] (ID: ${i['itemId']})";
                                  }).join(' | ')}", style: const TextStyle(color: Colors.grey)),
                                  if (eventType == 'no_deposit' && reason.isNotEmpty) 
                                     SelectableText("סיבה: $reason", style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                                ],
                              )
                            ),
                            Expanded(
                              flex: 1, 
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                                decoration: BoxDecoration(color: actionColor.withOpacity(0.2), borderRadius: BorderRadius.circular(5)),
                                child: SelectableText(actionText, textAlign: TextAlign.center, style: TextStyle(color: actionColor, fontWeight: FontWeight.bold)),
                              )
                            ),
                            Expanded(
                              flex: 1, 
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SelectableText("₪$cost", textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  if (eventType != 'no_deposit')
                                    Text(_getPaymentMethodText(pMethod), style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold))
                                ],
                              )
                            ),
                          ],
                        ),
                      ),
                    );
                  },
              ),
            )
          ],
        );
      },
    );
  }

  // --- SEARCH BAR WITH QUICK FILTERS ---
  Widget _buildQuickDateChip(String label, String type, int tabIndex) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal.shade50,
        side: BorderSide(color: Colors.teal.shade200),
        onPressed: () => _setQuickDate(tabIndex, type),
      ),
    );
  }

  Widget _buildSearchBar(TextEditingController controller, List<DateTime?> dates, int tabIndex) {
    String dateBtnText = "בחר תאריכים";
    if (dates.isNotEmpty && dates[0] != null) {
      dateBtnText = DateFormat('dd/MM/yy').format(dates[0]!);
      if (dates.length > 1 && dates[1] != null) dateBtnText += " - ${DateFormat('dd/MM/yy').format(dates[1]!)}";
    }

    return Container(
      padding: const EdgeInsets.all(15),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'חפש מספר מטופל',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (val) => setState(() {
                    if (tabIndex == 0) _pendingSearchQuery = val.trim();
                    else if (tabIndex == 1) _activeSearchQuery = val.trim();
                    else if (tabIndex == 2) _historySearchQuery = val.trim();
                  }),
                ),
              ),
              const SizedBox(width: 10),
              
              if (tabIndex == 2) ...[
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<String>(
                    value: _historyTypeFilter,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('כל הפעולות')),
                      DropdownMenuItem(value: 'taken', child: Text('לקיחות')),
                      DropdownMenuItem(value: 'returned', child: Text('החזרות')),
                      DropdownMenuItem(value: 'no_deposit', child: Text('ללא פיקדון')),
                      DropdownMenuItem(value: 'forfeited', child: Text('חולט (לא הוחזר)')),
                    ],
                    onChanged: (val) => setState(() => _historyTypeFilter = val!),
                  ),
                ),
                const SizedBox(width: 10),
              ],

              Expanded(
                flex: 1,
                child: OutlinedButton.icon(
                  onPressed: () => _showDateRangePicker(tabIndex),
                  icon: const Icon(Icons.calendar_today),
                  label: Text(dateBtnText, overflow: TextOverflow.ellipsis),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
              if (dates.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.red),
                  onPressed: () => setState(() {
                    if (tabIndex == 0) _pendingDates = [];
                    else if (tabIndex == 1) _activeDates = [];
                    else if (tabIndex == 2) _historyDates = [];
                  }),
                )
            ],
          ),
          const SizedBox(height: 10),
          
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text("סינון מהיר: ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(width: 10),
                _buildQuickDateChip("היום", 'today', tabIndex),
                _buildQuickDateChip("אתמול", 'yesterday', tabIndex),
                _buildQuickDateChip("החודש", 'this_month', tabIndex),
                _buildQuickDateChip("חודש שעבר", 'last_month', tabIndex),
                _buildQuickDateChip("השנה", 'this_year', tabIndex),
              ],
            ),
          )
        ],
      ),
    );
  }
}