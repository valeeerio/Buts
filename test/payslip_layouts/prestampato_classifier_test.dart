import 'package:buts/services/busta_paga_regex_parser.dart';
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
      expect(r.warnings.where((s) => s.contains('ex festività')), isEmpty);
      expect(r.exFestivitaMaturate, 0);
      expect(r.exFestivitaGodute, 0);
      expect(r.exFestivitaResidue, 0);
    });

    test('la parola "rateo m.:NN,NN" non è un saldo', () {
      final r = classificaPrestampato(pagine);
      expect(r.ferieMaturate, isNot(closeTo(5.0, 0.001)));
    });

    List<ParolaVoce> conValore(String da, String a) => [
          for (final p in paginaDati())
            p.testo == da
                ? w(a, p.bordoSinistro, p.bordoDestro, p.bordoSuperiore)
                : p,
        ];

    test('identità ratei coerente (Ferie godute vuote): nessun warning', () {
      final r = classificaPrestampato(pagine);
      expect(r.warnings.where((s) => s.startsWith('ratei')), isEmpty);
    });

    test('residuo ROL incoerente -> warning specifico solo per ROL', () {
      final r = classificaPrestampato([conValore('46,00', '47,00')]);
      expect(r.warnings.where((s) => s.startsWith('ratei ROL non coerenti')),
          hasLength(1));
      expect(r.warnings.where((s) => s.startsWith('ratei ferie')), isEmpty);
    });

    test('residuo Ferie incoerente -> warning specifico solo per ferie', () {
      final r = classificaPrestampato([conValore('45,00', '50,00')]);
      expect(r.warnings.where((s) => s.startsWith('ratei ferie non coerenti')),
          hasLength(1));
      expect(r.warnings.where((s) => s.startsWith('ratei ROL')), isEmpty);
    });

    test('Ferie a.p. modificato -> warning ferie', () {
      final r = classificaPrestampato([conValore('10,00', '11,00')]);
      expect(r.warnings.where((s) => s.startsWith('ratei ferie non coerenti')),
          hasLength(1));
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

  group('voci, trattenute, verifiche', () {
    test('competenze lette da TUTTE le pagine, senza deduplicare', () {
      final r = classificaPrestampato(pagine);
      expect(r.competenze.map((v) => v.descrizione),
          ['ORE ORD.', 'ROL GODUTI']);
      expect(r.competenze[0].quantita, closeTo(100.0, 0.001));
      expect(r.competenze[0].importo, closeTo(1000.0, 0.001));
      expect(r.competenze[1].quantita, closeTo(8.0, 0.001));
      expect(r.competenze[1].importo, closeTo(88.0, 0.001));
      expect(r.lordo, closeTo(1088.0, 0.001));
    });

    test(
        'trattenute: CTR FPLD -> INPS, IRPEF NETTA -> IRPEF, righe informative escluse',
        () {
      final r = classificaPrestampato(pagine);
      expect(r.trattenute['INPS'], closeTo(100.0, 0.001));
      expect(r.trattenute['IRPEF'], closeTo(200.0, 0.001));
      expect(r.trattenute.keys, isNot(contains('IMPONIBILE IRPEF')));
    });

    test('arrotondamento = arrPrec - arrAtt nella chiave del parser JOB', () {
      final r = classificaPrestampato(pagine);
      expect(
        r.trattenute[BustaPagaRegexParser.chiaveArrotondamento],
        closeTo(0.01, 0.0005),
      );
    });

    test('netto derivato = lordo - trattenute e coincide con il stampato', () {
      final r = classificaPrestampato(pagine);
      expect(r.netto, closeTo(787.99, 0.005));
    });

    test('flag di verifica veri quando le identità tornano', () {
      final r = classificaPrestampato(pagine);
      expect(r.lordoVerificato, isTrue);
      expect(r.trattenuteVerificate, isTrue);
      expect(r.nettoVerificato, isTrue);
      expect(r.warnings, isEmpty);
    });

    test('totale divergente -> flag falso e warning', () {
      final pagineRotte = [
        paginaSegue(),
        [
          for (final p in paginaDati())
            p.testo == '1.088,01'
                ? w('1.099,99', p.bordoSinistro, p.bordoDestro,
                    p.bordoSuperiore)
                : p,
        ],
      ];
      final r = classificaPrestampato(pagineRotte);
      expect(r.lordoVerificato, isFalse);
      expect(r.nettoVerificato, isFalse);
      expect(r.warnings.any((s) => s.contains('lordo calcolato')), isTrue);
    });

    test('nessuna voce di competenza letta -> warning, lordo null, flag falsi',
        () {
      final senzaVoci = [
        for (final pagina in [paginaSegue(), paginaDati()])
          [
            for (final p in pagina)
              if (p.bordoSuperiore != 351.3) p,
          ],
      ];
      final r = classificaPrestampato(senzaVoci);
      expect(r.competenze, isEmpty);
      expect(r.warnings, contains('nessuna voce di competenza trovata'));
      expect(r.lordo, isNull);
      expect(r.lordoVerificato, isFalse);
      expect(r.nettoVerificato, isFalse);
    });

    test('nessuna trattenuta letta con totale ritenute stampato -> warning',
        () {
      final senzaTrattenute = [
        for (final pagina in [paginaSegue(), paginaDati()])
          [
            for (final p in pagina)
              if (p.bordoSuperiore != 362.6 && p.bordoSuperiore != 373.9) p,
          ],
      ];
      final r = classificaPrestampato(senzaTrattenute);
      expect(r.warnings, contains('nessuna trattenuta trovata'));
      expect(r.trattenuteVerificate, isFalse);
      expect(r.nettoVerificato, isFalse);
    });

    test('straordinari: somma ore delle voci "Straordinario…"', () {
      final r = classificaPrestampato(pagine);
      expect(r.straordinari, 0);
    });
  });
}
