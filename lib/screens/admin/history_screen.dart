import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:calendar_date_picker2/calendar_date_picker2.dart';
import '../../utils/helpers.dart';
import '../../services/security_service.dart';

/// Screen displaying the complete audit log of all equipment actions (take, return, lost, etc.).
/// Provides advanced filtering capabilities by date, action type, user, patient, and SKU.
class HistoryScreen extends StatefulWidget {
  // NEW: Add companyId parameter
  final String companyId; 

  const HistoryScreen({super.key, required this.companyId}); // UPDATED

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();

  bool _isLoadingData = true;
  
  // --- CACHES ---
  Map<String, Map<String, dynamic>> _itemsCache = {};
  Map<String, String> _usersCache = {};
  Map<String, String> _groupNamesCache = {}; 
  
  // --- FILTERS ---
  String _searchQuery = "";
  List<DateTime?> _rangeDatePickerValueWithDefaultValue = [];
  String _actionFilter = 'all'; 
  String _subActionFilter = 'all';

  Map<String, dynamic>? _filterGroup;
  Map<String, dynamic>? _filterSku;
  int _filterSelectorKey = 0; 

  @override
  void initState() {
    super.initState();
    _loadAuxiliaryData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Fetches users, groups, and items from Firestore to populate local caches.
  /// This prevents excessive database reads during list rendering and filtering.
  Future<void> _loadAuxiliaryData() async {
    try {
      // 1. Load users for displaying staff names instead of UIDs
      // NEW: Filter users by company_id so we don't load users from other companies
      var usersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('company_id', isEqualTo: widget.companyId)
          .get();
          
      for (var doc in usersSnap.docs) {
        var data = doc.data();
        String name = data['displayName']?.toString() ?? data['name']?.toString() ?? 'Unknown';
        _usersCache[doc.id] = name;
      }

      // NEW: Define the specific company reference
      var companyRef = FirebaseFirestore.instance.collection('companies').doc(widget.companyId);

      // 2. Load group names to resolve GroupIDs
      var groupsSnap = await companyRef.collection('items_groups').get();
      for (var doc in groupsSnap.docs) {
        _groupNamesCache[doc.id] = (doc.data())['name']?.toString() ?? doc.id;
      }

      // 3. Load items to resolve item details based on ID
      var itemsSnap = await companyRef.collection('items').get();
      for (var doc in itemsSnap.docs) {
        var data = doc.data();
        String id = data['ID']?.toString() ?? doc.id;
        _itemsCache[id] = {
          'name': data['name']?.toString() ?? 'Unknown Item',
          'group': data['group']?.toString() ?? data['GroupID']?.toString(),
          'sku': data['SKU_ID']?.toString(),
        };
      }

      if (mounted) setState(() => _isLoadingData = false);
    } catch (e) {
      debugPrint("Error loading aux data: $e");
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  /// Helper to convert a raw group string (either an ID or a direct name) 
  /// into a human-readable group name using the cache.
  String _getReadableGroupName(String rawGroup) {
    if (rawGroup.isEmpty) return 'לא הוגדר';
    // If the string looks like a standard Firestore 20-character ID, attempt lookup
    if (rawGroup.length == 20 && !rawGroup.contains(' ')) {
      return _groupNamesCache[rawGroup] ?? 'לא הוגדר';
    }
    return rawGroup;
  }

  /// Opens the date range picker dialog to filter history by dates.
  Future<void> _showDateRangePicker() async {
    final values = await showCalendarDatePicker2Dialog(
      context: context,
      config: CalendarDatePicker2WithActionButtonsConfig(
        calendarType: CalendarDatePicker2Type.range,
        selectedDayHighlightColor: const Color(0xFF004D40),
        weekdayLabels: ['א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ש'],
        okButtonTextStyle: const TextStyle(color: Color(0xFF004D40), fontWeight: FontWeight.bold),
        cancelButtonTextStyle: const TextStyle(color: Colors.red),
        controlsTextStyle: const TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.bold),
      ),
      dialogSize: const Size(325, 400),
      borderRadius: BorderRadius.circular(15),
      value: _rangeDatePickerValueWithDefaultValue,
      dialogBackgroundColor: Colors.white,
    );

    if (values != null) setState(() => _rangeDatePickerValueWithDefaultValue = values);
  }

  /// Clears the selected date range.
  void _resetDates() => setState(() => _rangeDatePickerValueWithDefaultValue = []);

  /// Completely resets all active search parameters, dates, and dropdown filters.
  void _clearAllFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = "";
      _actionFilter = 'all';
      _subActionFilter = 'all';
      _filterGroup = null;
      _filterSku = null;
      _rangeDatePickerValueWithDefaultValue = [];
      _filterSelectorKey++;
    });
  }

  /// Generates a visual badge to represent the specific action performed on the item.
  Widget _buildActionBadge(String action) {
    action = action.toLowerCase();
    
    Color bgColor = Colors.grey.shade100;
    Color borderColor = Colors.grey;
    Color textColor = Colors.black87;
    String textStr = action;

    if (action.contains('take') || action.contains('borrow')) {
      bgColor = Colors.orange.shade50; borderColor = Colors.orange; textColor = Colors.orange.shade900; textStr = 'לקיחה';
    } else if (action.contains('return') || action.contains('returned')) {
      bgColor = Colors.green.shade50; borderColor = Colors.green; textColor = Colors.green.shade900; textStr = 'החזרה';
    } else if (action == 'sold') {
      bgColor = Colors.purple.shade50; borderColor = Colors.purple; textColor = Colors.purple.shade900; textStr = 'למחסן מכירה';
    } else if (action == 'lost') {
      bgColor = Colors.red.shade50; borderColor = Colors.red; textColor = Colors.red.shade900; textStr = 'נאבד';
    } else if (action == 'broken') {
      bgColor = Colors.red.shade50; borderColor = Colors.red; textColor = Colors.red.shade900; textStr = 'תקול';
    } else if (action == 'other') {
      bgColor = Colors.red.shade50; borderColor = Colors.red; textColor = Colors.red.shade900; textStr = 'אחר (נמחק)';
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(color: bgColor, border: Border.all(color: borderColor, width: 1.5), borderRadius: BorderRadius.circular(8)),
      alignment: Alignment.center,
      child: SelectableText(textStr, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textColor), textAlign: TextAlign.center),
    );
  }

  // NEW: Update paths to be specific to the company
  Stream<QuerySnapshot> _getGroupsStream() => FirebaseFirestore.instance
      .collection('companies')
      .doc(widget.companyId)
      .collection('items_groups')
      .snapshots();

  Stream<QuerySnapshot> _getSkusStream(String groupId) => FirebaseFirestore.instance
      .collection('companies')
      .doc(widget.companyId)
      .collection('SKU')
      .where('GroupID', isEqualTo: groupId)
      .snapshots();
  /// Builds an autocomplete dropdown selector for filtering groups or SKUs.
  Widget _buildFilterSelector({required String label, required Stream<QuerySnapshot> stream, required Function(Map<String, dynamic>?) onSelected, required String? selectedName}) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        List<Map<String, dynamic>> options = snapshot.data!.docs.map((doc) => {'id': doc.id, 'name': (doc.data() as Map)['name']?.toString() ?? doc.id}).toList();
        return LayoutBuilder(builder: (context, constraints) => Autocomplete<Map<String, dynamic>>(
          key: ValueKey("filter_sel_$_filterSelectorKey"),
          optionsBuilder: (v) {
            var list = v.text.isEmpty ? options : options.where((o) => o['name'].toString().toLowerCase().contains(v.text.toLowerCase())).toList();
            list.insert(0, {'id': 'ALL', 'name': '⭐️ הכל'});
            return list;
          },
          displayStringForOption: (o) => o['id'] == 'ALL' ? '' : o['name'],
          onSelected: (s) => onSelected(s['id'] == 'ALL' ? null : s),
          fieldViewBuilder: (ctx, ctrl, focus, submit) {
            if (selectedName != null && ctrl.text.isEmpty) ctrl.text = selectedName;
            return TextField(controller: ctrl, focusNode: focus, onTap: () => ctrl.clear(), style: const TextStyle(fontSize: 16), decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true, suffixIcon: const Icon(Icons.arrow_drop_down)));
          },
          optionsViewBuilder: (ctx, onSel, opts) => Align(alignment: Alignment.topRight, child: Material(elevation: 4, child: SizedBox(width: constraints.maxWidth, height: 250, child: ListView.builder(padding: EdgeInsets.zero, itemCount: opts.length, itemBuilder: (ctx, i) {
            final o = opts.elementAt(i);
            return ListTile(title: Text(o['name'], style: o['id'] == 'ALL' ? const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue) : null), onTap: () => onSel(o));
          })))),
        ));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const TextStyle bigTextStyle = TextStyle(fontSize: 16, color: Colors.black87);
    const TextStyle bigBoldStyle = TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87);

    String dateButtonText = "בחר תאריכים";
    bool hasDate = false;
    if (_rangeDatePickerValueWithDefaultValue.isNotEmpty && _rangeDatePickerValueWithDefaultValue[0] != null) {
      hasDate = true;
      String start = DateFormat('dd/MM').format(_rangeDatePickerValueWithDefaultValue[0]!);
      String end = _rangeDatePickerValueWithDefaultValue.length > 1 && _rangeDatePickerValueWithDefaultValue[1] != null ? " - ${DateFormat('dd/MM').format(_rangeDatePickerValueWithDefaultValue[1]!)}" : "";
      dateButtonText = "$start$end";
    }

    return Scaffold(
      backgroundColor: const Color(0xFFE0F2F1),
      appBar: AppBar(title: const Text('היסטוריית פעולות'), backgroundColor: const Color(0xFF004D40), foregroundColor: Colors.white),
      body: _isLoadingData 
        ? const Center(child: CircularProgressIndicator()) 
        : Column(
          children: [
            Container(
              padding: const EdgeInsets.all(15), color: Colors.white,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3, 
                        child: TextField(
                          controller: _searchController, 
                          decoration: const InputDecoration(labelText: 'חיפוש (שם, ID, עובד, מטופל)', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true), 
                          onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase())
                        )
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        flex: 1, 
                        child: DropdownButtonFormField<String>(
                          value: _actionFilter, 
                          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true), 
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('הכל')), 
                            DropdownMenuItem(value: 'borrow', child: Text('לקיחות')), 
                            DropdownMenuItem(value: 'return', child: Text('החזרות')), 
                            DropdownMenuItem(value: 'out_of_use', child: Text('יצא משימוש (נמחק)')),
                          ], 
                          onChanged: (val) => setState(() { _actionFilter = val!; _subActionFilter = 'all'; })
                        )
                      ),
                      if (_actionFilter == 'out_of_use') ...[
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 1, 
                          child: DropdownButtonFormField<String>(
                            value: _subActionFilter, 
                            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, labelText: 'סיבה'), 
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('כל הסיבות')), 
                              DropdownMenuItem(value: 'sold', child: Text('מחסן מכירה')), 
                              DropdownMenuItem(value: 'lost', child: Text('נאבד')), 
                              DropdownMenuItem(value: 'broken', child: Text('תקול')), 
                              DropdownMenuItem(value: 'other', child: Text('אחר')), 
                            ], 
                            onChanged: (val) => setState(() => _subActionFilter = val!)
                          )
                        ),
                      ],
                      const SizedBox(width: 10),
                      IconButton(icon: const Icon(Icons.refresh, color: Colors.teal, size: 30), tooltip: "אפס הכל", onPressed: _clearAllFilters),
                    ],
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(
                        flex: 2, 
                        child: OutlinedButton.icon(
                          onPressed: _showDateRangePicker, 
                          icon: const Icon(Icons.calendar_month, color: Color(0xFF004D40)), 
                          label: Text(dateButtonText, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15), overflow: TextOverflow.ellipsis), 
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10), side: const BorderSide(color: Colors.grey), alignment: Alignment.centerRight)
                        )
                      ),
                      const SizedBox(width: 10),
                      TextButton(onPressed: _resetDates, style: TextButton.styleFrom(foregroundColor: hasDate ? Colors.red : Colors.grey), child: const Text("כל הזמנים", style: TextStyle(fontWeight: FontWeight.bold))),
                      const SizedBox(width: 15),
                      Expanded(
                        flex: 2, 
                        child: _buildFilterSelector(label: "קבוצה", stream: _getGroupsStream(), selectedName: _filterGroup?['name'], onSelected: (sel) => setState(() { _filterGroup = sel; _filterSku = null; _filterSelectorKey++; }))
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2, 
                        child: _filterGroup == null 
                          ? const Opacity(opacity: 0.5, child: TextField(enabled: false, decoration: InputDecoration(labelText: "מק\"ט (בחר קבוצה)", border: OutlineInputBorder(), isDense: true))) 
                          : _buildFilterSelector(label: "מק\"ט", stream: _getSkusStream(_filterGroup!['id']), selectedName: _filterSku?['name'], onSelected: (sel) => setState(() { _filterSku = sel; _filterSelectorKey++; }))
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15), color: Colors.grey[200],
              child: Row(
                children: const [
                  Expanded(flex: 2, child: Text('תאריך ושעה', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                  Expanded(flex: 3, child: Text('פריט (שם + מזהה)', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                  Expanded(flex: 2, child: Text('פעולה', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                  Expanded(flex: 3, child: Text('איש צוות', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                  Expanded(flex: 2, child: Text('מספר מטופל', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                
                stream: FirebaseFirestore.instance
                    .collection('companies')
                    .doc(widget.companyId)
                    .collection('History')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) return Center(child: Text("שגיאה: ${snapshot.error}", textDirection: TextDirection.ltr));
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                  var filtered = snapshot.data!.docs.where((doc) {
                    try {
                      var data = doc.data() as Map<String, dynamic>;
                      String itemId = data['itemId']?.toString() ?? '';
                      String docItemName = data['itemName']?.toString() ?? '';
                      String action = data['action']?.toString().toLowerCase() ?? '';
                      String staffUid = data['staffUid']?.toString() ?? '';
                      String encryptedPid = data['patientId']?.toString() ?? '';
                      String patientId = encryptedPid.isNotEmpty ? SecurityService.decryptID(encryptedPid) : '';

                      var cachedItem = _itemsCache[itemId];
                      String realItemName = (docItemName.isNotEmpty && docItemName != 'Unknown') ? docItemName : (cachedItem?['name']?.toString() ?? 'לא ידוע');
                      String staffName = _usersCache[staffUid] ?? 'לא ידוע';

                      if (_searchQuery.isNotEmpty) {
                        bool match = itemId.toLowerCase().contains(_searchQuery) || realItemName.toLowerCase().contains(_searchQuery) || staffName.toLowerCase().contains(_searchQuery) || patientId.contains(_searchQuery);
                        if (!match) return false;
                      }

                      if (_rangeDatePickerValueWithDefaultValue.isNotEmpty) {
                        if (data['timestamp'] == null || data['timestamp'] is! Timestamp) return false;
                        DateTime date = (data['timestamp'] as Timestamp).toDate();
                        DateTime? start = _rangeDatePickerValueWithDefaultValue[0];
                        DateTime? end = _rangeDatePickerValueWithDefaultValue.length > 1 ? _rangeDatePickerValueWithDefaultValue[1] : null;
                        if (start != null && date.isBefore(DateTime(start.year, start.month, start.day))) return false;
                        if (end != null && date.isAfter(DateTime(end.year, end.month, end.day, 23, 59, 59))) return false;
                      }

                      if (_actionFilter == 'borrow' && !(action.contains('take') || action.contains('borrow'))) return false;
                      if (_actionFilter == 'return' && !action.contains('return')) return false;
                      if (_actionFilter == 'out_of_use') {
                        if (!(action == 'broken' || action == 'lost' || action == 'sold' || action == 'other')) return false;
                        if (_subActionFilter != 'all' && action != _subActionFilter) return false;
                      }

                      if (_filterGroup != null && cachedItem?['group'] != _filterGroup!['id']) return false;
                      if (_filterSku != null && cachedItem?['sku'] != _filterSku!['id']) return false;

                      return true;
                    } catch (e) { return false; }
                  }).toList();

                  if (filtered.isEmpty) return const Center(child: Text("לא נמצאו רשומות", style: TextStyle(fontSize: 20, color: Colors.grey)));
                  
                  // Optimize rendering by limiting to 200 items max
                  var displayList = filtered.take(200).toList();

                  return ListView.builder(
                    padding: const EdgeInsets.only(left: 10, right: 10, top: 10),
                    itemCount: displayList.length + 1,
                    itemBuilder: (context, index) {
                      if (index == displayList.length) return const SizedBox(height: 150); 
                      try {
                        var doc = displayList[index];
                        var data = doc.data() as Map<String, dynamic>;

                        String dateStr = '-';
                        if (data['timestamp'] != null && data['timestamp'] is Timestamp) {
                          dateStr = DateFormat('dd/MM/yyyy\nHH:mm').format((data['timestamp'] as Timestamp).toDate());
                        }
                        
                        String itemId = data['itemId']?.toString() ?? '';
                        String docItemName = data['itemName']?.toString() ?? '';
                        String displayItemName = (docItemName.isNotEmpty && docItemName != 'Unknown') ? docItemName : (_itemsCache[itemId]?['name']?.toString() ?? 'לא ידוע');

                        String rawGroup = data['group']?.toString() ?? _itemsCache[itemId]?['group']?.toString() ?? 'לא הוגדר';
                        String groupName = _getReadableGroupName(rawGroup);

                        String action = data['action']?.toString() ?? '';
                        String staffUid = data['staffUid']?.toString() ?? '';
                        String staffName = _usersCache[staffUid] ?? 'לא ידוע';
                        String patientId = data['patientId']?.toString() != null && data['patientId'].toString().isNotEmpty ? SecurityService.decryptID(data['patientId'].toString()) : '-';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
                            child: Row(
                              children: [
                                Expanded(flex: 2, child: SelectableText(dateStr, style: bigTextStyle, textAlign: TextAlign.center)),
                                Expanded(
                                  flex: 3, 
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min, 
                                    crossAxisAlignment: CrossAxisAlignment.center, 
                                    children: [
                                      SelectableText(displayItemName, style: bigBoldStyle, textAlign: TextAlign.center), 
                                      SelectableText("קבוצה: $groupName", style: const TextStyle(fontSize: 13, color: Colors.blueGrey), textAlign: TextAlign.center),
                                      SelectableText("ID: $itemId", style: const TextStyle(fontSize: 14, color: Colors.grey), textAlign: TextAlign.center)
                                    ]
                                  )
                                ),
                                Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: _buildActionBadge(action))),
                                Expanded(flex: 3, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: SelectableText(staffName, style: bigTextStyle, textAlign: TextAlign.center))),
                                Expanded(flex: 2, child: SelectableText(patientId, style: bigBoldStyle, textAlign: TextAlign.center)),
                              ],
                            ),
                          ),
                        );
                      } catch (e) { return Card(color: Colors.red.shade100, child: const Padding(padding: EdgeInsets.all(8), child: Text('שגיאה במסמך', textDirection: TextDirection.ltr))); }
                    },
                  );
                },
              ),
            ),
          ],
        ),
    );
  }
}