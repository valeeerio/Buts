# Layout "prestampato" (secondo layout PDF) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Regole di progetto (CLAUDE.md, prevalgono):** sviluppo Dart sempre delegato a
> dev1/dev2; dopo ogni run di dev, `revisore` con lo stesso scope; verifiche solo
> statiche (`flutter analyze`, `flutter test`), mai avviare l'app; i comandi git
> che modificano il repo partono solo su istruzione dell'utente (l'utente ha
> autorizzato i commit di questo lavoro con "confermo procedi", 2026-09-20; niente
> push/merge).

**Goal:** Implementare il parser del secondo layout di cedolino PDF (software paghe
diverso da "JOB", chiamato provvisoriamente `prestampato`) e registrarlo nel
`PayslipLayoutRegistry`, così l'import lo riconosce da solo.

**Architecture:** Una funzione pura `classificaPrestampato` (parole con coordinate
per pagina → `BustaPagaEstratti`), testabile con fixture sintetiche senza PDF,
avvolta da `PrestampatoLayout implements PayslipLayout` (`riconosce` + `estrai`).
Ogni ancora è **relativa all'etichetta della stessa pagina** (le Y traslano di
~11,3 pt fra pagine); le colonne si agganciano per **bordo destro** con tolleranza.
Stesse convenzioni del parser JOB: `lordo = somma voci`, `netto = lordo −
trattenute`, arrotondamento in trattenute con chiave
`Differenza di arrotondamento (mese precedente/attuale)` = `arrPrec − arrAtt`.

**Tech Stack:** Flutter/Dart, `flutter_test`, `syncfusion_flutter_pdf` (solo per il
test di accettazione opzionale sul PDF reale).

**Spec:** `docs/superpowers/specs/2026-09-19-payslip-layouts-design.md` (sez. 3) e
**ancore**: `docs/superpowers/specs/2026-09-19-payslip-layout-nuovo-coordinate.md`
(fonte unica di ogni numero X/Y usato qui).

## Global Constraints

- Nessuna modifica UI; nessun colore/token nuovo.
- **Privacy:** il PDF di esempio (fuori dal repo) contiene dati personali: mai
  copiare percorso, nomi, CF, azienda, valori reali nel repo, nei test, nei commit o
  nei report. Fixture solo sintetiche con valori fittizi; il test di accettazione
  sul PDF reale asserisce solo **identità** (flag di verifica), mai valori.
- Il comportamento del layout JOB non cambia: tutti i test esistenti passano senza
  modifiche alle asserzioni.
- Ancore sempre relative all'etichetta della pagina; celle vuote = nessuna parola;
  scartare le parole di solo spazio (`trim().isEmpty`).
