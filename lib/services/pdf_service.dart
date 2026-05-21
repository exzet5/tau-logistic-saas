import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:universal_html/html.dart' as html;

/// Service responsible for generating and downloading PDF documents 
/// (Barcodes and Deposit Forms).
class PdfService {
  
  /// Generates a PDF containing Code128 barcodes for the provided items.
  static Future<void> generateBarcodesPdf({
    required List<Map<String, String>> items, 
    required String fileNameLabel
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.rubikRegular();
      
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return [
            pw.Wrap(
              spacing: 15, 
              runSpacing: 15,
              children: items.map((item) {
                String code = item['id'] ?? '';
                String name = item['name'] ?? '';

                return pw.Container(
                  width: 113.4, 
                  height: 85.0, 
                  padding: const pw.EdgeInsets.all(4),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300, width: 0.5)
                  ),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text(
                        name, 
                        textDirection: pw.TextDirection.rtl, 
                        style: pw.TextStyle(font: font, fontSize: 8, fontWeight: pw.FontWeight.bold), 
                        maxLines: 1, 
                        overflow: pw.TextOverflow.clip
                      ),
                      pw.SizedBox(height: 4),
                      pw.Expanded(
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.code128(), 
                          data: code, 
                          drawText: false
                        )
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(code, style: const pw.TextStyle(fontSize: 9, letterSpacing: 2)),
                    ],
                  ),
                );
              }).toList(),
            )
          ];
        },
      ),
    );

    await _downloadOrSharePdf(pdf, 'Barcodes_${fileNameLabel}_${items.length}.pdf');
  }

  /// Generates a formal PDF document detailing borrowed equipment 
  /// and the required deposit for the customer to sign.
  static Future<void> generateDepositFormPdf({
    required String companyName,
    required String patientId, 
    required List<Map<String, String>> formattedItems, 
    required double totalCost, 
    required String staffName
  }) async {
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
                child: pw.Text(companyName, style: pw.TextStyle(font: fontBold, fontSize: 20, color: PdfColors.teal)),
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
                  pw.Text('מזהה לקוח: $patientId', style: pw.TextStyle(font: fontBold, fontSize: 16)),
                ]
              ),
              pw.SizedBox(height: 10),
              pw.Text('נמסר ע"י (איש צוות): $staffName', style: pw.TextStyle(font: font, fontSize: 14)),
              pw.SizedBox(height: 15),
              pw.Divider(),
              pw.SizedBox(height: 15),
              pw.Text('אני החתום/ה מטה מאשר/ת בזאת כי קיבלתי לידי את הציוד המפורט מטה, המהווה רכוש של $companyName.'),
              pw.SizedBox(height: 20),
              pw.Text('פירוט הציוד שהועבר לידיי:', style: pw.TextStyle(font: fontBold, decoration: pw.TextDecoration.underline)),
              pw.SizedBox(height: 10),
              ...formattedItems.map((item) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Text('• ${item['name']} [${item['group']}]  (מזהה: ${item['id']})  -  שווי: ₪${item['cost']}'),
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
              pw.Text('1. הציוד נמסר בהשאלה לתקופת השימוש בלבד.'),
              pw.SizedBox(height: 5),
              pw.Text('2. הנני מתחייב/ת לשמור על הציוד במצב תקין ולהחזירו ל-$companyName עם סיום השימוש.'),
              pw.SizedBox(height: 5),
              pw.Text('3. ידוע לי כי דמי הפיקדון יוחזרו במלואם רק עם החזרת הציוד בשלמותו.'),
              pw.SizedBox(height: 5),
              pw.Text('4. במקרה של אובדן או נזק משמעותי, החברה רשאית לחלט את הפיקדון.'),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('_______________________'),
                      pw.SizedBox(height: 5),
                      pw.Text('חתימת לקוח', style: pw.TextStyle(font: fontBold)),
                    ]
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('_______________________'),
                      pw.SizedBox(height: 5),
                      pw.Text('חתימת החברה', style: pw.TextStyle(font: fontBold)), 
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

    await _downloadOrSharePdf(pdf, 'Deposit_Form_$patientId.pdf');
  }

  static Future<void> _downloadOrSharePdf(pw.Document pdf, String fileName) async {
    final bytes = await pdf.save();
    if (kIsWeb) {
      final blob = html.Blob([bytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute("download", fileName)
        ..click();
      html.Url.revokeObjectUrl(url);
    } else {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    }
  }
}