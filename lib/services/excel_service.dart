import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:excel/excel.dart';
import 'package:universal_html/html.dart' as html;

/// Universal service for generating and downloading Excel (.xlsx) files.
class ExcelService {
  
  /// Generates an Excel file from provided headers and data rows, then triggers a download.
  static Future<void> exportToExcel({
    required String sheetName,
    required List<String> headers,
    required List<List<dynamic>> dataRows,
    required String fileName,
  }) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel[sheetName];
    excel.setDefaultSheet(sheetName);

    // Add headers
    List<TextCellValue> headerCells = headers.map((h) => TextCellValue(h)).toList();
    sheetObject.appendRow(headerCells);

    // Add data rows
    for (var row in dataRows) {
      List<CellValue> cellValues = row.map((value) {
        if (value is num) {
          return DoubleCellValue(value.toDouble());
        } else {
          return TextCellValue(value.toString());
        }
      }).toList();
      
      sheetObject.appendRow(cellValues);
    }

    // Encode and download
    var bytes = excel.encode();
    if (bytes != null) {
      if (kIsWeb) {
        final blob = html.Blob([bytes], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute("download", fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        // For mobile/desktop, we could use path_provider and open_file, 
        // but web is our primary target for admin dashboards.
        throw UnsupportedError("Excel export is currently only implemented for Web.");
      }
    }
  }
}