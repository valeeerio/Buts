# Backlog Buts

Traccia lo stato di avanzamento dello sviluppo. Aggiornare ad ogni sessione di
lavoro: spostare le voci tra le sezioni, non cancellarle (storico utile).
Contesto di prodotto/stile completo in `CLAUDE.md`.

Legenda skill: skill di Claude Code da invocare per quel task (vedi
`.claude/skills` o l'elenco skill disponibili in sessione).

## Buste Paga

## Budget

## Infrastruttura

## Analisi tecnica (2026-08-03)

Note emerse da una revisione dello script di parsing PDF e della schermata
Statistiche — non sono task spuntabili, solo materiale da cui aprire
eventuali task in una sessione futura, quando/se l'utente deciderà di
intervenire.

**Parser regex — risolto il 2026-08-04** (`lib/services/busta_paga_regex_parser.dart`,
tarato sul solo layout del software paghe "JOB"): righe multiple
"Straordinario"/"Retribuzione ordinaria" ora sommate invece di prendere
solo la prima; aggiunta validazione incrociata `netto > lordo` (unico
controllo sicuro senza falsi positivi — un controllo ferie/ROL
residuo-vs-maturato avrebbe prodotto falsi allarmi per via del riporto
dall'anno precedente, deliberatamente ignorato dal parser); chiusa come
non-bug la mancanza di warning sugli straordinari a zero (la riga non
compare nel PDF se non c'è stato straordinario quel mese, zero silenzioso
è il dato corretto). Copertura test estesa in
`test/busta_paga_regex_parser_test.dart` con 10 nuovi casi (tipo esplicito
tredicesima/quattordicesima, warning periodo/lordo/INPS/netto non
trovati, calcolo "Altre trattenute", righe multiple sommate, nuovo warning
netto>lordo).

**Statistiche — campi del modello mai visualizzati** (nessuna decisione
presa su quali implementare, elenco di candidati per una futura sessione
dedicata): `trattenute` (mappa INPS + "Altre trattenute IRPEF+varie", mai
mostrata nel tempo), `ferieMaturate`/`ferieGodute` (solo il residuo è
mostrato oggi), `rolMaturati`/`rolGoduti` (idem), `oreLavorate` (stimato
dal parser ma mai graficato). Quando si deciderà di espandere Statistiche,
l'utente li vuole descritti come task pronti da implementare — stesso
pattern dei 3 grafici esistenti (LineChart/BarChart + tabella
riepilogativa sotto) — non come mockup preliminari da validare prima.

**Permessi R.O.L. — due righe nel PDF, chiarita il 2026-09-02** (emersa il
2026-08-04 fixando la visualizzazione di Straordinari): il PDF reale ha sia
una riga cumulativa "Permessi (R.O.L.)" nei ratei (letta dal parser come
`rolGoduti`/`permessiGoduti`) sia una riga distinta "Permessi riduz. orario
goduti" tra le competenze del mese (`permessiGodutiMese`). Verificato su un
cedolino reale (agosto 2026): sono la stessa categoria letta a granularità
diversa — residuo inizio periodo + maturato − goduto cumulativo = residuo
attuale, e il goduto cumulativo meno il valore mensile di agosto è coerente
col cumulativo di luglio. Non è un bug, nessuna modifica al parser
necessaria — `permessiGodutiMese` va usato solo per un eventuale trend
mensile in Statistiche, mai sommato al residuo annuo cumulativo. Non è più
un blocco per il rilascio.

## Redesign "Pulse" e lavoro pre-rilascio (sessione 2026-08-28 → 2026-09-01)

Restyling totale da "Liquid Glass" a "Pulse" (sistema bold/dark-first
ispirato a Revolut, validato dall'utente il 2026-08-28) — vedi CLAUDE.md
sezione "Stile visivo" per il dettaglio completo del sistema di design.
Applicato ad Archivio/sidecar, dettaglio, form di import, Statistiche.

Lavoro aggiuntivo della sessione conclusa il 2026-09-01, in attesa di
merge in `main` via Pull Request (vedi commit su
`worktree-liquid-glass-riscaldato`):
- Nuovo selettore periodo a tocchi in Statistiche (`PeriodYearMonthPicker`),
  sostituisce il precedente `CupertinoRangeSlider` (rimosso, percepito
  impreciso dall'utente).
- Fix multi-round della barra flottante Salva/Annulla e Conferma/Modifica:
  artefatti d'angolo su device reale (causa: raggio del `ClipRRect` esterno
  disallineato dal riempimento interno di `FlatChipButton`), poi bug di
  layout che rendeva la barra invisibile (`CrossAxisAlignment.stretch` su
  vincolo di altezza infinito, risolto con `IntrinsicHeight`), poi angoli
  tondi su tutti i lati invece del taglio piatto al centro, poi vuoto reale
  nel gap tra i due chip.
- Form di import: editing "a fiducia" — netto/lordo/trattenute diventano
  di sola lettura quando il parser li ha verificati aritmeticamente contro
  i totali stampati sul PDF (nuovi flag `lordoVerificato`/
  `trattenuteVerificate`/`nettoVerificato` su `BustaPagaEstratti`); periodo
  non riconosciuto ora blocca esplicitamente "Salva" finché l'utente non lo
  conferma (non più un default silenzioso sul mese corrente).
- Parser: tipo mensilità (13a/14a) ora letto direttamente da una voce di
  competenza esplicita ("N.ma mensilità") quando presente, invece di
  essere sempre dedotto dal mese — scoperto analizzando 5 PDF reali forniti
  dall'utente, con nuove fixture di test permanenti (dati anagrafici
  anonimizzati).
- Pulizia repo: rimossi dal tracking file scratch (`.superpowers/`) e
  artefatti Android auto-generati finiti in un commit per errore (l'app è
  iOS-primaria, nessun target Android attivo) — vedi `.gitignore`.

## Layout PDF "prestampato" (2026-09-20) — punti aperti

Il secondo layout è tarato su un solo PDF di esempio (fuori dal repo); le
fixture sintetiche verificano la logica, non la stabilità del modulo.

- [ ] Secondo PDF del layout prestampato (con Ex festività, Ferie godute,
      13ª/14ª) per confermare le ancore; oggi le colonne Ex festività sono
      ipotizzate uguali a Ferie e Ex festività/Ferie godute non sono osservate
      su PDF reali
- [ ] L'accettazione sul PDF reale (`test/prestampato_acceptance_test.dart`)
      asserisce solo identità e ferie/ROL >= 0: rafforzare col secondo PDF
- [ ] Nome definitivo del layout (oggi id provvisorio `prestampato`; cambiarlo
      dopo il rilascio richiede una migrazione dei valori `layout` salvati)
- [ ] Firma del layout prestampato basata su etichette generiche di un modulo
      prestampato: rischio di falsi positivi con altri software paghe;
      aggiungere "Netto da pagare" o un'etichetta più specifica verificandola
      sul secondo PDF
- [ ] Il ROL goduti cumulato dei ratei non coincide con le ore della voce
      ROL GODUTI del mese; da chiarire con l'utente
- [ ] 13ª/14ª e cedolino a pagina singola: oggi il classificatore
      restituisce SEMPRE tipo `mensile`, quindi una 13ª/14ª di questo layout
      verrebbe bloccata dal controllo anti-duplicati come "mensile già
      presente" (import legittimo bloccato) finché non c'è un cedolino di
      esempio per rilevarla dalla tipologia
- [ ] Chiavi trattenute normalizzate (`CTR FPLD` → `INPS`, `IRPEF NETTA` →
      `IRPEF`): confermare guardando l'archivio
- [ ] Minor differiti della revisione: righe oltre 80 colonne, test di
      `_paroleDiPagina` su pagina illeggibile, copertura diretta della
      migrazione Drift v6→v7

## Rilascio (obiettivo sessione 2026-08-09, ancora valido)

- [x] Merge del branch `redesign-schema-busta-paga` in `main` (voci di
      competenza, permessi mensili, ex festività) — mergiato 2026-08-09,
      branch locale e remoto ripuliti dopo il merge
- [x] Merge del redesign "Pulse" + lavoro sessione 2026-09-01 in `main`
      (vedi sezione sopra) — mergiato (PR #4), `main` allineato a `origin/main`
- [x] Build e installazione diretta su iPhone via Xcode/cavo (no
      TestFlight/App Store — decisione utente 2026-08-09) — **completata
      2026-09-03, prima versione (1.0.0+1) installata e funzionante sul
      device reale**. Nota tecnica per il futuro: il primo run da Xcode in
      configurazione Debug crashava all'apertura diretta dall'icona
      (comportamento normale di Flutter su iOS — le build Debug usano JIT,
      che iOS permette solo col debugger agganciato); risolto passando la
      build configuration dello scheme "Run" a Release (Product → Scheme →
      Edit Scheme → Run → Build Configuration → Release), che è AOT e non
      richiede Xcode collegato per restare aperta
- [x] Icona app impostata (2026-08-09): sorgente in `assets/icon/app_icon.png`,
      generata su tutte le dimensioni iOS via `flutter_launcher_icons`
      (`dart run flutter_launcher_icons`), sostituisce il placeholder Flutter
      di default
- [x] `pubspec.yaml` corretto (2026-08-09): descrizione allineata al
      tracciamento buste paga, versione `1.0.0+1` per la prima release

## Fatto

Storico compresso il 2026-08-02 — dettaglio recuperabile dai commit Git su
`main`. Riassunto dei blocchi di lavoro completati fin qui: seed mock
rimosso e sostituito da import PDF reale con parser regex dedicato;
introduzione del tipo mensilità (mensile/13esima/14esima) nel modello, nel
parser e nelle statistiche; redesign completo in stile "Liquid Glass" di
Archivio, hero, dettaglio e Statistiche; passaggio della modifica busta
paga da un form separato a editing inline nel dettaglio; estrazione dei
widget condivisi tra dettaglio e form di import; redesign dei popup in
stile flat coerente con la sotto-navigazione; fix del tracking dello
slider di periodo. Vedi `CLAUDE.md` per lo stato architetturale attuale.

Branch `redesign-schema-busta-paga` (2026-08-04 → 2026-08-09, in attesa di
merge in `main`): parser regex reso più robusto su righe multiple e
validazione incrociata netto/lordo; fix unità di misura Straordinari (ore,
non euro) nel dettaglio; il PDF si apre nell'anteprima nativa di sistema
invece della condivisione; estrazione delle voci di competenza individuali
(`VoceCompetenza`, lordo/straordinari ora derivati da queste invece che
campi scalari indipendenti), dei permessi riduz. orario goduti del mese e
delle ex festività maturate/godute/residue dal PDF, con redesign della hero
card e nuova sezione Competenze editabile. Vedi `CLAUDE.md` per il dettaglio
architetturale.

## Decisioni archiviate (non da rimettere in discussione senza motivo nuovo)

- **AI locale on-device per estrazione dati busta paga — abbandonata
  (2026-07-30)**. Alla luce di quanto emerso nella sessione odierna,
  l'utente ha deciso di abbandonare l'idea. Il parser regex
  (`lib/services/busta_paga_regex_parser.dart`, mirato al layout del
  software paghe "JOB") resta l'unico meccanismo di precompilazione dati da
  PDF, nessun piano di sostituirlo con un modello locale.

## Manutenzione ricorrente (da fare periodicamente, non una tantum)

- `design-audit` dopo ogni serie di modifiche UI o prima di una consegna
- `flutter-check` dopo ogni modifica a codice Dart prima di considerare concluso un task
- `drift-migration` ogni volta che si tocca `lib/data/` o lo schema dati cambia
