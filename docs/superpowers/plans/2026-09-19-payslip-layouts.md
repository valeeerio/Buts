# Layout PDF multipli per le buste paga — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Regole di progetto (CLAUDE.md, prevalgono):** lo sviluppo di codice Dart è
> sempre delegato a dev1/dev2 (il coordinatore non usa Edit/Write su file Dart);
> dopo ogni run di dev lanciare `revisore` con lo stesso scope; verifiche solo
> statiche (`flutter analyze`, `flutter test`, `build_runner`, skill
> `flutter-check`), mai avviare l'app; **ogni comando git che modifica il repo
> (commit incluso) parte solo su istruzione esplicita dell'utente** — gli step
> "Commit" qui sotto vanno eseguiti solo se l'utente li ha autorizzati.

**Goal:** Riorganizzare l'estrazione dei dati da PDF in layout pluggabili con
auto-rilevamento, persistere il layout di origine di ogni busta, e preparare
l'aggiunta del secondo layout (software paghe diverso da "JOB").

**Architecture:** Interfaccia `PayslipLayout` (`id`, `riconosce`, `estrai`) e
`PayslipLayoutRegistry` che sceglie il primo layout che riconosce il PDF. Il
layout JOB esistente NON viene riscritto né spostato: `JobLayout` è un adattatore
sottile sopra `BustaPagaRegexParser` e le funzioni a coordinate già esistenti
(rischio di regressione minimo). Il servizio di import legge il PDF una volta in
un `PdfContenuto` (testo + parole con coordinate per ogni pagina) e lo passa al
registro. Nuova colonna Drift `layout` (default `'job'`).

