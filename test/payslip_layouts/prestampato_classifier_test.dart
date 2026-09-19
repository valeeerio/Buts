import 'package:buts/services/payslip_layouts/pdf_contenuto.dart';
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
    // Netto e ore lavorate esistono solo in pagina 1 (paginaSegue non ha
    // valori sotto Totale Competenze): se fosse scelta la pagina SEGUE
    // sarebbero assenti.
    for (final ordine in [
      [paginaSegue(), paginaDati()],
      [paginaDati(), paginaSegue()],
    ]) {
      final r = classificaPrestampato(ordine);
      expect(r.netto, closeTo(787.99, 0.001));
      expect(r.oreLavorate, closeTo(160.0, 0.001));
      expect(r.warnings, isNot(contains('pagina dei totali non trovata')));
    }
  });

  group('netto', () {
    List<ParolaVoce> senzaEtichettaBasso() => [
          for (final p in paginaDati())
            if (!(const {'NETTO', 'DA', 'PAGARE'}).contains(p.testo)) p,
        ];
    List<ParolaVoce> conAltoDiverso(List<ParolaVoce> parole) => [
          for (final p in parole)
            p.testo == '787,99' && p.bordoSuperiore == 215.7
                ? w('777,77', p.bordoSinistro, p.bordoDestro,
                    p.bordoSuperiore)
                : p,
        ];

    test('in basso: 787,99', () {
      expect(classificaPrestampato(pagine).netto, closeTo(787.99, 0.001));
    });

    test('ripiego sul riquadro in alto, senza confondersi col CF', () {
      final r = classificaPrestampato([conAltoDiverso(senzaEtichettaBasso())]);
      expect(r.netto, closeTo(777.77, 0.001));
    });

    test('il netto in basso ha priorità su quello in alto', () {
      final r = classificaPrestampato([conAltoDiverso(paginaDati())]);
      expect(r.netto, closeTo(787.99, 0.001));
    });

    test('senza alcun valore netto: warning e null', () {
      final p = [
        for (final x in senzaEtichettaBasso())
          if (!(x.testo == '787,99' && x.bordoSuperiore == 215.7)) x,
      ];
      final r = classificaPrestampato([p]);
      expect(r.netto, isNull);
      expect(r.warnings, contains('netto non trovato'));
    });

    test('senza valore ore lavorate: warning e null', () {
      final p = [
        for (final x in paginaDati())
          if (x.testo != '160,00') x,
      ];
      final r = classificaPrestampato([p]);
      expect(r.oreLavorate, isNull);
      expect(r.warnings, contains('ore lavorate non determinabili'));
    });
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

  group('ratei', () {
    test('Ferie: spett. = maturato, residue = residuo stampato, godute vuote = 0',
        () {
      final r = classificaPrestampato(pagine);
      expect(r.ferieMaturate, closeTo(35.0, 0.001));
      expect(r.ferieGodute, closeTo(0.0, 0.001));
      expect(r.ferieResidue, closeTo(45.0, 0.001));
    });

    test('ROL: maturati/goduti/residui; permessiGoduti = ROL goduti', () {
      final r = classificaPrestampato(pagine);
      expect(r.rolMaturati, closeTo(56.0, 0.001));
      expect(r.rolGoduti, closeTo(30.0, 0.001));
      expect(r.rolResidui, closeTo(46.0, 0.001));
      expect(r.permessiGoduti, closeTo(30.0, 0.001));
      expect(r.permessiGodutiMese, 0);
    });

    test('Ex festività: etichetta presente e celle vuote -> 0', () {
      final r = classificaPrestampato(pagine);
      expect(r.exFestivitaMaturate, 0);
      expect(r.exFestivitaGodute, 0);
      expect(r.exFestivitaResidue, 0);
    });

    test('la parola "rateo m.:NN,NN" non è un saldo', () {
      final r = classificaPrestampato(pagine);
      expect(r.ferieMaturate, isNot(closeTo(5.0, 0.001)));
    });

    test('etichette assenti -> warning e zeri', () {
      final r = classificaPrestampato([
        [
          for (final p in paginaDati())
            if (p.testo != 'Ferie' && p.testo != 'ROL') p,
        ],
      ]);
      expect(r.warnings, contains('dati ferie non trovati'));
      expect(r.warnings, contains('dati ROL non trovati'));
    });
  });
}
