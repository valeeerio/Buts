import 'dart:io';

import 'package:buts/services/payslip_layouts/payslip_layout_registry.dart';
import 'package:buts/services/pdf_import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Test di ACCETTAZIONE (non un unit test puro, a differenza di
/// `test/pdf_voci_coordinate_test.dart`) su cedolini REALI: verifica che
/// il percorso reale dell'app (`PdfImportService.leggiContenuto` +
/// `PayslipLayoutRegistry.standard.estrai`, che per i cedolini JOB usa il
/// percorso a coordinate, vedi `classificaVociDaCoordinate`) ricostruisca
/// ESATTAMENTE lordo/netto/somma trattenute dai totali stampati sulla riga
/// finale del cedolino, su tutti i PDF reali disponibili — non solo sulle
/// fixture sintetiche dell'altro file.
///
/// PRIVACY (non negoziabile): questi PDF contengono dati personali reali
/// (nome, codice fiscale, IBAN, indirizzo, stipendio) e vivono SOLO su
/// questa macchina, fuori dal repository — nessun file/testo/dato viene
/// copiato qui. Il test legge i file dal filesystem a runtime e fa SKIP
/// (non fallisce) se la cartella non esiste, così resta eseguibile
/// (silenziosamente saltato) su qualunque altra macchina/CI.
void main() {
  const baseDir = '/Users/valeriomortella/Documents/Lavoro/GTS/Buste paghe';

  if (!Directory(baseDir).existsSync()) {
    test(
      'PDF reali non disponibili su questa macchina — test saltato',
      () {},
      skip: 'cartella "$baseDir" non trovata: test di accettazione valido '
          'solo sulla macchina con i PDF reali di riferimento',
    );
    return;
  }

  final percorsi = <String>[
    for (final sottocartella in ['2025', '2026'])
      if (Directory(p.join(baseDir, sottocartella)).existsSync())
        for (final f in Directory(p.join(baseDir, sottocartella)).listSync())
          if (f.path.toLowerCase().endsWith('.pdf')) f.path,
  ]..sort();

  const importService = PdfImportService();

  // Stessa stringa di `BustaPagaRegexParser.chiaveArrotondamento`
  // (privata, non importabile): la differenza di arrotondamento ARR.
  // PRECED./ARR. ATTUALE non fa parte del "TOTALE TRATTENUTE" stampato sul
  // PDF (è un aggiustamento separato, sommato solo nel netto derivato), va
  // esclusa dalla somma sotto per confrontarla correttamente con quel
  // totale — vedi `BustaPagaRegexParser._trattenuteDaCoordinate`, che fa
  // internamente lo stesso confronto (lì solo un warning, qui
  // un'asserzione dura).
  const chiaveArrotondamento =
      'Differenza di arrotondamento (mese precedente/attuale)';

  test('almeno un PDF reale trovato sulla macchina di sviluppo', () {
    expect(percorsi, isNotEmpty,
        reason: 'cartella "$baseDir" presente ma senza PDF nelle '
            'sottocartelle 2025/2026');
  });

  for (final path in percorsi) {
    test(
        'estrazione per coordinate coerente con i totali stampati: '
        '${p.basename(path)}', () {
      final bytes = File(path).readAsBytesSync();
      final contenuto = importService.leggiContenuto(bytes);
      expect(contenuto.testo, isNotNull,
          reason: 'nessun testo estraibile da $path');

      const registro = PayslipLayoutRegistry.standard;
      expect(registro.rileva(contenuto)?.id, 'job',
          reason: 'layout non riconosciuto come "job" su $path');
      final risultato = registro.estrai(contenuto);
      expect(risultato, isNotNull, reason: 'nessun layout per $path');
      expect(risultato!.layoutId, 'job');

      // Totali stampati sulla riga finale, riletti per coordinate dalla
      // prima pagina (stessa funzione pura usata dal layout).
      final parole = contenuto.primaPagina;
      expect(parole, isNotNull,
          reason: 'prima pagina non leggibile per coordinate su $path');
      final voci = classificaVociDaCoordinate(parole!);
      expect(voci.haDatiSufficienti, isTrue,
          reason: 'dati insufficienti dal percorso a coordinate su $path');
      final totali = voci.totali!;

      // --- lordo == TOTALE COMPETENZE ---
      expect(risultato.lordo, isNotNull,
          reason: 'lordo non calcolato per $path');
      expect(
        risultato.lordo,
        closeTo(totali.totaleCompetenze, 0.01),
        reason: 'lordo (€${risultato.lordo}) non coincide col TOTALE '
            'COMPETENZE stampato (€${totali.totaleCompetenze}) su $path',
      );

      // --- netto == NETTO IN BUSTA ---
      expect(risultato.netto, isNotNull,
          reason: 'netto non calcolato per $path');
      expect(
        risultato.netto,
        closeTo(totali.nettoInBusta, 0.01),
        reason: 'netto (€${risultato.netto}) non coincide col NETTO IN '
            'BUSTA stampato (€${totali.nettoInBusta}) su $path',
      );

      // --- Σ trattenute (esclusa la voce di arrotondamento, che non fa
      // parte del totale stampato sul PDF) == TOTALE TRATTENUTE ---
      final sommaTrattenuteNominate = risultato.trattenute.entries
          .where((e) => e.key != chiaveArrotondamento)
          .fold(0.0, (somma, e) => somma + e.value);
      expect(
        sommaTrattenuteNominate,
        closeTo(totali.totaleTrattenute, 0.01),
        reason: 'somma trattenute (€$sommaTrattenuteNominate) non coincide '
            'col TOTALE TRATTENUTE stampato (€${totali.totaleTrattenute}) '
            'su $path — dettaglio: ${risultato.trattenute}',
      );

      // Nessun warning di divergenza/dato mancante originato dal percorso a
      // coordinate: se le 3 identità sopra tornano ma il parser aveva
      // comunque segnalato un'incongruenza (es. su un campo non coperto
      // dalle asserzioni sopra), è comunque un sintomo da correggere, non
      // da ignorare silenziosamente.
      final warningsRilevanti = risultato.warnings
          .where((w) => w.contains('diverge') || w.contains('dalle coordinate'))
          .toList();
      expect(
        warningsRilevanti,
        isEmpty,
        reason: 'warning inattesi dal percorso a coordinate su $path: '
            '$warningsRilevanti',
      );

      // --- regressione: descrizioni spezzate a metà parola (vedi
      // `_unisciParoleDescrizione` in `pdf_import_service.dart`) — su questa
      // macchina di sviluppo il bug produceva letteralmente "Fe stivita'"
      // (invece di "Festivita'") e "Tr attamento integrativo DL 3/2020"
      // (invece di "Trattamento integrativo DL 3/2020") su più cedolini
      // reali. Nessuna descrizione dev'essere corrotta. Solo termini
      // generici di un provvedimento fiscale nazionale (DL 3/2020) e di una
      // voce standard di cedolino, non dati personali. ---
      const descrizioniCorrotteNote = ['Fe stivita', 'Tr attamento'];
      for (final descrizione
          in risultato.competenze.map((v) => v.descrizione)) {
        for (final corrotta in descrizioniCorrotteNote) {
          expect(
            descrizione.contains(corrotta),
            isFalse,
            reason: 'descrizione competenza "$descrizione" su $path '
                'contiene il pattern spezzato "$corrotta"',
          );
        }
      }
    });
  }
}