**Tech Stack:** Flutter/Dart, Riverpod, Drift (SQLite, `*.g.dart` non
versionati), `syncfusion_flutter_pdf`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-19-payslip-layouts-design.md`
(scostamenti decisi in fase di piano: `estrai` è **sincrona**; `JobLayout` è un
adattatore, non uno spostamento di codice).

## Global Constraints

- Design tokens/stile invariati: nessuna modifica UI in questo piano.
- App solo dark mode; nessun nuovo colore.
- Il PDF di esempio contiene dati personali: **mai copiarlo o incollarne
  contenuti anagrafici (nome, CF, azienda, indirizzo) nel repo**; fixture solo
  sintetiche.
- Migrazioni Drift **additive** (`schemaVersion` 6→7), default sulla colonna,
  nessun dato esistente toccato.
- Comportamento del layout JOB **invariato**: tutti i test esistenti passano
  senza modifiche alle asserzioni.
- Dopo modifiche a `lib/data/database.dart`: `dart run build_runner build --delete-conflicting-outputs`.
- Identificatore di layout stabile e persistito: JOB = `'job'`.

## File Structure

| File | Responsabilità |
|------|----------------|
| `lib/services/payslip_layouts/pdf_contenuto.dart` (nuovo) | `ParolaVoce` (typedef spostato qui) + `PdfContenuto` |
| `lib/services/payslip_layouts/payslip_layout.dart` (nuovo) | interfaccia `PayslipLayout` |
| `lib/services/payslip_layouts/payslip_layout_registry.dart` (nuovo) | `PayslipLayoutRegistry` |
| `lib/services/payslip_layouts/job_layout.dart` (nuovo) | `JobLayout`, adattatore sul parser JOB |
| `lib/services/pdf_import_service.dart` (modifica) | `leggiContenuto`, `PdfImportResult.contenuto`, re-export `ParolaVoce` |
| `lib/screens/buste_paga/buste_paga_section_screen.dart` (modifica) | usa il registro al posto di `BustaPagaRegexParser` |
| `lib/models/busta_paga.dart` (modifica) | `BustaPaga.layout`, `kLayoutPredefinito` |
| `lib/services/busta_paga_regex_parser.dart` (modifica) | `BustaPagaEstratti.layoutId` |
| `lib/data/database.dart` (modifica) | colonna `layout`, migrazione v7, mapping |
| `lib/screens/buste_paga/busta_paga_form_screen.dart` (modifica) | passa `layout` a `BustaPaga` |
| `test/payslip_layouts/*` (nuovi) | test registro, JobLayout, leggiContenuto |

---

### Task 1: PdfContenuto, interfaccia, registro, JobLayout

**Files:**
- Create: `lib/services/payslip_layouts/pdf_contenuto.dart`
- Create: `lib/services/payslip_layouts/payslip_layout.dart`
- Create: `lib/services/payslip_layouts/payslip_layout_registry.dart`
- Create: `lib/services/payslip_layouts/job_layout.dart`
- Modify: `lib/models/busta_paga.dart` (aggiungere `kLayoutPredefinito`)
- Modify: `lib/services/busta_paga_regex_parser.dart` (aggiungere `layoutId` a `BustaPagaEstratti`)
- Modify: `lib/services/pdf_import_service.dart:473-478` (il typedef `ParolaVoce` si sposta)
- Test: `test/payslip_layouts/payslip_layout_registry_test.dart`, `test/payslip_layouts/job_layout_test.dart`

**Interfaces:**
- Produces:
  - `const kLayoutPredefinito = 'job';` in `lib/models/busta_paga.dart`
  - `typedef ParolaVoce = ({String testo, double bordoSuperiore, double bordoSinistro, double bordoDestro});`
  - `class PdfContenuto { final String? testo; final List<List<ParolaVoce>?> paroleAPagina; const PdfContenuto({this.testo, this.paroleAPagina = const []}); List<ParolaVoce>? get primaPagina; }`
  - `abstract interface class PayslipLayout { String get id; bool riconosce(PdfContenuto contenuto); BustaPagaEstratti estrai(PdfContenuto contenuto); }`
  - `class PayslipLayoutRegistry { const PayslipLayoutRegistry(List<PayslipLayout> layouts); static const standard; PayslipLayout? rileva(PdfContenuto contenuto); }`
  - `class JobLayout implements PayslipLayout { const JobLayout(); }` con `id == 'job'`
  - `BustaPagaEstratti.layoutId` (`String`, default `kLayoutPredefinito`)

- [ ] **Step 1: Scrivere i test (falliscono: file non esistono)**

`test/payslip_layouts/payslip_layout_registry_test.dart`:

```dart
import 'package:buts/services/busta_paga_regex_parser.dart';
import 'package:buts/services/payslip_layouts/payslip_layout.dart';
import 'package:buts/services/payslip_layouts/payslip_layout_registry.dart';
import 'package:buts/services/payslip_layouts/pdf_contenuto.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLayout implements PayslipLayout {
  _FakeLayout(this.id, this.firma);

  @override
  final String id;
  final String firma;

  @override
  bool riconosce(PdfContenuto contenuto) =>
      (contenuto.testo ?? '').contains(firma);

  @override
  BustaPagaEstratti estrai(PdfContenuto contenuto) => BustaPagaEstratti(
        trattenute: const {},
        straordinari: 0,
        ferieMaturate: 0,
        ferieGodute: 0,
        ferieResidue: 0,
        rolMaturati: 0,
        rolGoduti: 0,
        rolResidui: 0,
        permessiGoduti: 0,
        warnings: const [],
        layoutId: id,
      );
}

void main() {
  group('PayslipLayoutRegistry.rileva', () {
    test('restituisce il layout che riconosce il PDF', () {
      final registro = PayslipLayoutRegistry([
        _FakeLayout('a', 'FIRMA-A'),
        _FakeLayout('b', 'FIRMA-B'),
      ]);
      final trovato = registro.rileva(const PdfContenuto(testo: 'x FIRMA-B y'));
      expect(trovato?.id, 'b');
    });

    test('con più layout compatibili vince il primo in ordine', () {
      final registro = PayslipLayoutRegistry([
        _FakeLayout('a', 'COMUNE'),
        _FakeLayout('b', 'COMUNE'),
      ]);
      expect(registro.rileva(const PdfContenuto(testo: 'COMUNE'))?.id, 'a');
    });

    test('nessun layout compatibile -> null', () {
      final registro = PayslipLayoutRegistry([_FakeLayout('a', 'FIRMA-A')]);
      expect(registro.rileva(const PdfContenuto(testo: 'altro')), isNull);
    });

    test('testo assente -> null', () {
      final registro = PayslipLayoutRegistry([_FakeLayout('a', 'FIRMA-A')]);
      expect(registro.rileva(const PdfContenuto()), isNull);
    });
  });
}
```

`test/payslip_layouts/job_layout_test.dart` (testo JOB sintetico inline, ridotto
ma con periodo, una voce, INPS e totali, sufficiente per il confronto con
`parse`):

```dart
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
```

- [ ] **Step 2: Eseguire i test e verificare che falliscano**

Run: `flutter test test/payslip_layouts/`
Expected: FAIL (import non risolti / `layoutId` non definito).

- [ ] **Step 3: Implementare**

`lib/models/busta_paga.dart` — in cima al file, dopo gli enum:

```dart
/// Identificatore del layout PDF di default (software paghe "JOB"); usato
/// anche come default della colonna Drift `layout` per le buste già salvate.
const kLayoutPredefinito = 'job';
```

`lib/services/busta_paga_regex_parser.dart` — in `BustaPagaEstratti` aggiungere il
campo e il parametro del costruttore:

```dart
  /// Identificatore del layout PDF che ha prodotto questi dati (vedi
  /// `PayslipLayout.id`); persistito in `BustaPaga.layout`.
  final String layoutId;
  ...
    this.nettoVerificato = false,
    this.layoutId = kLayoutPredefinito,
  });
```

`lib/services/payslip_layouts/pdf_contenuto.dart`:

```dart
/// Parola di una pagina con le sue coordinate (origine in alto a sinistra).
typedef ParolaVoce = ({
  String testo,
  double bordoSuperiore,
  double bordoSinistro,
  double bordoDestro,
});

/// Tutto ciò che un layout vede di un PDF: testo linearizzato e parole con
/// coordinate per ogni pagina. Una pagina illeggibile è `null` (mai
/// un'eccezione): l'estrazione per coordinate è best-effort.
class PdfContenuto {
  final String? testo;
  final List<List<ParolaVoce>?> paroleAPagina;

  const PdfContenuto({this.testo, this.paroleAPagina = const []});

  List<ParolaVoce>? get primaPagina =>
      paroleAPagina.isEmpty ? null : paroleAPagina.first;
}
```

In `lib/services/pdf_import_service.dart` rimuovere il typedef `ParolaVoce`
(righe 473-478) e aggiungere tra gli import:

```dart
import 'payslip_layouts/pdf_contenuto.dart';
export 'payslip_layouts/pdf_contenuto.dart' show ParolaVoce;
```

(il re-export mantiene compilabili i test esistenti che importano solo
`pdf_import_service.dart`).

`lib/services/payslip_layouts/payslip_layout.dart`:

```dart
import '../busta_paga_regex_parser.dart';
import 'pdf_contenuto.dart';

/// Un layout di cedolino PDF (software paghe): sa riconoscere il proprio PDF
/// e trasformarlo in [BustaPagaEstratti]. Aggiungere un layout = nuova classe
/// + una riga in `PayslipLayoutRegistry.standard`.
abstract interface class PayslipLayout {
  /// Identificatore stabile, persistito in `BustaPaga.layout`.
  String get id;

  bool riconosce(PdfContenuto contenuto);

  BustaPagaEstratti estrai(PdfContenuto contenuto);
}
```

`lib/services/payslip_layouts/payslip_layout_registry.dart`:

```dart
import 'job_layout.dart';
import 'payslip_layout.dart';
import 'pdf_contenuto.dart';

class PayslipLayoutRegistry {
  final List<PayslipLayout> layouts;

  const PayslipLayoutRegistry(this.layouts);

  /// Layout supportati, in ordine di prova. I nuovi layout si aggiungono qui.
  static const standard = PayslipLayoutRegistry([JobLayout()]);

  /// Primo layout che riconosce il PDF, o `null` se nessuno lo riconosce.
  PayslipLayout? rileva(PdfContenuto contenuto) {
    for (final layout in layouts) {
      if (layout.riconosce(contenuto)) return layout;
    }
    return null;
  }
}
```

`lib/services/payslip_layouts/job_layout.dart`:

```dart
import '../../models/busta_paga.dart';
import '../busta_paga_regex_parser.dart';
import '../pdf_import_service.dart';
import 'payslip_layout.dart';
import 'pdf_contenuto.dart';

/// Layout del software paghe "JOB". Adattatore sottile: la logica vive ancora
/// in [BustaPagaRegexParser] e nelle funzioni `classifica*DaCoordinate`.
class JobLayout implements PayslipLayout {
  const JobLayout();

  static final _firma = RegExp(r'JOB\s*-\s*Copyright', caseSensitive: false);

  @override
  String get id => kLayoutPredefinito;

  @override
  bool riconosce(PdfContenuto contenuto) =>
      _firma.hasMatch(contenuto.testo ?? '');

  @override
  BustaPagaEstratti estrai(PdfContenuto contenuto) {
    final parole = contenuto.primaPagina;
    final ratei = parole == null
        ? null
        : classificaRateiDaCoordinate([
            for (final p in parole)
              (
                testo: p.testo,
                bordoSuperiore: p.bordoSuperiore,
                bordoDestro: p.bordoDestro,
              ),
          ]);
    final voci = parole == null ? null : classificaVociDaCoordinate(parole);
    return const BustaPagaRegexParser().parse(contenuto.testo ?? '', ratei, voci);
  }
}
```

- [ ] **Step 4: Eseguire test e analyzer**

Run: `flutter test test/payslip_layouts/ test/busta_paga_regex_parser_test.dart test/pdf_voci_coordinate_test.dart test/pdf_ratei_coordinate_test.dart && flutter analyze`
Expected: PASS, nessun errore di analyze.

- [ ] **Step 5: Commit (solo su autorizzazione dell'utente)**

```bash
git add lib/services/payslip_layouts lib/models/busta_paga.dart lib/services/busta_paga_regex_parser.dart lib/services/pdf_import_service.dart test/payslip_layouts
git commit -m "refactor: interfaccia PayslipLayout, registro e JobLayout"
```

---

### Task 2: Colonna `layout`, migrazione v7, modello

**Files:**
- Modify: `lib/models/busta_paga.dart` (campo `layout`, `copyWith`)
- Modify: `lib/data/database.dart` (colonna, `schemaVersion => 7`, migrazione, mapping `toDomain`/`toCompanion`)
- Modify: `lib/screens/buste_paga/busta_paga_form_screen.dart:595` (passare `layout`)
- Test: `test/database_migration_test.dart`, `test/busta_paga_model_test.dart`

**Interfaces:**
- Consumes: `kLayoutPredefinito`, `BustaPagaEstratti.layoutId` (Task 1)
- Produces: `BustaPaga.layout` (`String`, default `kLayoutPredefinito`, in `copyWith`); colonna `layout` in `BustePagaTable`

- [ ] **Step 1: Test che falliscono**

In `test/database_migration_test.dart`, nel test di migrazione v3→(attuale) dopo
`expect(riga.exFestivitaResidue, ...)` (circa riga 135) aggiungere:

```dart
      expect(riga.layout, 'job'); // default della colonna aggiunta in v7
```

e aggiornare i commenti/titoli "v3 -> v6" e "da 3 a 6" in "v3 -> v7" / "da 3 a 7".
Nel test che inserisce una riga con tutte le colonne (circa riga 140-170)
passare `layout: 'altro'` al `BustaPaga` inserito e verificare dopo la rilettura
`expect(riletta.layout, 'altro');`.

In `test/busta_paga_model_test.dart` aggiungere:

```dart
  test('layout: default job e copyWith', () {
    final b = BustaPaga(
      id: 'x',
      periodo: DateTime(2026, 7),
      lordo: 0,
      netto: 0,
      trattenute: const {},
      straordinari: 0,
      ferieMaturate: 0,
      ferieGodute: 0,
      ferieResidue: 0,
      rolMaturati: 0,
      rolGoduti: 0,
      rolResidui: 0,
      permessiGoduti: 0,
      oreLavorate: 0,
    );
    expect(b.layout, 'job');
    expect(b.copyWith(layout: 'altro').layout, 'altro');
  });
```

- [ ] **Step 2: Verificare che falliscano**

Run: `flutter test test/database_migration_test.dart test/busta_paga_model_test.dart`
Expected: FAIL (`layout` non definito).

- [ ] **Step 3: Implementare**

`lib/models/busta_paga.dart`: in `BustaPaga` aggiungere
`final String layout;` (con doc: "Layout PDF di origine, vedi
`PayslipLayout.id`; `job` per le buste salvate prima dell'introduzione del
campo"), `this.layout = kLayoutPredefinito,` nel costruttore, `String? layout,` in
`copyWith` e `layout: layout ?? this.layout,` nel ritorno.

`lib/data/database.dart`:

```dart
  /// Layout PDF da cui la busta è stata importata (vedi `PayslipLayout.id`).
  /// Default `job` per compatibilità con le righe create prima di v7.
  TextColumn get layout =>
      text().withDefault(const Constant(kLayoutPredefinito))();
```

`int get schemaVersion => 7;` e in `onUpgrade`, dopo il blocco `from < 6`:

```dart
          // v6 -> v7: nuova colonna `layout` (layout PDF di origine, vedi
          // PayslipLayout) — migrazione additiva, le righe esistenti
          // ricevono il default 'job', nessun dato esistente toccato.
          if (from < 7) {
            await m.addColumn(bustePagaTable, bustePagaTable.layout);
          }
```

In `toDomain()` aggiungere `layout: layout,` e in `toCompanion()`
`layout: Value(layout),`.

`lib/screens/buste_paga/busta_paga_form_screen.dart` — nel `BustaPaga(` di
`_save` (dopo `tipo: _tipo,`) aggiungere `layout: widget.estratti.layoutId,`.

- [ ] **Step 4: Rigenerare Drift e verificare**

Run: `dart run build_runner build --delete-conflicting-outputs && flutter test && flutter analyze`
Expected: tutti i test PASS, analyze pulito.

- [ ] **Step 5: Commit (solo su autorizzazione dell'utente)**

```bash
git add lib/models lib/data lib/screens/buste_paga/busta_paga_form_screen.dart test
git commit -m "feat: persiste il layout PDF di origine (migrazione v7)"
```

---

### Task 3: Import basato sul registro

**Files:**
- Modify: `lib/services/pdf_import_service.dart` (`leggiContenuto`, `PdfImportResult.contenuto`, `pickAndImport`)
- Modify: `lib/screens/buste_paga/buste_paga_section_screen.dart:70-71,396-399`
- Test: `test/payslip_layouts/leggi_contenuto_test.dart`

**Interfaces:**
- Consumes: `PdfContenuto`, `PayslipLayoutRegistry.standard` (Task 1)
- Produces: `PdfContenuto PdfImportService.leggiContenuto(List<int> bytes)`; `PdfImportResult.contenuto` (`PdfContenuto?`) e getter `extractedText` (`String?`, = `contenuto?.testo`). `estraiDaBytes` resta invariato (usato dal test di accettazione).

- [ ] **Step 1: Test che fallisce**

`test/payslip_layouts/leggi_contenuto_test.dart`:

```dart
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
```

- [ ] **Step 2: Verificare che fallisca**

Run: `flutter test test/payslip_layouts/leggi_contenuto_test.dart`
Expected: FAIL (`leggiContenuto` non definito).

- [ ] **Step 3: Implementare**

`lib/services/pdf_import_service.dart`:

1. In `PdfImportResult` sostituire i campi `extractedText`, `ratei`, `voci` con
   `final PdfContenuto? contenuto;` e aggiungere
   `String? get extractedText => contenuto?.testo;`. `PdfImportResult.success`
   prende `PdfContenuto? contenuto` al posto dei tre parametri opzionali
   (aggiornare doc: i ratei/voci ora li calcola il layout, non l'import).
2. Aggiungere il metodo pubblico:

```dart
  /// Legge il PDF una sola volta: testo linearizzato + parole con coordinate
  /// di OGNI pagina (pagina illeggibile = `null`, mai un'eccezione). I layout
  /// decidono quali pagine usare.
  PdfContenuto leggiContenuto(List<int> bytes) {
    final document = PdfDocument(inputBytes: bytes);
    try {
      return PdfContenuto(
        testo: PdfTextExtractor(document).extractText(),
        paroleAPagina: [
          for (var i = 0; i < document.pages.count; i++)
            _paroleDiPagina(document, i),
        ],
      );
    } finally {
      document.dispose();
    }
  }
```

3. Generalizzare `_paroleprimaPagina` in `_paroleDiPagina(PdfDocument document, int indice)`
   (stessa logica, `startPageIndex`/`endPageIndex` = `indice`,
   `if (indice >= document.pages.count) return null;`) e far chiamare
   `_paroleDiPagina(document, 0)` da `estraiDaBytes`.
4. In `pickAndImport`: `final contenuto = leggiContenuto(bytes); final text = contenuto.testo;`
   (stessa soglia `<= 20` → `noExtractableText`), e
   `PdfImportResult.success(targetPath, contenuto: contenuto)`.

`lib/screens/buste_paga/buste_paga_section_screen.dart`: sostituire il campo
`_regexParser` (riga 71) con

```dart
  final _layoutRegistry = PayslipLayoutRegistry.standard;
```

(import `../../services/payslip_layouts/payslip_layout_registry.dart`, rimuovere
l'import di `BustaPagaRegexParser` se non più usato) e le righe 396-399 con:

```dart
      final contenuto = result.contenuto;
      final layout = contenuto == null ? null : _layoutRegistry.rileva(contenuto);
      final risultato = layout?.estrai(contenuto!);
```

Il resto (controllo `risultato == null || (netto == null && periodo == null)`,
alert "Formato non riconosciuto", cleanup del file) resta identico.

- [ ] **Step 4: Verifica completa**

Run: `flutter test && flutter analyze`
Expected: tutti PASS (incluso `pdf_voci_coordinate_acceptance_test.dart`, che
esegue i PDF JOB reali sulla macchina dello sviluppatore o fa skip altrove).

- [ ] **Step 5: Commit (solo su autorizzazione dell'utente)**

```bash
git add lib/services lib/screens/buste_paga/buste_paga_section_screen.dart test/payslip_layouts
git commit -m "refactor: l'import sceglie il layout tramite PayslipLayoutRegistry"
```

Fine del refactor: a questo punto l'app si comporta come prima (solo JOB), con
l'architettura pronta. Segnalare all'utente "pronto per il test visivo".

---

### Task 4: Scoperta delle coordinate del nuovo layout (nessun codice di produzione)

Serve a fissare le ancore reali prima di scrivere il parser (il testo PDFKit di
macOS è frammentato e non rappresenta ciò che vede Syncfusion, che è il motore
dell'app). Produce solo un documento di findings.

**Files:**
- Create (temporaneo, NON committare): `test/tmp_dump_layout_test.dart`
- Create: `docs/superpowers/specs/2026-09-19-payslip-layout-nuovo-coordinate.md`

- [ ] **Step 1: Scrivere il dump temporaneo**

```dart
import 'dart:io';

import 'package:buts/services/pdf_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _percorso = String.fromEnvironment('PAYSLIP_PDF');

void main() {
  test(
    'dump layout',
    () {
      final bytes = File(_percorso).readAsBytesSync();
      final c = const PdfImportService().leggiContenuto(bytes);
      // ignore: avoid_print
      print('--- TESTO LINEARIZZATO ---\n${c.testo}');
      for (var i = 0; i < c.paroleAPagina.length; i++) {
        // ignore: avoid_print
        print('--- PAGINA $i ---');
        for (final p in c.paroleAPagina[i] ?? const []) {
          // ignore: avoid_print
          print('${p.bordoSinistro.toStringAsFixed(1)} '
              '${p.bordoDestro.toStringAsFixed(1)} '
              '${p.bordoSuperiore.toStringAsFixed(1)} ${p.testo}');
        }
      }
    },
    skip: _percorso.isEmpty ? 'PAYSLIP_PDF non impostato' : false,
  );
}
```

- [ ] **Step 2: Eseguirlo sul PDF di esempio**

Run: `flutter test test/tmp_dump_layout_test.dart --dart-define=PAYSLIP_PDF="<percorso locale del PDF di esempio>"`
Expected: stampa testo linearizzato e parole (sinistra, destra, alto, testo) per ogni pagina.
L'output resta in locale: contiene dati anagrafici, non va incollato nel repo.

- [ ] **Step 3: Scrivere il documento di findings (senza dati personali)**

`docs/superpowers/specs/2026-09-19-payslip-layout-nuovo-coordinate.md` deve
contenere, con etichette e intervalli X/Y ma **mai** nome, CF, azienda, indirizzo:

1. **Firma di riconoscimento**: stringhe presenti nel testo linearizzato di
   Syncfusion (es. "ELEMENTI DELLA RETRIBUZIONE", "Periodo di retribuzione"),
   verificate assenti nel testo JOB (`_testoSintetico`).
2. **Selezione pagina**: quale pagina contiene "Totale Competenze" e i ratei, e
   come riconoscerla per contenuto.
3. **Ancora per ogni campo**: periodo (come compare il token `LUG.2026` nelle
   parole), netto, totale competenze, totale ritenute, ore lavorate, righe
   Ferie/ROL (a.p., spett., godute, residuo), voci di competenza, trattenute
   (IRPEF, addizionali, contributi) — per ciascuno: etichetta, colonna (X
   min/max) e riga (Y) relative all'etichetta.
4. **Punti ambigui** ancora aperti.

- [ ] **Step 4: Rimuovere il dump temporaneo**

Run: `rm test/tmp_dump_layout_test.dart && flutter analyze`
Expected: analyze pulito, working tree con solo il documento di findings nuovo.

- [ ] **Step 5: Commit (solo su autorizzazione dell'utente)**

```bash
git add docs/superpowers/specs/2026-09-19-payslip-layout-nuovo-coordinate.md
git commit -m "docs: findings coordinate del nuovo layout PDF"
```

---

## Prossimo passo (fuori da questo piano)

**Task 5 — implementare `<Nuovo>Layout`** (classificazione per coordinate,
riconoscimento, mappatura ferie/ROL come da spec, fixture sintetiche, riga in
`PayslipLayoutRegistry.standard`, test di non-ambiguità JOB/nuovo) va pianificato
**dopo il Task 4**, con le ancore reali del documento di findings: scriverlo ora
significherebbe inventare coordinate. Lo stesso passaggio aggiorna `CLAUDE.md`
(sezione import PDF) e `BACKLOG.md`. Servirebbe anche un secondo PDF del nuovo
layout (o una 13ª) per non tarare il riconoscimento su un solo esempio.

## Self-review (spec coverage)

- Interfaccia + registro + JobLayout → Task 1 ✔
- Riconoscimento con firma JOB e non-ambiguità → Task 1 (`job_layout_test`); non-ambiguità col nuovo layout → Task 5 (dipende da Task 4) ✔
- Colonna `layout` + migrazione v7 → Task 2 ✔
- Import via registro, alert bloccante invariato → Task 3 ✔
- Estrazione nuovo layout + mappatura ratei + fixture sintetiche → Task 5 (rinviato con motivo esplicito) ⚠ gap dichiarato
- Privacy PDF → Global Constraints + Task 4 ✔
- Aggiornare CLAUDE.md/BACKLOG.md → Task 5 ✔
