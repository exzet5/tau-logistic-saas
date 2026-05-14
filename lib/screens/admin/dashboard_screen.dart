import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'dart:math' as math;
import '../../utils/helpers.dart';
import '../../services/security_service.dart';

/// Defines the time range for the statistics chart.
enum TimeRange { monthly, yearly }

/// The main dashboard screen for admins displaying real-time statistics, 
/// alerts (low stock, overdue), equipment efficiency, and historical charts.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // --- SETTINGS ---
  int _lowStockThreshold = 2;
  int _overdueDays = 30;

  // --- FILTERS (ALERTS) ---
  String? _lowStockGroupFilter;

  // --- FILTERS (EFFICIENCY) ---
  String? _efficiencyGroupFilter;
  String? _efficiencySkuFilter; 
  String? _efficiencySkuName; 

  // --- SETTINGS (STATS CHART) ---
  bool _showAdded = true;
  bool _showMoney = false;
  TimeRange _timeRange = TimeRange.yearly;
  String? _chartGroupFilter;
  String? _chartSkuFilter;
  int _chartFilterKey = 0;

  // Filter for specific item loss reasons
  String _chartLossReasonFilter = 'all'; 

  // --- CACHE ---
  Map<String, String> _groupNames = {};
  Map<String, List<Map<String, String>>> _skuByGroup = {};

  // --- SCROLL CONTROLLERS ---
  final ScrollController _lowStockScrollCtrl = ScrollController();
  final ScrollController _overdueScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadFiltersData();
  }

  @override
  void dispose() {
    _lowStockScrollCtrl.dispose();
    _overdueScrollCtrl.dispose();
    super.dispose();
  }

  /// Fetches group names and associated SKUs to populate the filter dropdowns.
  Future<void> _loadFiltersData() async {
    var gSnap = await FirebaseFirestore.instance.collection('items_groups').get();
    for (var doc in gSnap.docs) {
      _groupNames[doc.id] = doc.data()['name'] ?? doc.id;
      var sSnap = await FirebaseFirestore.instance
          .collection('SKU')
          .where('GroupID', isEqualTo: doc.id)
          .get();
      List<Map<String, String>> skus = [];
      for (var s in sSnap.docs) {
        skus.add({'id': s.id, 'name': s.data()['name'] ?? s.id});
      }
      _skuByGroup[doc.id] = skus;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('items').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          var docs = snapshot.data!.docs;

          // 1. RAW DATA (Exclude all 4 loss statuses to find active inventory)
          List<String> lossStatuses = ['broken', 'lost', 'sold', 'other'];
          var activeDocs = docs.where((d) {
            var data = d.data() as Map<String, dynamic>;
            String status = data['status'] ?? '';
            return !lossStatuses.contains(status);
          }).toList();

          int totalActive = activeDocs.length;
          int available = activeDocs.where((d) {
            return (d.data() as Map<String, dynamic>)['status'] == 'available';
          }).length;
          
          int inUse = activeDocs.where((d) {
            String s = (d.data() as Map<String, dynamic>)['status'] ?? '';
            return s == 'in_use' || s == 'taken';
          }).length;

          // 2. PREPARE LOW STOCK DATA
          Map<String, int> skuAvailable = {};
          Map<String, int> skuTotal = {};
          Map<String, String> skuExampleId = {};
          Map<String, String> skuGroupNames = {};

          for (var doc in activeDocs) {
            var d = doc.data() as Map<String, dynamic>;
            String name = d['name'] ?? 'Unknown';
            String gId = d['GroupID'] ?? '';
            String id = d['ID'] ?? '';
            String groupName = d['group'] ?? _groupNames[gId] ?? 'לא הוגדר';
            
            if (name == 'Unknown') continue;

            if (_lowStockGroupFilter != null &&
                _lowStockGroupFilter != 'ALL' &&
                gId != _lowStockGroupFilter) {
              continue;
            }

            skuTotal[name] = (skuTotal[name] ?? 0) + 1;
            if (d['status'] == 'available') {
              skuAvailable[name] = (skuAvailable[name] ?? 0) + 1;
            } else {
              skuAvailable[name] = (skuAvailable[name] ?? 0);
            }
            skuExampleId[name] = id;
            skuGroupNames[name] = groupName; 
          }

          var lowStockItems = skuAvailable.entries
              .where((e) => e.value <= _lowStockThreshold)
              .toList();

          // 3. PREPARE OVERDUE DATA
          DateTime overdueDate = DateTime.now().subtract(Duration(days: _overdueDays));
              
          var overdueItems = activeDocs.where((d) {
            var data = d.data() as Map<String, dynamic>;
            if (data['status'] != 'in_use') return false;
            if (data['lastTaken'] == null) return false;
            Timestamp ts = data['lastTaken'];
            return ts.toDate().isBefore(overdueDate);
          }).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER
              Row(
                children: [
                  Text(
                    "תפוסה נוכחית: $inUse מתוך $totalActive",
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF004D40)),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              _buildWideProgressBar(available, inUse, totalActive),
              const SizedBox(height: 30),

              // STAT CARDS
              Wrap(
                spacing: 15,
                runSpacing: 15,
                children: [
                  _buildStatCard("פעילים במלאי", totalActive.toString(), Icons.inventory, Colors.teal),
                  _buildStatCard("פנויים לשימוש", available.toString(), Icons.check_circle, Colors.green),
                  _buildStatCard("בשימוש כרגע", inUse.toString(), Icons.people, Colors.blue),
                ],
              ),
              const SizedBox(height: 30),

              // ALERTS SECTION
              LayoutBuilder(builder: (context, constraints) {
                if (constraints.maxWidth > 900) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildLowStockAlert(
                            lowStockItems, skuExampleId, skuTotal, skuGroupNames),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: _buildOverdueAlert(overdueItems),
                      ),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      _buildLowStockAlert(
                          lowStockItems, skuExampleId, skuTotal, skuGroupNames),
                      const SizedBox(height: 20),
                      _buildOverdueAlert(overdueItems),
                    ],
                  );
                }
              }),

              const SizedBox(height: 40),

              // === EFFICIENCY SECTION ===
              const Text(
                "יעילות ושימוש (Efficiency)",
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF004D40)),
              ),
              const SizedBox(height: 15),
              _buildEfficiencySection(activeDocs),

              const SizedBox(height: 40),

              // === STATS CHART (PURCHASE/LOST) ===
              _buildProChartSection(docs),

              const SizedBox(height: 150),
            ],
          );
        },
      ),
    );
  }

  // --- 1. ALERTS WIDGETS ---

  /// Builds the alert panel displaying items that have reached the low stock threshold.
  Widget _buildLowStockAlert(
      List<MapEntry<String, int>> items,
      Map<String, String> exampleIds,
      Map<String, int> totals,
      Map<String, String> groupNames) {
    return _buildAlertBox(
      titleWidget: Row(
        children: [
          const Icon(Icons.shopping_cart_checkout, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "מלאי פנוי נמוך (≤ $_lowStockThreshold)",
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.orange),
            ),
          ),
        ],
      ),
      onSettings: _showLowStockSettingsDialog,
      extraAction: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.orange, width: 2),
          borderRadius: BorderRadius.circular(8),
          color: Colors.orange[50],
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _lowStockGroupFilter,
            icon: const Icon(Icons.filter_list, color: Colors.orange),
            hint: const Text(
              "סינון קבוצה",
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.orange),
            ),
            items: [
              const DropdownMenuItem(
                value: 'ALL',
                child: Text("הכל", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ..._groupNames.entries.map((e) {
                return DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value),
                );
              }).toList()
            ],
            onChanged: (val) {
              setState(() {
                _lowStockGroupFilter = val == 'ALL' ? null : val;
              });
            },
          ),
        ),
      ),
      child: SizedBox(
        height: 300,
        child: items.isEmpty
            ? const Center(
                child: Text(
                  "המלאי תקין 👍",
                  style: TextStyle(color: Colors.grey),
                ),
              )
            : NotificationListener<OverscrollIndicatorNotification>(
                onNotification: (overscroll) {
                  overscroll.disallowIndicator();
                  return true;
                },
                child: ListView.separated(
                  controller: _lowStockScrollCtrl,
                  physics: const ClampingScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (c, i) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    var e = items[i];
                    int total = totals[e.key] ?? 0;
                    String group = groupNames[e.key] ?? 'לא הוגדר';
                    
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 5),
                      title: SelectableText(
                        "${e.key} (ID: ${exampleIds[e.key] ?? '...'})",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text("קבוצה: $group", style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                      trailing: Chip(
                        label: Text("${e.value} פנויים מתוך $total"),
                        backgroundColor: e.value == 0
                            ? Colors.red[100]
                            : Colors.orange[100],
                        labelStyle: TextStyle(
                            color: e.value == 0
                                ? Colors.red
                                : Colors.orange[900],
                            fontWeight: FontWeight.bold),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }

  /// Builds the alert panel displaying items currently exceeding the allowed taken duration.
  Widget _buildOverdueAlert(List<QueryDocumentSnapshot<Object?>> items) {
    return _buildAlertBox(
      titleWidget: Row(
        children: [
          const Icon(Icons.timer_off, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "חריגות זמן (> $_overdueDays יום)",
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.red),
            ),
          ),
        ],
      ),
      onSettings: _showOverdueSettingsDialog,
      extraAction: null,
      child: SizedBox(
        height: 300,
        child: items.isEmpty
            ? const Center(
                child: Text(
                  "אין חריגות זמן 👍",
                  style: TextStyle(color: Colors.grey),
                ),
              )
            : NotificationListener<OverscrollIndicatorNotification>(
                onNotification: (overscroll) {
                  overscroll.disallowIndicator();
                  return true;
                },
                child: ListView.separated(
                  controller: _overdueScrollCtrl,
                  physics: const ClampingScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (c, i) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    var d = items[i].data() as Map<String, dynamic>;
                    Timestamp ts = d['lastTaken'];
                    int days = DateTime.now().difference(ts.toDate()).inDays;
                    String pId = d['patientId'] != null
                        ? SecurityService.decryptID(d['patientId'])
                        : '?';
                    String group = d['group'] ?? _groupNames[d['GroupID']] ?? 'לא הוגדר';

                    return ListTile(
                      dense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 5),
                      title: SelectableText("${d['name']} (ID: ${d['ID']})"),
                      subtitle: SelectableText("קבוצה: $group | אצל: $pId", style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                      trailing: Text(
                        "$days ימים",
                        style: const TextStyle(
                            color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }

  // --- 2. EFFICIENCY SECTION ---

  /// Calculates and builds the complex UI for the Efficiency section, computing 
  /// historical usage rates for different SKUs based on their creation dates.
  Widget _buildEfficiencySection(List<QueryDocumentSnapshot> activeDocs) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('History').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 300,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        var historyDocs = snapshot.data!.docs;
        DateTime now = DateTime.now();

        Map<String, String> skuNames = {};
        Map<String, String> skuGroups = {}; 
        Map<String, List<DateTime>> itemAddedDates = {};
        Map<String, List<String>> itemsInSku = {};

        for (var doc in activeDocs) {
          var d = doc.data() as Map<String, dynamic>;
          String sId = d['SKU_ID'] ?? '';
          String iId = d['ID'] ?? '';
          String gId = d['GroupID'] ?? '';
          if (sId.isEmpty) continue;

          skuNames[sId] = d['name'] ?? 'Unknown';
          skuGroups[sId] = d['group'] ?? _groupNames[gId] ?? 'לא הוגדר';

          if (itemsInSku[sId] == null) itemsInSku[sId] = [];
          itemsInSku[sId]!.add(iId);

          Timestamp? added = d['dateAdded'];
          if (added != null) {
            if (itemAddedDates[iId] == null) itemAddedDates[iId] = [];
            itemAddedDates[iId]!.add(added.toDate());
          }
        }

        Map<String, List<Map<String, dynamic>>> historyByItem = {};
        for (var h in historyDocs) {
          var d = h.data() as Map<String, dynamic>;
          String itemId = d['itemId'] ?? '';
          if (itemId.isNotEmpty) {
            if (historyByItem[itemId] == null) historyByItem[itemId] = [];
            historyByItem[itemId]!.add(d);
          }
        }

        List<Map<String, dynamic>> skuStats = [];
        DateTime sixMonthsAgo = DateTime(now.year, now.month - 5, 1);

        itemsInSku.forEach((skuId, itemIds) {
          double totalUsedDays = 0;
          double totalCapacityDays = 0;

          for (String itemId in itemIds) {
            DateTime bornDate = itemAddedDates[itemId]?.isNotEmpty == true
                ? itemAddedDates[itemId]!.first
                : DateTime(2000);

            DateTime effectiveStart =
                bornDate.isAfter(sixMonthsAgo) ? bornDate : sixMonthsAgo;
            int capacity = now.difference(effectiveStart).inDays + 1;
            if (capacity < 0) capacity = 0;
            totalCapacityDays += capacity;

            List<Map<String, dynamic>> events = historyByItem[itemId] ?? [];
            events.sort((a, b) => (a['timestamp'] as Timestamp)
                .compareTo(b['timestamp'] as Timestamp));

            DateTime? lastTake;
            for (var e in events) {
              String action = e['action'];
              DateTime ts = (e['timestamp'] as Timestamp).toDate();

              if (action == 'take') {
                lastTake = ts;
              } else if (action == 'return' && lastTake != null) {
                DateTime start =
                    lastTake.isAfter(effectiveStart) ? lastTake : effectiveStart;
                DateTime end = ts.isBefore(now) ? ts : now;
                if (start.isBefore(end)) {
                  totalUsedDays += end.difference(start).inHours / 24.0;
                }
                lastTake = null;
              }
            }
            if (lastTake != null) {
              DateTime start =
                  lastTake.isAfter(effectiveStart) ? lastTake : effectiveStart;
              if (start.isBefore(now)) {
                totalUsedDays += now.difference(start).inHours / 24.0;
              }
            }
          }

          double rate =
              totalCapacityDays > 0 ? totalUsedDays / totalCapacityDays : 0;
          skuStats.add({
            'id': skuId,
            'name': skuNames[skuId] ?? skuId,
            'group': skuGroups[skuId] ?? 'לא הוגדר', 
            'rate': rate,
          });
        });

        skuStats.sort((a, b) => b['rate'].compareTo(a['rate']));
        var top5 = skuStats.take(5).toList();
        var bottom5 = skuStats.reversed.take(5).toList();

        String selectedId =
            _efficiencySkuFilter ?? (top5.isNotEmpty ? top5.first['id'] : '');
        String selectedName = _efficiencySkuName ??
            (top5.isNotEmpty ? top5.first['name'] : '');

        Map<String, String> skuIdToName = skuNames;
        List<Map<String, String>> dropdownSkus = [];
        
        if (_efficiencyGroupFilter != null &&
            _skuByGroup[_efficiencyGroupFilter] != null) {
          dropdownSkus = _skuByGroup[_efficiencyGroupFilter]!;
        } else {
          dropdownSkus = skuIdToName.entries
              .map((e) => {'id': e.key, 'name': e.value})
              .toList();
        }

        if (selectedId.isNotEmpty &&
            !dropdownSkus.any((s) => s['id'] == selectedId)) {
          if (dropdownSkus.isNotEmpty) {
            selectedId = dropdownSkus.first['id']!;
            selectedName = dropdownSkus.first['name']!;
          }
        }

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.grey.shade200, blurRadius: 5)
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              bool isWide = constraints.maxWidth > 900;
              return Flex(
                direction: isWide ? Axis.horizontal : Axis.vertical,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // LISTS
                  SizedBox(
                    width: isWide ? 300 : double.infinity,
                    child: Column(
                      children: [
                        _buildEfficiencyList(
                            "🔥 הכי בשימוש (ממוצע חצי שנה)",
                            top5,
                            Colors.orange[50]!),
                        const SizedBox(height: 20),
                        _buildEfficiencyList(
                            "❄️ הכי פנויים (ממוצע חצי שנה)",
                            bottom5,
                            Colors.blue[50]!),
                      ],
                    ),
                  ),
                  if (isWide)
                    const SizedBox(width: 30)
                  else
                    const SizedBox(height: 30),

                  // CHART
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("קבוצה",
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12)),
                                  const SizedBox(height: 5),
                                  DropdownButtonFormField<String>(
                                    decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        isDense: true),
                                    value: _efficiencyGroupFilter,
                                    items: [
                                      const DropdownMenuItem(
                                          value: null, child: Text("הכל")),
                                      ..._groupNames.entries
                                          .map((e) => DropdownMenuItem(
                                              value: e.key,
                                              child: Text(e.value)))
                                          .toList()
                                    ],
                                    onChanged: (val) {
                                      setState(() {
                                        _efficiencyGroupFilter = val;
                                        _efficiencySkuFilter = null;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("מק\"ט",
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12)),
                                  const SizedBox(height: 5),
                                  DropdownButtonFormField<String>(
                                    decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        isDense: true),
                                    value: selectedId.isEmpty
                                        ? null
                                        : selectedId,
                                    items: dropdownSkus
                                        .map((s) => DropdownMenuItem(
                                            value: s['id'],
                                            child: Text(s['name']!)))
                                        .toList(),
                                    onChanged: (val) {
                                      setState(() {
                                        _efficiencySkuFilter = val;
                                        _efficiencySkuName = skuNames[val];
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        selectedId.isEmpty
                            ? const SizedBox(
                                height: 300,
                                child: Center(child: Text("אין נתונים להצגה")))
                            : Column(
                                children: [
                                  Text("היסטוריית שימוש: $selectedName",
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.teal)),
                                  const SizedBox(height: 10),
                                  _buildEfficiencyChartForSku(
                                      selectedId,
                                      selectedName,
                                      activeDocs,
                                      historyDocs),
                                ],
                              ),
                      ],
                    ),
                  )
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// Builds a visual ranking list for efficiency statistics (e.g., top 5 used, bottom 5 unused).
  Widget _buildEfficiencyList(
      String title, List<Map<String, dynamic>> items, Color bgColor) {
    return Container(
      decoration: BoxDecoration(
          color: bgColor, borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(),
          if (items.isEmpty) const Text("אין נתונים"),
          ...items.map((item) {
            int percent = (item['rate'] * 100).round();
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(item['name'],
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("קבוצה: ${item['group']}", style: TextStyle(color: Colors.grey[700], fontSize: 11)),
              trailing: Text("$percent%",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: percent > 50
                          ? Colors.orange[800]
                          : Colors.blue[800])),
              onTap: () {
                setState(() {
                  _efficiencySkuFilter = item['id'];
                  _efficiencySkuName = item['name'];
                  _groupNames.forEach((gId, gName) {
                    var list = _skuByGroup[gId];
                    if (list != null && list.any((s) => s['id'] == item['id'])) {
                      _efficiencyGroupFilter = gId;
                    }
                  });
                });
              },
            );
          }).toList()
        ],
      ),
    );
  }

  /// Renders a detailed bar chart mapping the efficiency trend for a specific SKU over time.
  Widget _buildEfficiencyChartForSku(
      String skuId,
      String skuName,
      List<QueryDocumentSnapshot> activeDocs,
      List<QueryDocumentSnapshot> historyDocs) {
    Set<String> itemIds = activeDocs
        .where((d) => (d.data() as Map<String, dynamic>)['SKU_ID'] == skuId)
        .map((d) => (d.data() as Map<String, dynamic>)['ID'].toString())
        .toSet();

    Map<String, DateTime> itemBirthdays = {};
    for (var doc in activeDocs) {
      var d = doc.data() as Map<String, dynamic>;
      if (itemIds.contains(d['ID'])) {
        Timestamp? ts = d['dateAdded'];
        itemBirthdays[d['ID']] = ts != null ? ts.toDate() : DateTime(2000);
      }
    }

    Map<String, double> usageDaysPerMonth = {};
    DateTime now = DateTime.now();
    List<String> sortedMonths = [];

    for (int i = 5; i >= 0; i--) {
      DateTime m = DateTime(now.year, now.month - i, 1);
      String key = "${m.year}-${m.month.toString().padLeft(2, '0')}";
      usageDaysPerMonth[key] = 0.0;
      sortedMonths.add(key);
    }

    var relevantHistory = historyDocs.where((h) {
      var data = h.data() as Map<String, dynamic>;
      return itemIds.contains(data['itemId']);
    }).toList();

    relevantHistory.sort((a, b) => (a.data() as Map<String, dynamic>)['timestamp']
        .compareTo((b.data() as Map<String, dynamic>)['timestamp']));

    Map<String, DateTime> currentlyTaken = {};

    for (var h in relevantHistory) {
      var data = h.data() as Map<String, dynamic>;
      String id = data['itemId'];
      String action = data['action'];
      DateTime ts = (data['timestamp'] as Timestamp).toDate();

      if (action == 'take') {
        currentlyTaken[id] = ts;
      } else if (action == 'return') {
        if (currentlyTaken.containsKey(id)) {
          DateTime start = currentlyTaken[id]!;
          _addUsageToMonths(start, ts, usageDaysPerMonth);
          currentlyTaken.remove(id);
        }
      }
    }
    
    currentlyTaken.forEach((id, start) {
      _addUsageToMonths(start, now, usageDaysPerMonth);
    });

    List<BarChartGroupData> barGroups = [];

    for (int i = 0; i < sortedMonths.length; i++) {
      String key = sortedMonths[i];
      double totalUsedDays = usageDaysPerMonth[key]!;

      int year = int.parse(key.split('-')[0]);
      int month = int.parse(key.split('-')[1]);

      DateTime mStart = DateTime(year, month, 1);
      DateTime mEnd = DateTime(year, month + 1, 0, 23, 59, 59);
      if (i == sortedMonths.length - 1) mEnd = now;

      double monthlyCapacity = 0;
      for (String itemId in itemIds) {
        DateTime born = itemBirthdays[itemId]!;
        DateTime effectiveStart = born.isAfter(mStart) ? born : mStart;

        if (effectiveStart.isBefore(mEnd)) {
          monthlyCapacity += mEnd.difference(effectiveStart).inHours / 24.0;
        }
      }
      if (monthlyCapacity < 1) monthlyCapacity = 1;

      double percent = (totalUsedDays / monthlyCapacity) * 100;
      if (percent > 100) percent = 100;

      barGroups.add(BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
                toY: percent,
                color: Colors.teal,
                width: 30,
                borderRadius: BorderRadius.circular(4))
          ],
          showingTooltipIndicators: [0]));
    }

    return SizedBox(
      height: 300,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: 100,
          barTouchData: BarTouchData(
              enabled: false,
              touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (group) => Colors.transparent,
                  tooltipMargin: 0,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    return BarTooltipItem(
                        "${rod.toY.toInt()}%",
                        const TextStyle(
                            color: Colors.black, fontWeight: FontWeight.bold));
                  })),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (val, meta) {
                      int idx = val.toInt();
                      if (idx >= 0 && idx < sortedMonths.length) {
                        return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(sortedMonths[idx],
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)));
                      }
                      return const SizedBox();
                    })),
            leftTitles: AxisTitles(
                axisNameWidget: const Text("יעילות",
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                axisNameSize: 20,
                sideTitles: SideTitles(
                    showTitles: true,
                    interval: 20,
                    reservedSize: 50,
                    getTitlesWidget: (val, meta) {
                      return Text("${val.toInt()}%",
                          style: const TextStyle(
                              fontSize: 10, color: Colors.grey));
                    })),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
              show: true, drawVerticalLine: false, horizontalInterval: 20),
          borderData: FlBorderData(
              show: true,
              border: const Border(
                  bottom: BorderSide(color: Colors.black),
                  left: BorderSide(color: Colors.black))),
          barGroups: barGroups,
        ),
      ),
    );
  }

  /// Distributes usage days evenly across month boundaries for chart generation.
  void _addUsageToMonths(
      DateTime start, DateTime end, Map<String, double> bucket) {
    DateTime cursor = start;
    while (cursor.isBefore(end)) {
      String key = "${cursor.year}-${cursor.month.toString().padLeft(2, '0')}";
      DateTime endOfMonth =
          DateTime(cursor.year, cursor.month + 1, 0, 23, 59, 59);
      DateTime intervalEnd = end.isBefore(endOfMonth) ? end : endOfMonth;
      double days = intervalEnd.difference(cursor).inHours / 24.0;
      if (bucket.containsKey(key)) {
        bucket[key] = (bucket[key] ?? 0) + days;
      }
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
  }

  /// A helper widget to render a uniform KPI stat card.
  Widget _buildStatCard(
      String title, String count, IconData icon, Color color) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150, minHeight: 100),
      child: Container(
        width: 200,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.grey.shade200, blurRadius: 5)
            ]),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(height: 5),
            Text(count,
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            Text(title,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  /// A reusable wrapper container for alert boxes (low stock, overdue).
  Widget _buildAlertBox(
      {required Widget titleWidget,
      required Widget child,
      required VoidCallback onSettings,
      Widget? extraAction}) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.grey.shade200, blurRadius: 5)
          ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: titleWidget),
              if (extraAction != null) extraAction,
              const SizedBox(width: 10),
              InkWell(
                onTap: onSettings,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        Text("לחץ לשינוי",
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[700])),
                        const SizedBox(width: 4),
                        Icon(Icons.settings,
                            color: Colors.grey[800], size: 20),
                      ],
                    )),
              )
            ],
          ),
          const Divider(),
          child,
        ],
      ),
    );
  }

  /// A visual component rendering a horizontal bar split proportionally 
  /// between available and in-use equipment.
  Widget _buildWideProgressBar(int available, int inUse, int total) {
    if (total == 0) return const SizedBox();
    int inUsePercent = ((inUse / total) * 100).round();
    int availablePercent = ((available / total) * 100).round();
    String inUseText = inUse > 0 ? "בשימוש ($inUsePercent%)" : "";
    String availableText = available > 0 ? "פנוי ($availablePercent%)" : "";

    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            Expanded(
                flex: inUse,
                child: Container(
                    color: Colors.blue,
                    child: Center(
                        child: Text(inUseText,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis)))),
            Expanded(
                flex: available,
                child: Container(
                    color: Colors.green[400],
                    child: Center(
                        child: Text(availableText,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis)))),
          ],
        ),
      ),
    );
  }

  // --- STATS CHART (BOTTOM) ---
  
  /// Calculates and builds the main statistical chart comparing acquisitions 
  /// and lost/broken items over monthly or yearly intervals.
  Widget _buildProChartSection(List<QueryDocumentSnapshot> allDocs) {
    Map<String, double> chartData = {};
    DateTime now = DateTime.now();
    DateTime? minDate;

    // IMPORTANT: All 4 loss statuses must be considered here
    List<String> lossStatuses = ['broken', 'lost', 'sold', 'other'];

    // 1. FIND THE MINIMUM DATE
    for (var doc in allDocs) {
      var data = doc.data() as Map<String, dynamic>;
      Timestamp? dateTs;
      
      if (_showAdded) {
        dateTs = data['dateAdded'];
      } else {
        String status = data['status'] ?? '';
        if (lossStatuses.contains(status)) {
          // If a specific loss reason filter is selected
          if (_chartLossReasonFilter != 'all' && status != _chartLossReasonFilter) continue;
          
          // Use deletion date. Fallback to creation date for legacy records.
          dateTs = data['dateDeleted'] ?? data['dateAdded'];
        }
      }
      
      if (dateTs != null) {
        DateTime dt = dateTs.toDate();
        if (minDate == null || dt.isBefore(minDate)) minDate = dt;
      }
    }

    if (minDate == null) minDate = now;

    // 2. CREATE X-AXIS RANGES (Months or Years)
    List<String> allKeys = [];
    DateTime cursor = minDate;

    if (_timeRange == TimeRange.monthly) {
      cursor = DateTime(cursor.year, cursor.month, 1);
      while (cursor.isBefore(now) ||
          cursor.isAtSameMomentAs(now) ||
          (cursor.year == now.year && cursor.month == now.month)) {
        String key = "${cursor.year}-${cursor.month.toString().padLeft(2, '0')}";
        allKeys.add(key);
        chartData[key] = 0;
        cursor = DateTime(cursor.year, cursor.month + 1, 1);
      }
    } else {
      cursor = DateTime(cursor.year, 1, 1);
      while (cursor.year <= now.year) {
        String key = "${cursor.year}";
        allKeys.add(key);
        chartData[key] = 0;
        cursor = DateTime(cursor.year + 1, 1, 1);
      }
    }

    // 3. POPULATE DATA
    for (var doc in allDocs) {
      var data = doc.data() as Map<String, dynamic>;
      
      if (_chartGroupFilter != null && data['GroupID'] != _chartGroupFilter) continue;
      if (_chartSkuFilter != null && data['SKU_ID'] != _chartSkuFilter) continue;

      Timestamp? dateTs;
      
      if (_showAdded) {
        dateTs = data['dateAdded'];
      } else {
        String status = data['status'] ?? '';
        if (lossStatuses.contains(status)) {
          if (_chartLossReasonFilter != 'all' && status != _chartLossReasonFilter) continue;
          dateTs = data['dateDeleted'] ?? data['dateAdded'];
        } else {
          continue; 
        }
      }

      if (dateTs == null) continue;
      DateTime date = dateTs.toDate();

      String key;
      if (_timeRange == TimeRange.monthly) {
        key = "${date.year}-${date.month.toString().padLeft(2, '0')}";
      } else {
        key = "${date.year}";
      }

      if (chartData.containsKey(key)) {
        double value = 1;
        if (_showMoney) value = (data['cost'] ?? 0).toDouble();
        chartData[key] = chartData[key]! + value;
      }
    }

    // 4. DRAW THE CHART
    List<BarChartGroupData> barGroups = [];
    double maxY = 0;

    for (int i = 0; i < allKeys.length; i++) {
      double val = chartData[allKeys[i]]!;
      if (val > maxY) maxY = val;

      barGroups.add(BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
                toY: val,
                color: _showAdded ? Colors.teal : Colors.redAccent,
                width: 32,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(4)))
          ],
          showingTooltipIndicators: [0]));
    }

    if (maxY == 0) maxY = 10;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.grey.shade200, blurRadius: 5)
          ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("סטטיסטיקה כללית (רכש ואובדן)",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("קבוצה",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 5),
                    DropdownButtonFormField<String>(
                        key: ValueKey('cg_$_chartFilterKey'),
                        decoration: const InputDecoration(
                            border: OutlineInputBorder(), isDense: true),
                        value: _chartGroupFilter,
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text("כל הקבוצות")),
                          ..._groupNames.entries
                              .map((e) => DropdownMenuItem(
                                  value: e.key, child: Text(e.value)))
                              .toList()
                        ],
                        onChanged: (val) {
                          setState(() {
                            _chartGroupFilter = val;
                            _chartSkuFilter = null;
                            _chartFilterKey++;
                          });
                        }),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("מק\"ט",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 5),
                    DropdownButtonFormField<String>(
                        key: ValueKey('cs_$_chartFilterKey'),
                        decoration: const InputDecoration(
                            border: OutlineInputBorder(), isDense: true),
                        value: _chartSkuFilter,
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text("הכל")),
                          if (_chartGroupFilter != null &&
                              _skuByGroup[_chartGroupFilter] != null)
                            ..._skuByGroup[_chartGroupFilter]!
                                .map((s) => DropdownMenuItem(
                                    value: s['id'], child: Text(s['name']!)))
                                .toList()
                        ],
                        onChanged: _chartGroupFilter == null
                            ? null
                            : (val) => setState(() => _chartSkuFilter = val)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 5.0),
                child: IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.blueGrey),
                    onPressed: () => setState(() {
                          _chartGroupFilter = null;
                          _chartSkuFilter = null;
                          _chartFilterKey++;
                        })),
              ),
            ],
          ),
          const SizedBox(height: 15),
          
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ToggleButtons(
                isSelected: [_showAdded, !_showAdded],
                onPressed: (idx) {
                  setState(() {
                    _showAdded = idx == 0;
                    if (_showAdded) _chartLossReasonFilter = 'all'; 
                  });
                },
                borderRadius: BorderRadius.circular(8),
                selectedColor: Colors.white,
                fillColor: _showAdded ? Colors.teal : Colors.redAccent,
                children: const [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20), 
                    child: Row(children: [
                      Icon(Icons.add, size: 16),
                      SizedBox(width: 6),
                      Text("רכישות")
                    ]),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20), 
                    child: Row(children: [
                      Icon(Icons.delete, size: 16),
                      SizedBox(width: 6),
                      Text("יצא משימוש")
                    ]),
                  ),
                ],
              ),
              
              if (!_showAdded)
                Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.red.shade50,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _chartLossReasonFilter,
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.redAccent),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('כל הסיבות')),
                        DropdownMenuItem(value: 'sold', child: Text('מחסן מכירה')),
                        DropdownMenuItem(value: 'lost', child: Text('נאבד')),
                        DropdownMenuItem(value: 'broken', child: Text('תקול')),
                        DropdownMenuItem(value: 'other', child: Text('אחר')),
                      ],
                      onChanged: (val) {
                        setState(() => _chartLossReasonFilter = val!);
                      },
                    ),
                  ),
                ),

              ToggleButtons(
                isSelected: [!_showMoney, _showMoney],
                onPressed: (idx) => setState(() => _showMoney = idx == 1),
                borderRadius: BorderRadius.circular(8),
                selectedColor: Colors.white,
                fillColor: Colors.blueGrey,
                children: const [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 15),
                    child: Text("יח'"),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 15),
                    child: Text("₪"),
                  ),
                ],
              ),
              ToggleButtons(
                isSelected: [
                  _timeRange == TimeRange.monthly,
                  _timeRange == TimeRange.yearly
                ],
                onPressed: (idx) {
                  setState(() {
                    if (idx == 0) {
                      _timeRange = TimeRange.monthly;
                    } else if (idx == 1) {
                      _timeRange = TimeRange.yearly;
                    }
                  });
                },
                borderRadius: BorderRadius.circular(8),
                selectedColor: Colors.white,
                fillColor: Colors.blueGrey,
                children: const [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 15),
                    child: Text("חודש"),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 15),
                    child: Text("שנה"),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 40),
          LayoutBuilder(builder: (context, constraints) {
            double minWidth = constraints.maxWidth;
            double calculatedWidth = allKeys.length * 90.0;
            double finalWidth =
                calculatedWidth > minWidth ? calculatedWidth : minWidth;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: SizedBox(
                width: finalWidth,
                height: 350,
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: maxY * 1.4,
                      barTouchData: BarTouchData(
                          enabled: false,
                          touchTooltipData: BarTouchTooltipData(
                              getTooltipColor: (group) =>
                                  Colors.transparent,
                              tooltipPadding: EdgeInsets.zero,
                              tooltipMargin: 8,
                              getTooltipItem:
                                  (group, groupIndex, rod, rodIndex) {
                                return BarTooltipItem(
                                    _showMoney
                                        ? "${rod.toY.toStringAsFixed(0)}₪"
                                        : "${rod.toY.toInt()}",
                                    const TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12));
                              })),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget:
                                  (double value, TitleMeta meta) {
                                int index = value.toInt();
                                if (index < 0 || index >= allKeys.length) {
                                  return const SizedBox();
                                }
                                return Padding(
                                    padding:
                                        const EdgeInsets.only(top: 8.0),
                                    child: Text(allKeys[index],
                                        style: const TextStyle(
                                            color: Colors.black,
                                            fontSize: 11,
                                            fontWeight:
                                                FontWeight.bold)));
                              }),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 50,
                              getTitlesWidget:
                                  (double value, TitleMeta meta) {
                                if (value == 0) return const SizedBox();
                                return Text(
                                    _showMoney
                                        ? "${value.toInt()}₪"
                                        : "${value.toInt()}",
                                    style: TextStyle(
                                        color: Colors.grey[800],
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold));
                              }),
                        ),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (value) => FlLine(
                              color: Colors.grey.withOpacity(0.2),
                              strokeWidth: 1)),
                      borderData: FlBorderData(
                          show: true,
                          border: const Border(
                              bottom: BorderSide(
                                  color: Colors.black, width: 1),
                              left: BorderSide(
                                  color: Colors.black, width: 1))),
                      barGroups: barGroups,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // --- DIALOGS ---

  /// Prompts the user to configure the threshold for the low stock alert.
  void _showLowStockSettingsDialog() {
    TextEditingController c =
        TextEditingController(text: _lowStockThreshold.toString());
    showDialog(
        context: context,
        builder: (ctx) => Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text("הגדר סף מלאי נמוך"),
                content: TextField(
                    controller: c,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: "כמות מינימלית")),
                actions: [
                  ElevatedButton(
                      onPressed: () {
                        setState(() => _lowStockThreshold =
                            int.tryParse(c.text) ?? 2);
                        Navigator.pop(ctx);
                      },
                      child: const Text("שמור"))
                ],
              ),
            ));
  }

  /// Prompts the user to configure the day limit for the overdue returns alert.
  void _showOverdueSettingsDialog() {
    TextEditingController c =
        TextEditingController(text: _overdueDays.toString());
    showDialog(
        context: context,
        builder: (ctx) => Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text("הגדר סף חריגת זמן"),
                content: TextField(
                    controller: c,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: "מספר ימים מקסימלי")),
                actions: [
                  ElevatedButton(
                      onPressed: () {
                        setState(() =>
                            _overdueDays = int.tryParse(c.text) ?? 30);
                        Navigator.pop(ctx);
                      },
                      child: const Text("שמור"))
                ],
              ),
            ));
  }
}