import 'package:buts/services/payslip_layouts/prestampato_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

import 'prestampato_fixture.dart';

void main() {
  final pagine = [paginaSegue(), paginaDati()];

  test('periodo LUG.2026 -> 2026-07', () {
    expect(classificaPrestampato(pagine).periodo, '2026-07');
  });

  test('mesi abbreviati: tutti mappati', () {
    // Usa la pagina dati sostituendo solo il token del periodo.
    for (final (abbr, mm) in const [
      ('GEN', '01'), ('FEB', '02'), ('MAR', '03'), ('APR', '04'),
      ('MAG', '05'), ('GIU', '06'), ('LUG', '07'), ('AGO', '08'),
      ('SET', '09'), ('OTT', '10'), ('NOV', '11'), ('DIC', '12'),
    ]) {
      final p = [
        for (final parola in paginaDati())
          parola.testo == 'LUG.2026'
              ? w('$abbr.2026', parola.bordoSinistro, parola.bordoDestro,
                  parola.bordoSuperiore)
              : parola,
      ];
      expect(classificaPrestampato([p]).periodo, '2026-$mm');
    }
  });

  test('la pagina dei totali è quella con il valore sotto Totale Competenze',
      () {
    // Pagina 0 (SEGUE) senza valori NON deve essere scelta: ore lavorate
    // sono lette da una sola pagina, il totale vale 1.088,01 solo in pagina 1.
    final r = classificaPrestampato(pagine);
    expect(r.warnings, isNot(contains('pagina dei totali non trovata')));
  });

  test('regge anche l\'ordine invertito e la pagina singola', () {
    expect(classificaPrestampato([paginaDati()]).periodo, '2026-07');
    expect(classificaPrestampato([paginaDati(), paginaSegue()]).periodo,
        '2026-07');
  });

  test('ore lavorate: prima parola numerica della riga, non "ore retribuite"',
      () {
    expect(classificaPrestampato(pagine).oreLavorate, closeTo(160.0, 0.001));
  });

  test('nessuna pagina utile -> warning e campi principali assenti', () {
    final r = classificaPrestampato([paginaSegue()]);
    expect(r.periodo, isNotNull); // il periodo è nell'intestazione fissa
    expect(r.warnings, contains('pagina dei totali non trovata'));
    expect(r.netto, isNull);
  });

  test('pagine illeggibili (null) non sollevano', () {
    final r = classificaPrestampato([null, null]);
    expect(r.periodo, isNull);
    expect(r.netto, isNull);
    expect(r.warnings, contains('periodo non trovato'));
  });
}
