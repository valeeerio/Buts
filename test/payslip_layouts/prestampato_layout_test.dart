import 'package:buts/services/payslip_layouts/job_layout.dart';
import 'package:buts/services/payslip_layouts/payslip_layout_registry.dart';
import 'package:buts/services/payslip_layouts/pdf_contenuto.dart';
import 'package:buts/services/payslip_layouts/prestampato_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import 'prestampato_fixture.dart';

// Firma testuale del layout (etichette del modulo, presenti nel testo
// linearizzato di Syncfusion) e testo JOB sintetico.
const _testoPrestampato = 'ELEMENTI DELLA RETRIBUZIONE Periodo di retribuzione '
    'Netto da pagare Totale Competenze Totale ritenute';
const _testoJob = 'JOB - Copyright Sistemi S.p.A. - Autorizzazione INAIL '
    'Retribuzione ordinaria';

PdfContenuto _contenutoPrestampato() => PdfContenuto(
      testo: _testoPrestampato,
      paroleAPagina: [paginaSegue(), paginaDati()],
    );

void main() {
  const layout = PrestampatoLayout();

  test('id stabile', () => expect(layout.id, 'prestampato'));

  test('riconosce il proprio testo', () {
    expect(layout.riconosce(const PdfContenuto(testo: _testoPrestampato)),
        isTrue);
  });

  test('riconosce anche con spazi/a-capo diversi', () {
    expect(
      layout.riconosce(const PdfContenuto(
        testo: 'ELEMENTI  DELLA\nRETRIBUZIONE ... Periodo di\r\nretribuzione',
      )),
      isTrue,
    );
  });

  test('non-ambiguità: non riconosce JOB, JOB non riconosce lui', () {
    expect(layout.riconosce(const PdfContenuto(testo: _testoJob)), isFalse);
    expect(
        const JobLayout()
            .riconosce(const PdfContenuto(testo: _testoPrestampato)),
        isFalse);
  });

  test('senza testo non riconosce', () {
    expect(layout.riconosce(const PdfContenuto()), isFalse);
  });

  test('il registro standard sceglie il layout giusto e stampa layoutId', () {
    final r = PayslipLayoutRegistry.standard.estrai(_contenutoPrestampato());
    expect(r, isNotNull);
    expect(r!.layoutId, 'prestampato');
    expect(r.periodo, '2026-07');
    expect(r.nettoVerificato, isTrue);
  });

  test('il registro standard sceglie JOB per un testo JOB', () {
    final r = PayslipLayoutRegistry.standard
        .estrai(const PdfContenuto(testo: _testoJob));
    expect(r?.layoutId, 'job');
  });
}
