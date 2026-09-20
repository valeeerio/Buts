import 'dart:io';

import 'package:buts/services/payslip_layouts/payslip_layout_registry.dart';
import 'package:buts/services/pdf_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _percorso = String.fromEnvironment('PAYSLIP_PDF');

/// Accettazione sul PDF REALE del layout "prestampato" (dati personali: vive
/// fuori dal repo, si passa il percorso a runtime). Verifica solo le identità
/// aritmetiche del cedolino, mai valori.
void main() {
  test(
    'PDF reale: riconosciuto, identità aritmetiche verificate',
    () {
      final bytes = File(_percorso).readAsBytesSync();
      final contenuto = const PdfImportService().leggiContenuto(bytes);
      final r = PayslipLayoutRegistry.standard.estrai(contenuto);

      expect(r, isNotNull, reason: 'nessun layout ha riconosciuto il PDF');
      expect(r!.layoutId, 'prestampato');
      expect(r.periodo, matches(RegExp(r'^\d{4}-\d{2}$')));
      expect(r.lordoVerificato, isTrue, reason: r.warnings.join(' | '));
      expect(r.trattenuteVerificate, isTrue, reason: r.warnings.join(' | '));
      expect(r.nettoVerificato, isTrue, reason: r.warnings.join(' | '));
      expect(r.competenze, isNotEmpty);
      expect(r.ferieResidue, greaterThanOrEqualTo(0));
      expect(r.rolResidui, greaterThanOrEqualTo(0));
    },
    skip: _percorso.isEmpty ? 'PAYSLIP_PDF non impostato' : false,
  );
}
