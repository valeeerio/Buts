import 'dart:ui';

import 'package:buts/services/pdf_import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  test('leggiContenuto: testo e parole con coordinate per pagina', () {
    final doc = PdfDocument();
    final font = PdfStandardFont(PdfFontFamily.helvetica, 12);
    doc.pages.add().graphics.drawString(
          'Totale 100,00',
          font,
          bounds: const Rect.fromLTWH(10, 10, 300, 20),
        );
    doc.pages.add().graphics.drawString(
          'Seconda 200,00',
          font,
          bounds: const Rect.fromLTWH(10, 10, 300, 20),
        );
    final bytes = doc.saveSync();
    doc.dispose();

    final contenuto = const PdfImportService().leggiContenuto(bytes);

    expect(contenuto.testo, contains('Totale'));
    expect(contenuto.paroleAPagina, hasLength(2));
    expect(contenuto.paroleAPagina[0]!.any((p) => p.testo == '100,00'), isTrue);
    expect(contenuto.paroleAPagina[1]!.any((p) => p.testo == '200,00'), isTrue);
    expect(contenuto.primaPagina, same(contenuto.paroleAPagina[0]));
  });
}
