import 'package:buts/models/busta_paga.dart';
import 'package:buts/services/busta_paga_regex_parser.dart';
import 'package:buts/services/payslip_layouts/job_layout.dart';
import 'package:buts/services/payslip_layouts/pdf_contenuto.dart';
import 'package:flutter_test/flutter_test.dart';

const _testoJob = '''
JOB - Copyright Sistemi S.p.A. - Autorizzazione INAIL   N°  792   del  03/01/20185MARZO 2026
Retribuzione ordinaria
GIORNI
20,000 50,00000 1.000,00
INPS1.050,00 5,84061,32 CONTRIBUTO EBILOG0,50 3,50
Firma per quietanza
1.050,00 61,32-988,68
''';

void main() {
  const layout = JobLayout();

  test('id stabile', () => expect(layout.id, kLayoutPredefinito));

  test('riconosce il testo JOB', () {
    expect(layout.riconosce(const PdfContenuto(testo: _testoJob)), isTrue);
  });

  test('non riconosce un testo di altro software paghe', () {
    const altro = 'ELEMENTI DELLA RETRIBUZIONE Periodo di retribuzione LUG.2026';
    expect(layout.riconosce(const PdfContenuto(testo: altro)), isFalse);
  });

  test('estrai == BustaPagaRegexParser.parse (senza coordinate)', () {
    final atteso = const BustaPagaRegexParser().parse(_testoJob);
    final ottenuto = layout.estrai(const PdfContenuto(testo: _testoJob));
    expect(ottenuto.netto, atteso.netto);
    expect(ottenuto.lordo, atteso.lordo);
    expect(ottenuto.periodo, atteso.periodo);
    expect(ottenuto.layoutId, 'job');
  });
}
