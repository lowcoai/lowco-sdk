// The Lowco API quickstart with lowcoai_api: a UPI QR code, then a GST
// invoice extracted as a job and waited for. Run with LOWCO_API_KEY set to a
// test key (lc_test_…) and invoice.pdf in the working directory.
import 'dart:convert';
import 'dart:io';

import 'package:lowcoai_api/lowcoai_api.dart';

Future<void> main() async {
  final lowco = LowcoApi(); // reads LOWCO_API_KEY
  try {
    // 1. A UPI payment QR code, as the PNG itself
    final qr = await lowco.qr.generate(
        const QrGenerateParams(type: 'upi', pa: 'acme@okhdfcbank', pn: 'Acme Traders', am: '1499.00', tn: 'INV-2026-0042'),
        const CallOptions(accept: 'image/png'));
    File('qr.png').writeAsBytesSync(qr.bytes!);
    print('qr.png written (${qr.bytes!.length} bytes)');

    // 2. A GST invoice, submitted as a job and waited for
    final answer = await lowco.docai.invoice(DocaiInvoiceParams(file: FileInput.path('invoice.pdf')), const CallOptions(mode: 'async'));
    print('job ${answer.job!.status}');
    final invoice = await lowco.waitForResult(answer, InvoiceResult.fromJson);
    for (final (name, f) in [('invoice_number', invoice.invoiceNumber), ('seller_gstin', invoice.seller?.gstin), ('total', invoice.total)]) {
      final v = f?.value;
      print('$name: ${v is String ? v : jsonEncode(v)} (confidence ${f?.confidence})');
    }
  } on LowcoApiError catch (e) {
    stderr.writeln('${e.reason}: ${e.message} (${e.docUrl}, request ${e.requestId})');
    exitCode = 1;
  } finally {
    lowco.close();
  }
}