- Mappatura ratei (confermata dall'utente, 2026-09-20): `maturato` = "spett."
  (cumulato dell'anno corrente, come JOB), `goduto` = goduti cumulati, `residuo` =
  residuo stampato (non ricalcolato), `residuoAnnoPrecedente` = "a.p."; il valore
  `rateo m.:NN,NN` va ignorato. `permessiGoduti` = ROL goduti (come in JOB),
  `permessiGodutiMese` = 0 (nessun equivalente nel layout).
- Identificatore persistito del layout: `'prestampato'` (nome provvisorio, vedi
  "Punti aperti": cambiarlo dopo il rilascio richiederebbe una migrazione).

## File Structure

| File | Responsabilità |
|------|----------------|
| `lib/services/payslip_layouts/prestampato_classifier.dart` (nuovo) | `classificaPrestampato` + helper privati puri |
| `lib/services/payslip_layouts/prestampato_layout.dart` (nuovo) | `PrestampatoLayout` (`id`, `riconosce`, `estrai`) |
| `lib/services/payslip_layouts/payslip_layout_registry.dart` (modifica) | aggiunge il layout a `standard` |
| `test/payslip_layouts/prestampato_fixture.dart` (nuovo) | costruttore di pagine sintetiche (solo helper, niente `main`) |
| `test/payslip_layouts/prestampato_classifier_test.dart` (nuovo) | test del classificatore |
| `test/payslip_layouts/prestampato_layout_test.dart` (nuovo) | riconoscimento, non-ambiguità con JOB, registro |
| `test/prestampato_acceptance_test.dart` (nuovo) | accettazione su PDF reale, saltata se non fornito |

---

### Task 5: Fixture sintetiche e campi di intestazione (pagina totali, periodo, netto, totali, ore)

**Files:**
- Create: `test/payslip_layouts/prestampato_fixture.dart`
- Create: `lib/services/payslip_layouts/prestampato_classifier.dart`
- Test: `test/payslip_layouts/prestampato_classifier_test.dart`

**Interfaces:**
- Produces:
  - `ParolaVoce w(String testo, double sinistra, double destra, double top)` (helper test)
  - `List<ParolaVoce> paginaDati({double dy = 0})` e `List<ParolaVoce> paginaSegue()` (helper test; pagina 1 = totali con `dy = 11.3`, pagina 0 = "SEGUE" con `dy = 0`)
  - `BustaPagaEstratti classificaPrestampato(List<List<ParolaVoce>?> pagine)`

- [ ] **Step 1: Scrivere il fixture e i test che falliscono**

`test/payslip_layouts/prestampato_fixture.dart` — valori FITTIZI, ancore da
`2026-09-19-payslip-layout-nuovo-coordinate.md` (sez. 3). `dy` è la traslazione
delle etichette che traslano (+11,3 in pagina 1); i blocchi FISSI (periodo, riquadro
netto, ore lavorate, testata tabella) non usano `dy`.

```dart
import 'package:buts/services/payslip_layouts/pdf_contenuto.dart';

ParolaVoce w(String testo, double sinistra, double destra, double top) => (
      testo: testo,
      bordoSuperiore: top,
      bordoSinistro: sinistra,
      bordoDestro: destra,
    );

/// Parole comuni a entrambe le pagine (blocchi FISSI + testata tabella).
List<ParolaVoce> _fissi() => [
      // Periodo (etichetta a 127,6, valore a 136,9).
      w('Periodo', 453.0, 478.0, 127.6),
      w('di', 479.7, 486.0, 127.6),
      w('retribuzione', 487.7, 515.5, 127.6),
      w('LUG.2026', 486.7, 523.3, 136.9),
      // Riquadro netto in alto (206,5 / 215,7) + un CF-like da scartare.
      w('Netto', 425.4, 448.0, 206.5),
      w('da', 449.7, 457.0, 206.5),
      w('pagare', 458.7, 472.7, 206.5),
      w('AAAAAA00A00A000A', 284.0, 365.0, 215.7),
      w('787,99', 535.0, 561.5, 215.7),
      // Ore lavorate (296,9 / 306,1) e ore retribuite.
      w('Ore', 72.7, 85.0, 296.9),
      w('lavorate', 86.7, 107.1, 296.9),
      w('160,00', 103.3, 127.9, 306.1),
      w('184,00', 164.0, 189.0, 306.1),
      // Testata tabella (331,9).
      w('COD.', 76.2, 90.0, 331.9),
      w('DESCRIZIONE', 162.4, 200.0, 331.9),
    ];

/// Pagina 1 (dati): etichette che traslano di [dy] rispetto alla pagina 0.
/// Valori fittizi coerenti: competenze 1.000,00 + 88,00 + arrAtt 0,01 =
/// 1.088,01; ritenute 100,00 + 200,00 + arrPrec 0,02 = 300,02; netto 787,99.
List<ParolaVoce> paginaDati({double dy = 11.3}) => [
      ..._fissi(),
      // Voce competenza (pagina 1): codice 42, "ROL GODUTI", 8,00 h, 88,00.
      w('42', 84.5, 93.3, 351.3),
      w('ROL', 107.4, 122.0, 351.3),
      w('GODUTI', 123.7, 160.0, 351.3),
      w('8,00', 305.0, 324.4, 351.3),
      w('11,0000', 362.8, 391.7, 351.3),
      w('88,00', 540.0, 561.5, 351.3),
      // Trattenute (senza codice): CTR FPLD e IRPEF NETTA.
      w('CTR', 107.4, 125.0, 362.6),
      w('FPLD', 126.7, 148.0, 362.6),
      w('100,00', 448.7, 473.3, 362.6),
      w('IRPEF', 107.4, 130.0, 373.9),
      w('NETTA', 131.7, 158.0, 373.9),
      w('200,00', 448.7, 473.3, 373.9),
      // Riga informativa senza importo in colonna competenze/ritenute.
      w('IMPONIBILE', 107.4, 160.0, 385.2),
      w('IRPEF', 161.7, 185.0, 385.2),
      w('1.500,00', 360.0, 392.0, 385.2),
      // Riga detrazioni/arrotondamenti (590,3 + dy) con valori a +9,3.
      w('Arrot.', 436.0, 453.0, 590.3 + dy),
      w('precedente', 454.7, 490.0, 590.3 + dy),
      w('Arrot.', 500.0, 517.0, 590.3 + dy),
      w('attuale', 518.7, 540.0, 590.3 + dy),
      w('0,02', 457.2, 472.8, 599.6 + dy),
      w('0,01', 545.2, 560.7, 599.6 + dy),
      // Totali (612,8 + dy) con valori a +9,3.
      w('Totale', 397.9, 425.0, 612.8 + dy),
      w('ritenute', 426.7, 437.8, 612.8 + dy),
      w('Totale', 479.0, 505.0, 612.8 + dy),
      w('Competenze', 506.7, 533.7, 612.8 + dy),
      w('300,02', 448.7, 473.3, 622.1 + dy),
      w('1.088,01', 530.2, 561.4, 622.1 + dy),
      // Ratei: etichette (635,4 + dy) e valori a +12,8. Esempio FITTIZIO:
      // Ferie a.p. 10,00 + spett. 35,00 = residue 45,00 (godute vuote);
      // ROL a.p. 20,00 + spett. 56,00 - goduti 30,00 = residui 46,00.
      w('Ferie', 72.7, 87.0, 635.4 + dy),
      w('a.p.', 88.7, 99.1, 635.4 + dy),
      w('Ferie', 113.5, 127.0, 635.4 + dy),
      w('spett.', 128.7, 144.8, 635.4 + dy),
      w('Ferie', 153.8, 167.0, 635.4 + dy),
      w('godute', 168.7, 189.0, 635.4 + dy),
      w('Ferie', 194.8, 208.0, 635.4 + dy),
      w('residue', 209.7, 231.2, 635.4 + dy),
      w('ROL', 235.0, 247.0, 635.4 + dy),
      w('a.p.', 248.7, 259.9, 635.4 + dy),
      w('ROL', 275.8, 288.0, 635.4 + dy),
      w('spett.', 289.7, 305.7, 635.4 + dy),
      w('ROL', 316.1, 328.0, 635.4 + dy),
      w('goduti', 329.7, 347.7, 635.4 + dy),
      w('ROL', 357.0, 369.0, 635.4 + dy),
      w('residui', 370.7, 390.1, 635.4 + dy),
      w('rateo', 130.0, 142.0, 641.7 + dy),
      w('m.:5,00', 143.7, 160.0, 641.7 + dy),
      w('10,00', 89.8, 109.8, 648.2 + dy),
      w('35,00', 130.3, 150.3, 648.2 + dy),
      w('45,00', 211.4, 231.4, 648.2 + dy),
      w('20,00', 251.9, 271.9, 648.2 + dy),
      w('56,00', 292.6, 312.6, 648.2 + dy),
      w('30,00', 333.0, 353.0, 648.2 + dy),
      w('46,00', 373.8, 393.8, 648.2 + dy),
      // Ex festività: solo etichette (celle vuote).
      w('Ex', 72.7, 80.0, 658.1 + dy),
      w('fes.', 81.7, 92.0, 658.1 + dy),
      w('a.p.', 93.7, 104.0, 658.1 + dy),
      // Netto in basso (647,9 + dy), valore a +19,4.
      w('NETTO', 463.6, 490.0, 647.9 + dy),
      w('DA', 491.7, 499.0, 647.9 + dy),
      w('PAGARE', 500.7, 524.0, 647.9 + dy),
      w('787,99', 535.0, 561.4, 667.3 + dy),
    ];

/// Pagina 0: prime voci, marker "SEGUE ..", etichette totali SENZA valori.
List<ParolaVoce> paginaSegue() => [
      ..._fissi(),
      w('1', 84.5, 93.3, 351.3),
      w('ORE', 107.4, 125.0, 351.3),
      w('ORD.', 126.7, 148.0, 351.3),
      w('100,00', 299.6, 324.4, 351.3),
      w('10,0000', 362.8, 391.7, 351.3),
      w('1.000,00', 530.2, 561.5, 351.3),
      w('Arrot.', 436.0, 453.0, 590.3),
      w('precedente', 454.7, 490.0, 590.3),
      w('Totale', 397.9, 425.0, 612.8),
      w('ritenute', 426.7, 437.8, 612.8),
      w('Totale', 479.0, 505.0, 612.8),
      w('Competenze', 506.7, 533.7, 612.8),
      w('SEGUE', 466.0, 494.0, 667.3),
      w('..', 495.7, 500.0, 667.3),
    ];
```

`test/payslip_layouts/prestampato_classifier_test.dart`:

```dart
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
```

- [ ] **Step 2: Eseguire i test e verificare che falliscano**

Run: `flutter test test/payslip_layouts/prestampato_classifier_test.dart`
Expected: FAIL (`prestampato_classifier.dart` non esiste).

- [ ] **Step 3: Implementare lo scheletro del classificatore**

`lib/services/payslip_layouts/prestampato_classifier.dart` (in questo task: pagina
totali, periodo, netto, totali, ore; ratei/voci/trattenute sono aggiunti dai task
successivi, per ora restituiscono valori vuoti):

```dart
import '../../models/busta_paga.dart';
import '../busta_paga_regex_parser.dart';
import 'pdf_contenuto.dart';

// Ancore X (bordo destro) delle colonne, da
// docs/superpowers/specs/2026-09-19-payslip-layout-nuovo-coordinate.md.
const _xCompetenzeDestro = 561.4;
const _xRitenuteDestro = 473.3;
const _tolleranzaX = 4.0;

const _mesiAbbreviati = {
  'GEN': 1, 'FEB': 2, 'MAR': 3, 'APR': 4, 'MAG': 5, 'GIU': 6,
  'LUG': 7, 'AGO': 8, 'SET': 9, 'OTT': 10, 'NOV': 11, 'DIC': 12,
};

final _numero = RegExp(r'^-?(?:\d{1,3}(?:\.\d{3})+|\d+),\d+$');
final _periodo = RegExp(r'^([A-Z]{3})\.(\d{4})$');

double? _num(String testo) {
  final t = testo.trim();
  if (!_numero.hasMatch(t)) return null;
  return double.parse(t.replaceAll('.', '').replaceAll(',', '.'));
}

List<ParolaVoce> _pulite(List<ParolaVoce> parole) =>
    [for (final p in parole) if (p.testo.trim().isNotEmpty) p];

/// Prima occorrenza della sequenza di [token] sulla stessa riga (Y ±1,0), ogni
/// token a destra del precedente a meno di 6 pt. Restituisce Y e gli estremi X.
({double top, double sinistra, double destra})? _etichetta(
  List<ParolaVoce> parole,
  List<String> token,
) {
  for (final prima in parole) {
    if (prima.testo != token.first) continue;
    var ultima = prima;
    var trovata = true;
    for (final t in token.skip(1)) {
      final candidate = [
        for (final p in parole)
          if (p.testo == t &&
              (p.bordoSuperiore - prima.bordoSuperiore).abs() <= 1.0 &&
              p.bordoSinistro >= ultima.bordoDestro - 0.5 &&
              p.bordoSinistro - ultima.bordoDestro <= 6.0)
            p,
      ]..sort((a, b) => a.bordoSinistro.compareTo(b.bordoSinistro));
      if (candidate.isEmpty) {
        trovata = false;
        break;
      }
      ultima = candidate.first;
    }
    if (trovata) {
      return (
        top: prima.bordoSuperiore,
        sinistra: prima.bordoSinistro,
        destra: ultima.bordoDestro,
      );
    }
  }
  return null;
}

/// Primo valore numerico con Y in [dalTop, alTop] e bordo destro entro
/// [tolleranza] da [bordoDestro].
double? _valore(
  List<ParolaVoce> parole, {
  required double dalTop,
  required double alTop,
  required double bordoDestro,
  double tolleranza = _tolleranzaX,
}) {
  for (final p in parole) {
    if (p.bordoSuperiore < dalTop || p.bordoSuperiore > alTop) continue;
    if ((p.bordoDestro - bordoDestro).abs() > tolleranza) continue;
    final v = _num(p.testo);
    if (v != null) return v;
  }
  return null;
}

/// Indice dell'ULTIMA pagina che ha un valore sotto "Totale Competenze": le
/// pagine intermedie ("SEGUE ..") hanno le etichette ma nessun valore.
int? _indicePaginaTotali(List<List<ParolaVoce>?> pagine) {
  int? scelto;
  for (var i = 0; i < pagine.length; i++) {
    final grezza = pagine[i];
    if (grezza == null) continue;
    final parole = _pulite(grezza);
    final et = _etichetta(parole, ['Totale', 'Competenze']);
    if (et == null) continue;
    final v = _valore(
      parole,
      dalTop: et.top + 5,
      alTop: et.top + 14,
      bordoDestro: _xCompetenzeDestro,
    );
    if (v != null) scelto = i;
  }
  return scelto;
}

String? _periodoDa(List<List<ParolaVoce>?> pagine) {
  for (final grezza in pagine) {
    if (grezza == null) continue;
    final parole = _pulite(grezza);
    final et = _etichetta(parole, ['Periodo', 'di', 'retribuzione']);
    if (et == null) continue;
    for (final p in parole) {
      if (p.bordoSinistro < 450) continue;
      if (p.bordoSuperiore < et.top + 2 || p.bordoSuperiore > et.top + 16) {
        continue;
      }
      final m = _periodo.firstMatch(p.testo);
      final mese = m == null ? null : _mesiAbbreviati[m.group(1)!];
      if (m != null && mese != null) {
        return '${m.group(2)}-${mese.toString().padLeft(2, '0')}';
      }
    }
  }
  return null;
}

/// Converte le parole con coordinate di un cedolino del layout "prestampato"
/// in [BustaPagaEstratti]. Puro: nessuna dipendenza da Syncfusion. Tutte le
/// ancore sono relative all'etichetta della stessa pagina.
BustaPagaEstratti classificaPrestampato(List<List<ParolaVoce>?> pagine) {
  final warnings = <String>[];

  final periodo = _periodoDa(pagine);
  if (periodo == null) warnings.add('periodo non trovato');

  final indice = _indicePaginaTotali(pagine);
  List<ParolaVoce> parole = const [];
  if (indice == null) {
    warnings.add('pagina dei totali non trovata');
  } else {
    parole = _pulite(pagine[indice]!);
  }

  double? oreLavorate;
  if (parole.isNotEmpty) {
    final et = _etichetta(parole, ['Ore', 'lavorate']);
    if (et != null) {
      final candidati = [
        for (final p in parole)
          if (p.bordoSuperiore >= et.top + 5 &&
              p.bordoSuperiore <= et.top + 14 &&
              p.bordoSinistro < 150 &&
              _num(p.testo) != null)
            p,
      ]..sort((a, b) => a.bordoSinistro.compareTo(b.bordoSinistro));
      if (candidati.isNotEmpty) oreLavorate = _num(candidati.first.testo);
    }
    if (oreLavorate == null) warnings.add('ore lavorate non determinabili');
  }

  double? nettoStampato;
  if (parole.isNotEmpty) {
    final basso = _etichetta(parole, ['NETTO', 'DA', 'PAGARE']);
    if (basso != null) {
      nettoStampato = _valore(
        parole,
        dalTop: basso.top + 14,
        alTop: basso.top + 25,
        bordoDestro: _xCompetenzeDestro,
      );
    }
    if (nettoStampato == null) {
      final alto = _etichetta(parole, ['Netto', 'da', 'pagare']);
      if (alto != null) {
        nettoStampato = _valore(
          parole,
          dalTop: alto.top + 5,
          alTop: alto.top + 14,
          bordoDestro: _xCompetenzeDestro,
        );
      }
    }
    if (nettoStampato == null) warnings.add('netto non trovato');
  }

  return BustaPagaEstratti(
    periodo: periodo,
    netto: nettoStampato,
    trattenute: const {},
    straordinari: 0,
    ferieMaturate: 0,
    ferieGodute: 0,
    ferieResidue: 0,
    rolMaturati: 0,
    rolGoduti: 0,
    rolResidui: 0,
    permessiGoduti: 0,
    oreLavorate: oreLavorate,
    tipo: TipoBustaPaga.mensile,
    warnings: warnings,
  );
}
```

Nota: in questo task `_xRitenuteDestro` non è ancora usato; se `flutter analyze`
lo segnala come non usato, spostarne la dichiarazione nel Task 7.

- [ ] **Step 4: Eseguire test e analyzer**

Run: `flutter test test/payslip_layouts/prestampato_classifier_test.dart && flutter analyze`
Expected: PASS, nessun problema. Se un test rivela un errore di ancora rispetto al
documento di findings, correggi il **codice** (le regole del documento sono la
fonte); se il documento stesso è contraddetto dal PDF reale, riportalo nel report.

- [ ] **Step 5: Commit**

```bash
git add lib/services/payslip_layouts/prestampato_classifier.dart test/payslip_layouts
git commit -m "feat: classificatore prestampato — pagina totali, periodo, netto, ore"
```

---

### Task 6: Ratei Ferie / ROL / Ex festività

**Files:**
- Modify: `lib/services/payslip_layouts/prestampato_classifier.dart`
- Test: `test/payslip_layouts/prestampato_classifier_test.dart`

**Interfaces:**
- Consumes: `_etichetta`, `_valore`, `_pulite`, `classificaPrestampato` (Task 5), `RateoCategoria` (`busta_paga_regex_parser.dart`), fixture `paginaDati`/`paginaSegue`.
- Produces: campi `ferie*`, `rol*`, `exFestivita*`, `permessiGoduti` valorizzati in `BustaPagaEstratti`.

- [ ] **Step 1: Test che falliscono** (aggiungere in `main()` del test)

```dart
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
```

- [ ] **Step 2: Verificare che falliscano**

Run: `flutter test test/payslip_layouts/prestampato_classifier_test.dart`
Expected: FAIL (ratei a zero).

- [ ] **Step 3: Implementare**

Aggiungere in `prestampato_classifier.dart`, sotto le costanti:

```dart
// Bordi destri delle 4 colonne dei ratei (a.p., spett., godute, residue), da
// findings sez. 3. Ferie godute (~189) NON osservato: dedotto dall'etichetta.
// Le colonne Ex festività sono IPOTIZZATE uguali a quelle Ferie (celle vuote
// nell'unico PDF di esempio).
const _colonneFerie = [109.8, 150.3, 189.0, 231.4];
const _colonneRol = [271.9, 312.6, 353.0, 393.8];
```

e le funzioni:

```dart
/// Legge una riga di ratei ancorata alla sua etichetta "a.p." ([etichettaAp]).
/// I valori stanno a +12,8 pt (finestra +10..+16) e si assegnano per bordo
/// destro di colonna. Cella assente = 0 (una cella vuota non produce parole).
/// `null` se l'etichetta della riga non esiste sulla pagina.
RateoCategoria? _rateo(
  List<ParolaVoce> parole,
  List<String> etichettaAp,
  List<double> colonne,
) {
  final et = _etichetta(parole, etichettaAp);
  if (et == null) return null;
  double cella(double destro) =>
      _valore(
        parole,
        dalTop: et.top + 10,
        alTop: et.top + 16,
        bordoDestro: destro,
      ) ??
      0.0;
  return RateoCategoria(
    residuoAnnoPrecedente: cella(colonne[0]),
    maturato: cella(colonne[1]),
    goduto: cella(colonne[2]),
    residuo: cella(colonne[3]),
  );
}
```

In `classificaPrestampato`, prima del `return`:

```dart
  final ferie = parole.isEmpty
      ? null
      : _rateo(parole, ['Ferie', 'a.p.'], _colonneFerie);
  final rol =
      parole.isEmpty ? null : _rateo(parole, ['ROL', 'a.p.'], _colonneRol);
  final ex = parole.isEmpty
      ? null
      : _rateo(parole, ['Ex', 'fes.', 'a.p.'], _colonneFerie);
  if (parole.isNotEmpty) {
    if (ferie == null) warnings.add('dati ferie non trovati');
    if (rol == null) warnings.add('dati ROL non trovati');
    if (ex == null) warnings.add('dati ex festività non trovati');
  }
```

e nel `BustaPagaEstratti(` sostituire i campi ratei con:

```dart
    ferieMaturate: ferie?.maturato ?? 0,
    ferieGodute: ferie?.goduto ?? 0,
    ferieResidue: ferie?.residuo ?? 0,
    rolMaturati: rol?.maturato ?? 0,
    rolGoduti: rol?.goduto ?? 0,
    rolResidui: rol?.residuo ?? 0,
    permessiGoduti: rol?.goduto ?? 0,
    exFestivitaMaturate: ex?.maturato ?? 0,
    exFestivitaGodute: ex?.goduto ?? 0,
    exFestivitaResidue: ex?.residuo ?? 0,
```

(`RateoCategoria` è già importato via `busta_paga_regex_parser.dart`.)

- [ ] **Step 4: Test e analyze**

Run: `flutter test test/payslip_layouts/prestampato_classifier_test.dart && flutter analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/payslip_layouts/prestampato_classifier.dart test/payslip_layouts
git commit -m "feat: classificatore prestampato — ratei ferie, ROL, ex festività"
```

---

### Task 7: Voci di competenza, trattenute, arrotondamenti e verifiche

**Files:**
- Modify: `lib/services/busta_paga_regex_parser.dart` (rendere pubblica la chiave di arrotondamento)
- Modify: `lib/services/payslip_layouts/prestampato_classifier.dart`
- Test: `test/payslip_layouts/prestampato_classifier_test.dart`

**Interfaces:**
- Consumes: helper del Task 5, `computeLordo`/`computeStraordinari`/`computeNetto`/`VoceCompetenza` (`lib/models/busta_paga.dart`).
- Produces: `BustaPagaRegexParser.chiaveArrotondamento` (`static const String`, pubblica); `competenze`, `trattenute`, `lordo`, `netto`, `straordinari`, flag `lordoVerificato`/`trattenuteVerificate`/`nettoVerificato` valorizzati.

- [ ] **Step 1: Test che falliscono**

```dart
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

    test('trattenute: CTR FPLD -> INPS, IRPEF NETTA -> IRPEF, righe informative escluse',
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
            p.testo == '1.088,01' ? w('1.099,99', p.bordoSinistro, p.bordoDestro, p.bordoSuperiore) : p,
        ],
      ];
      final r = classificaPrestampato(pagineRotte);
      expect(r.lordoVerificato, isFalse);
      expect(r.nettoVerificato, isFalse);
      expect(r.warnings.any((s) => s.contains('lordo calcolato')), isTrue);
    });

    test('straordinari: somma ore delle voci "Straordinario…"', () {
      final r = classificaPrestampato(pagine);
      expect(r.straordinari, 0);
    });
  });
```

(aggiungere gli import `package:buts/services/busta_paga_regex_parser.dart` in testa
al file di test.)

- [ ] **Step 2: Verificare che falliscano**

Run: `flutter test test/payslip_layouts/prestampato_classifier_test.dart`
Expected: FAIL (`chiaveArrotondamento` non definita; competenze vuote).

- [ ] **Step 3: Implementare**

`lib/services/busta_paga_regex_parser.dart`: in `BustaPagaRegexParser` rinominare
`static const _chiaveArrotondamento =` in `static const chiaveArrotondamento =`
(stessa stringa) e aggiornare i 3 usi interni (righe ~739, ~743 e la
dichiarazione). Aggiungere il doc-comment "Chiave delle trattenute per la
differenza di arrotondamento; condivisa con i layout" (italiano). Poi
`grep -rn "_chiaveArrotondamento" lib test` deve restituire 0 risultati.

`prestampato_classifier.dart`: l'import di `../busta_paga_regex_parser.dart` c'è già
dal Task 5 (dà accesso a `BustaPagaRegexParser`, `RateoCategoria`, `BustaPagaEstratti`):
non aggiungere un secondo import. Aggiungere le costanti/funzioni:

```dart
const _xCodiceDestro = 95.0; // colonna Codice: bordo destro ~84-93
const _xCodiceSinistroMin = 80.0;
const _xQuantitaDestro = 324.4;
const _xDescrizioneMin = 100.0;
const _xDescrizioneMaxCompetenza = 296.0;
// Le trattenute hanno annotazioni "Anno AAAA Cod.ENTE" da X ~243: la
// descrizione di una trattenuta si legge solo a sinistra di questo limite.
const _xDescrizioneMaxTrattenuta = 240.0;

final _codice = RegExp(r'^\d{1,3}$');

typedef _Riga = List<ParolaVoce>;

/// Raggruppa le parole per riga (Y entro 1,0 pt dalla prima della riga).
List<_Riga> _righe(List<ParolaVoce> parole) {
  final ordinate = [...parole]
    ..sort((a, b) => a.bordoSuperiore.compareTo(b.bordoSuperiore));
  final righe = <_Riga>[];
  for (final p in ordinate) {
    if (righe.isNotEmpty &&
        (p.bordoSuperiore - righe.last.first.bordoSuperiore).abs() <= 1.0) {
      righe.last.add(p);
    } else {
      righe.add([p]);
    }
  }
  for (final r in righe) {
    r.sort((a, b) => a.bordoSinistro.compareTo(b.bordoSinistro));
  }
  return righe;
}

String _descrizione(_Riga riga, double xMax) => [
      for (final p in riga)
        if (p.bordoSinistro >= _xDescrizioneMin && p.bordoDestro <= xMax) p.testo,
    ].join(' ').trim();

double? _importoInColonna(_Riga riga, double bordoDestro) {
  for (final p in riga) {
    if ((p.bordoDestro - bordoDestro).abs() > _tolleranzaX) continue;
    final v = _num(p.testo);
    if (v != null) return v;
  }
  return null;
}

/// Voci di competenza (con codice e importo in colonna competenze) e
/// trattenute (senza codice, importo in colonna ritenute) di UNA pagina, nella
/// zona fra la testata e la riga di etichette "Arrot. precedente".
({List<VoceCompetenza> voci, Map<String, double> trattenute}) _vociDiPagina(
  List<ParolaVoce> parole,
) {
  final voci = <VoceCompetenza>[];
  final trattenute = <String, double>{};
  final testata = _etichetta(parole, ['COD.']);
  final fine = _etichetta(parole, ['Arrot.', 'precedente']);
  if (testata == null || fine == null) return (voci: voci, trattenute: trattenute);

  final zona = [
    for (final p in parole)
      if (p.bordoSuperiore >= testata.top + 10 && p.bordoSuperiore < fine.top - 1)
        p,
  ];
  for (final riga in _righe(zona)) {
    final haCodice = riga.any((p) =>
        p.bordoSinistro >= _xCodiceSinistroMin &&
        p.bordoDestro <= _xCodiceDestro &&
        _codice.hasMatch(p.testo));
    final importoComp = _importoInColonna(riga, _xCompetenzeDestro);
    final importoRit = _importoInColonna(riga, _xRitenuteDestro);
    if (haCodice && importoComp != null) {
      voci.add(VoceCompetenza(
        descrizione: _descrizione(riga, _xDescrizioneMaxCompetenza),
        quantita: _importoInColonna(riga, _xQuantitaDestro),
        importo: importoComp,
      ));
    } else if (!haCodice && importoRit != null) {
      final d = _descrizione(riga, _xDescrizioneMaxTrattenuta);
      if (d.isEmpty) continue;
      final chiave = switch (d) {
        'CTR FPLD' => 'INPS',
        'IRPEF NETTA' => 'IRPEF',
        _ => d,
      };
      trattenute[chiave] = (trattenute[chiave] ?? 0) + importoRit;
    }
  }
  return (voci: voci, trattenute: trattenute);
}
```

In `classificaPrestampato`, prima del `return`:

```dart
  final competenze = <VoceCompetenza>[];
  final trattenute = <String, double>{};
  for (final grezza in pagine) {
    if (grezza == null) continue;
    final letto = _vociDiPagina(_pulite(grezza));
    competenze.addAll(letto.voci);
    letto.trattenute.forEach(
      (k, v) => trattenute[k] = (trattenute[k] ?? 0) + v,
    );
  }

  // Totali stampati e arrotondamenti (solo pagina dei totali).
  double? totaleRitenute, totaleCompetenze, arrPrec, arrAtt;
  if (parole.isNotEmpty) {
    final tr = _etichetta(parole, ['Totale', 'ritenute']);
    if (tr != null) {
      totaleRitenute = _valore(parole,
          dalTop: tr.top + 5, alTop: tr.top + 14, bordoDestro: _xRitenuteDestro);
    }
    final tc = _etichetta(parole, ['Totale', 'Competenze']);
    if (tc != null) {
      totaleCompetenze = _valore(parole,
          dalTop: tc.top + 5, alTop: tc.top + 14, bordoDestro: _xCompetenzeDestro);
    }
    final ap = _etichetta(parole, ['Arrot.', 'precedente']);
    if (ap != null) {
      arrPrec = _valore(parole,
          dalTop: ap.top + 5, alTop: ap.top + 14, bordoDestro: _xRitenuteDestro);
    }
    final aa = _etichetta(parole, ['Arrot.', 'attuale']);
    if (aa != null) {
      arrAtt = _valore(parole,
          dalTop: aa.top + 5, alTop: aa.top + 14, bordoDestro: _xCompetenzeDestro);
    }
  }

  final lordo = computeLordo(competenze);
  final sommaNominate = trattenute.values.fold(0.0, (s, v) => s + v);
  final arrotondamento = (arrPrec ?? 0) - (arrAtt ?? 0);
  if (arrotondamento.abs() > 0.005) {
    trattenute[BustaPagaRegexParser.chiaveArrotondamento] = arrotondamento;
  }
  final nettoDerivato =
      competenze.isEmpty ? null : computeNetto(lordo, trattenute);

  var lordoVerificato = false;
  if (totaleCompetenze != null && competenze.isNotEmpty) {
    lordoVerificato = (totaleCompetenze - (lordo + (arrAtt ?? 0))).abs() <= 0.05;
    if (!lordoVerificato) {
      warnings.add(
        'lordo calcolato (€${lordo.toStringAsFixed(2)}) diverge dal '
        'totale competenze stampato sul PDF '
        '(€${totaleCompetenze.toStringAsFixed(2)}): verifica manualmente',
      );
    }
  }
  var trattenuteVerificate = false;
  if (totaleRitenute != null && trattenute.isNotEmpty) {
    trattenuteVerificate =
        (totaleRitenute - (sommaNominate + (arrPrec ?? 0))).abs() <= 0.05;
    if (!trattenuteVerificate) {
      warnings.add(
        'somma trattenute (€${sommaNominate.toStringAsFixed(2)}) diverge dal '
        'totale ritenute stampato sul PDF '
        '(€${totaleRitenute.toStringAsFixed(2)}): verifica manualmente',
      );
    }
  }
  var nettoVerificato = false;
  if (nettoDerivato != null && nettoStampato != null) {
    final coerente = (nettoDerivato - nettoStampato).abs() <= 0.05;
    if (!coerente) {
      warnings.add(
        'netto calcolato (€${nettoDerivato.toStringAsFixed(2)}) diverge dal '
        'netto in busta stampato sul PDF '
        '(€${nettoStampato.toStringAsFixed(2)}): verifica manualmente',
      );
    }
    nettoVerificato = lordoVerificato && trattenuteVerificate && coerente;
  }
```

e nel `BustaPagaEstratti(`: `lordo: competenze.isNotEmpty ? lordo : null,`,
`netto: nettoDerivato ?? nettoStampato,`, `trattenute: trattenute,`,
`straordinari: computeStraordinari(competenze),`, `competenze: competenze,`,
`lordoVerificato: lordoVerificato, trattenuteVerificate: trattenuteVerificate,
nettoVerificato: nettoVerificato,` (rimuovere i vecchi `netto:`/`trattenute:`/
`straordinari:` del Task 5).

Nota del test "totale divergente": il totale competenze diverge di 11,98 → il
warning contiene "lordo calcolato"; anche `nettoVerificato` diventa falso perché
`lordoVerificato` lo è.

- [ ] **Step 4: Verifica completa**

Run: `flutter test test/payslip_layouts/ test/busta_paga_regex_parser_test.dart && flutter analyze`
Expected: PASS (il rename della chiave non cambia il comportamento JOB).

- [ ] **Step 5: Commit**

```bash
git add lib/services test/payslip_layouts
git commit -m "feat: classificatore prestampato — voci, trattenute, arrotondamenti e verifiche"
```

---

### Task 8: PrestampatoLayout, registro, non-ambiguità e accettazione sul PDF reale

**Files:**
- Create: `lib/services/payslip_layouts/prestampato_layout.dart`
- Modify: `lib/services/payslip_layouts/payslip_layout_registry.dart`
- Test: `test/payslip_layouts/prestampato_layout_test.dart`, `test/payslip_layouts/payslip_layout_registry_test.dart`
- Create: `test/prestampato_acceptance_test.dart`

**Interfaces:**
- Consumes: `classificaPrestampato` (Task 5-7), `PayslipLayout`, `PayslipLayoutRegistry.estrai` (esistente: rileva + estrai + `conLayoutId`), `JobLayout`, `PdfImportService.leggiContenuto`.
- Produces: `class PrestampatoLayout implements PayslipLayout` con `id == 'prestampato'`; `PayslipLayoutRegistry.standard` = `[JobLayout(), PrestampatoLayout()]`.

- [ ] **Step 1: Test che falliscono**

`test/payslip_layouts/prestampato_layout_test.dart`:

```dart
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
    expect(layout.riconosce(PdfContenuto(testo: _testoPrestampato)), isTrue);
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
    expect(const JobLayout().riconosce(PdfContenuto(testo: _testoPrestampato)),
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
```

`test/prestampato_acceptance_test.dart` (nessun dato reale nel repo: il PDF si
passa a runtime con `--dart-define=PAYSLIP_PDF="<percorso locale>"`; senza, il test
è saltato; asserisce solo **identità**, mai valori):

```dart
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
```

- [ ] **Step 2: Verificare che falliscano**

Run: `flutter test test/payslip_layouts/prestampato_layout_test.dart`
Expected: FAIL (`prestampato_layout.dart` non esiste).

- [ ] **Step 3: Implementare**

`lib/services/payslip_layouts/prestampato_layout.dart`:

```dart
import '../busta_paga_regex_parser.dart';
import 'payslip_layout.dart';
import 'pdf_contenuto.dart';
import 'prestampato_classifier.dart';

/// Secondo layout di cedolino PDF: modulo prestampato con etichette e valori in
/// colonne separate (l'estrazione testuale non le associa: si legge per
/// COORDINATE). Il nome del software paghe non è deducibile dal PDF; `id` è
/// provvisorio ma persistito in `BustaPaga.layout`.
class PrestampatoLayout implements PayslipLayout {
  const PrestampatoLayout();

  static final _elementi = RegExp(r'ELEMENTI\s+DELLA\s+RETRIBUZIONE');
  static final _periodo = RegExp(r'Periodo\s+di\s+retribuzione');

  @override
  String get id => 'prestampato';

  @override
  bool riconosce(PdfContenuto contenuto) {
    final testo = contenuto.testo ?? '';
    return _elementi.hasMatch(testo) && _periodo.hasMatch(testo);
  }

  @override
  BustaPagaEstratti estrai(PdfContenuto contenuto) =>
      classificaPrestampato(contenuto.paroleAPagina);
}
```

`lib/services/payslip_layouts/payslip_layout_registry.dart`: aggiungere
`import 'prestampato_layout.dart';` e cambiare
`static const standard = PayslipLayoutRegistry([JobLayout()]);` in
`static const standard = PayslipLayoutRegistry([JobLayout(), PrestampatoLayout()]);`.
JOB resta primo: la sua firma è esplicita e le due firme non si sovrappongono.

- [ ] **Step 4: Verifica completa, poi accettazione sul PDF reale**

Run: `flutter test --reporter failures-only && flutter analyze`
Expected: intera suite verde, analyze pulito.

Poi, sul PDF reale (percorso fornito dall'utente in locale, NON scriverlo in nessun
file tracciato né nel report):
`flutter test test/prestampato_acceptance_test.dart --dart-define=PAYSLIP_PDF="<percorso locale del PDF di esempio>"`
Expected: PASS. Se fallisce, il messaggio `reason` riporta i warning: correggi le
ancore del **codice** confrontandole col documento di findings; se il PDF reale
contraddice il documento, riporta la discrepanza nel report (non riscrivere i
findings di tua iniziativa). Le descrizioni "IMPOSTA AUMENTI CCNL 5%" e le righe
con annotazione "Anno AAAA Cod.ENTE" sono i punti più a rischio (limite X della
descrizione delle trattenute): il test di accettazione li verifica tramite
`trattenuteVerificate`.

- [ ] **Step 5: Commit**

```bash
git add lib/services/payslip_layouts test
git commit -m "feat: PrestampatoLayout registrato nel registro, con accettazione su PDF reale"
```

---

### Task 9: Documentazione di progetto

**Files:**
- Modify: `CLAUDE.md` (sezione import PDF)
- Modify: `BACKLOG.md`

- [ ] **Step 1: Aggiornare CLAUDE.md**

Nella sezione che descrive `PdfImportService.pickAndImport()` e il parser regex
(`buste_paga_section_screen.dart`, "Solo import PDF…"): descrivere il nuovo flusso
in poche righe, in italiano, nello stile del file: l'import legge il PDF in un
`PdfContenuto`; `PayslipLayoutRegistry.standard` (in
`lib/services/payslip_layouts/`) sceglie il layout con la firma testuale
(`JobLayout` = "JOB - Copyright"; `PrestampatoLayout` = etichette "ELEMENTI DELLA
RETRIBUZIONE" + "Periodo di retribuzione"), stampa `layoutId` sul risultato e la
busta salva `layout` (colonna Drift, `schemaVersion` 7, default `'job'`); nessun
layout riconosce il PDF → alert "Formato non riconosciuto" come prima. Aggiungere
la regola: **per un nuovo layout = una classe `PayslipLayout` + una riga in
`PayslipLayoutRegistry.standard` + test con fixture sintetiche (mai PDF reali nel
repo)**. Nota di merge: `CLAUDE.md` su `main` è cambiato (caricamento all'avvio,
animazione di avvio); ripartire dalla versione di `main` al merge, non
sovrascriverla.

- [ ] **Step 2: Aggiornare BACKLOG.md**

Aggiungere voci aperte: (1) secondo PDF del layout `prestampato` (con Ex festività,
Ferie godute, 13ª/14ª) per confermare le ancore; (2) nome definitivo del layout
(oggi id provvisorio `prestampato`); (3) significato del "ROL goduti" del rateo
(106,00-tipo vs ore della voce mensile); (4) 13ª/14ª e cedolino a pagina singola
per il nuovo layout; (5) minor differiti della revisione (righe >80 colonne, test
di `_paroleDiPagina` su pagina illeggibile, copertura v6→v7 diretta).

- [ ] **Step 3: Verifica e commit**

Run: `flutter analyze` (nessun codice cambia; solo controllo).

```bash
git add CLAUDE.md BACKLOG.md
git commit -m "docs: layout prestampato e regola per aggiungere nuovi layout"
```

## Punti aperti (da non risolvere in questo piano)

- **Un solo PDF**: le ancore X/Y sono tarate su un unico esempio; le fixture
  sintetiche verificano la logica, non la stabilità del modulo. Serve un secondo
  cedolino (idealmente con Ex festività, Ferie godute e 13ª/14ª).
- **Ex festività**: colonne ipotizzate uguali a Ferie (celle vuote nell'esempio).
- **Nome/id del layout** (`prestampato`): provvisorio; cambiarlo dopo il rilascio
  richiede una migrazione dei valori `layout` già salvati.
- **Chiavi delle trattenute**: `CTR FPLD` → `INPS` e `IRPEF NETTA` → `IRPEF` sono
  una scelta di normalizzazione (allineare le statistiche al layout JOB); le altre
  righe conservano la descrizione stampata. Da confermare guardando l'archivio.
- **Tipo busta** (13ª/14ª): il classificatore restituisce sempre `mensile`.

## Self-review (copertura del documento di findings)

- Firma di riconoscimento e non-ambiguità con JOB → Task 8 ✔
- Selezione pagina per valore sotto "Totale Competenze", pagina singola, ordine
  invertito → Task 5 ✔
- Periodo `MMM.AAAA` e mesi abbreviati → Task 5 ✔
- Netto (basso, ripiego riquadro alto), totali per colonna, ore lavorate → Task 5/7 ✔
- Ratei per bordo destro, celle vuote = 0, "rateo m." ignorato, mappatura → Task 6 ✔
- Voci da tutte le pagine senza deduplicare, quantità, trattenute senza codice,
  righe informative escluse, arrotondamenti come JOB → Task 7 ✔
- Verifiche aritmetiche (lordo, trattenute, netto) come flag → Task 7 ✔
- Privacy (nessun dato reale, accettazione solo su identità) → Global Constraints,
  Task 8 ✔
- Documentazione e regola "nuovo layout = classe + riga + fixture" → Task 9 ✔
- Non coperti per scelta (punti aperti): secondo PDF, Ex festività reali, 13ª/14ª,
  nome del layout.
