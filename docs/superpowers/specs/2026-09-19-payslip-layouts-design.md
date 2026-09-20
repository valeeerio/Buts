# Layout PDF multipli per le buste paga (v1.0.1) — design

Data: 2026-09-19 · Branch: `worktree-release-1.0.1`

## Obiettivo

Supportare in import un secondo layout di cedolino PDF (software paghe diverso
da "JOB") e riorganizzare l'estrazione in modo che aggiungere layout futuri
sia un'operazione locale: un file nuovo più una riga in un registro.

Fuori scope: nuove categorie di documento (TFR, CUD…), OCR di scansioni,
modifiche a form/dettaglio/statistiche (il contratto di uscita non cambia).

## Stato attuale

- `BustaPagaRegexParser` (`lib/services/busta_paga_regex_parser.dart`, ~1400
  righe) contiene regex tarate sul solo layout JOB.
- `pdf_import_service.dart` contiene le funzioni a coordinate specifiche JOB
  (`classificaRateiDaCoordinate`, `classificaVociDaCoordinate`) e orchestra
  estrazione testo + coordinate + parser.
- Il contratto di uscita `BustaPagaEstratti` è già indipendente dal layout, così
  come modello, form, dettaglio e statistiche. Il refactor tocca solo
  estrazione/import più una colonna DB.
- `TipoBustaPaga` (mensile/13a/14a) resta ortogonale al layout.

## Il nuovo layout (da PDF di esempio, mese di esempio)

- Nessuna marca "JOB"; intestazioni "ELEMENTI DELLA RETRIBUZIONE", "Periodo di
  retribuzione".
- Periodo in formato abbreviato `MMM.AAAA` (il parser JOB cerca i mesi per
  esteso).
- Il testo linearizzato separa etichette e valori in colonne: l'estrazione
  testuale non basta, serve l'estrazione per **coordinate** delle parole.
- Dati presenti: netto, totale competenze (lordo), totale ritenute, ore
  lavorate, trattenute (IRPEF, addizionali, contributi), ratei Ferie/ROL come
  saldi "a.p." (anno precedente) + "spett." (cumulato dell'anno corrente:
  rateo mensile x mesi trascorsi) + residuo stampato (struttura verificata;
  esempio fittizio: Ferie a.p. 10,00 + spett. 45,00 = residuo 55,00; ROL a.p.
  20,00 + spett. 30,00 − goduti 40,00 = 10,00).
- Documento di 2 pagine: i dati si leggono dalla pagina 2 (la pagina 1 ha una
  griglia presenze parziale con "SEGUE .."). **Da confermare in
  implementazione** sul PDF reale; il layout deve scegliere la pagina in modo
  robusto (es. quella che contiene "Totale Competenze") invece di assumere un
  indice fisso.

## Design

### 1. Interfaccia e registro

Nuova cartella `lib/services/payslip_layouts/`:

- `payslip_layout.dart` — interfaccia `PayslipLayout`:
  - `String get id` (stabile, persistito in DB, es. `'job'`);
  - `bool riconosce(PdfContenuto contenuto)`;
  - `BustaPagaEstratti estrai(PdfContenuto contenuto)` (sincrona: il PDF è già letto in `PdfContenuto`).
- `payslip_layout_registry.dart` — elenco ordinato di layout; `rileva(contenuto)`
  restituisce il primo che riconosce il PDF o `null`.
- `job_layout.dart` — `JobLayout`: adattatore sottile sopra `BustaPagaRegexParser` e le
  funzioni a coordinate esistenti, che **restano dove sono** (nessuno
  spostamento di codice, rischio di regressione minimo).
- `<nuovo>_layout.dart` — nuovo layout; nome definitivo da decidere con
  l'utente (nome neutro finché non noto il software paghe).

`PdfContenuto` è un nuovo carrier (testo estratto, parole con coordinate per
pagina) che generalizza quanto oggi il servizio di import tiene in
`extractedText`/`ratei`/`voci`; è l'unica cosa che i layout vedono del PDF. Il
nome e i campi esatti si fissano nel piano.

`pdf_import_service.dart` diventa orchestratore: valida il PDF, costruisce
`PdfContenuto`, chiede al registro il layout, delega. Nessun layout riconosce il
PDF → alert bloccante come oggi (il form non si apre).

### 2. Riconoscimento

Ogni layout dichiara una firma testuale sul testo/parole. Per JOB la firma è
esplicita nel testo (`JOB - Copyright …`, presente nelle fixture dei test). Test di
non-ambiguità: ogni fixture è riconosciuta da **uno solo** dei layout.
L'ordine nel registro è deterministico; il primo che combacia vince.

### 3. Estrazione del nuovo layout

Parole con coordinate → colonne/righe → `BustaPagaEstratti` (netto, periodo,
competenze, trattenute, ore, ratei). Riusa `VoceCompetenza`, `RateoCategoria`
ecc. Warning di validazione (es. netto>lordo) restano gli stessi del contratto.

Mappatura ratei (coerente col parser JOB, che ignora il riporto):
- **maturato** = "spett." (CUMULATO dell'anno corrente, rateo mensile x mesi
  trascorsi; come nel layout JOB, dove residuo = residuo A.P. + maturato −
  goduto, vedi `lib/services/busta_paga_regex_parser.dart`). Il valore
  "rateo m.:NN,NN" NON va usato come maturato: va scartato in estrazione;
- **goduto** = goduti cumulati;
- **residuo** = residuo stampato, non ricalcolato.

Da riconfermare con l'utente prima del Task 5.
Ex festività: assenti nel layout di esempio → categoria vuota (`RateoCategoria.vuoto`).

### 4. Persistenza

Nuova colonna Drift `layout` (testo, default `'job'`), migrazione additiva
`schemaVersion` 6→7; le buste esistenti restano valide. `BustaPaga.layout`
(String) valorizzato dall'import; non modificabile dall'utente. Usa la skill
`drift-migration` in implementazione (build_runner incluso).

### 5. Test e privacy

- Il PDF di esempio contiene dati personali: **non entra nel repo**. Le fixture
  sono sintetiche e anonimizzate (liste di parole con coordinate, come i test
  `pdf_*_coordinate_test.dart`).
- Test: registro (riconoscimento/ordine/nessun match), `JobLayout` invariato
  (i test esistenti del parser passano senza modifiche), nuovo layout su
  fixture, migrazione v6→v7 (estendere `database_migration_test.dart`).
- Verifica statica con `flutter analyze`/`flutter test`; il test visivo resta
  dell'utente (regole di CLAUDE.md).

## Rischi

- Firma di un layout troppo generica → falsi positivi tra layout: mitigato dal
  test di non-ambiguità.
- Spostare `JobLayout` deve essere un puro refactor: i test esistenti sono la
  rete di sicurezza; nessun cambio di regex nello stesso passo.
- Selezione pagina del nuovo layout basata su un solo PDF di esempio: cercare
  altri esempi (es. 13a) prima del rilascio.

## Sequenza di lavoro suggerita

1. Interfaccia + registro + `JobLayout` (refactor puro, test verdi).
2. Colonna `layout` + migrazione v7.
3. Nuovo layout + fixture sintetiche.
4. Aggiornare `CLAUDE.md` (sezione import PDF) e `BACKLOG.md`.

Sviluppo delegato a dev1/dev2 e revisione con `revisore` dopo ogni run, come da
regole di CLAUDE.md.
