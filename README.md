# Buts

App iOS personale per tracciare la propria busta paga — niente cloud,
niente account, i dati restano sempre sul telefono.

## Cosa fa

- **Si apre direttamente sull'archivio**: nessuna schermata di benvenuto,
  nessun onboarding — l'unica cosa che l'app fa è tracciare buste paga, e lo
  mostra da subito.
- **Import PDF, non inserimento manuale**: basta scegliere il PDF del
  cedolino dal telefono. Un parser dedicato al layout del software paghe
  "JOB" legge automaticamente netto, voci di competenza, ferie/ROL/permessi/
  ex festività, straordinari e trattenute — niente OCR, niente digitazione a
  mano.
- **Anti-duplicati**: se provi a importare due volte lo stesso cedolino
  (stesso anno/mese/tipo), l'app se ne accorge subito, prima ancora di
  aprire il form.
- **Modifica inline con conferma**: ogni dato importato resta modificabile
  direttamente nel dettaglio, con un riepilogo di cosa è cambiato prima di
  salvare.
- **Statistiche**: andamento di netto/lordo, ferie/ROL/permessi/ex
  festività residui e straordinari nel tempo, con un selettore di periodo a
  tocchi pensato per essere usato con anni di storico.

## Design

Il sistema visivo dell'app si chiama **"Pulse"**: bold, dark-first,
ispirato ai prodotti fintech moderni — non il look Flutter/Material di
default. Nessun asset generico: tipografia di sistema (SF Pro via
`CupertinoTheme`, nessun font bundlato), icone disegnate ad hoc invece di
un set standard, superfici a colore pieno senza effetti di vetro/blur.
L'app è **solo dark mode**.

## Stack tecnico

- **Flutter**, target iOS-first (Cupertino, nessun target Android attivo)
- **Riverpod** (`flutter_riverpod`) per lo stato applicativo
- **Drift** (SQLite tipizzato, con schema versionato e migrazioni additive)
  per la persistenza locale
- **Syncfusion PDF** (`syncfusion_flutter_pdf`) per leggere il testo dei
  cedolini importati
- **fl_chart** per i grafici di Statistiche

## Setup

1. Verifica l'ambiente: `flutter doctor -v`
2. Installa le dipendenze: `flutter pub get`
3. Avvia sul simulatore iOS: `flutter run`

## Struttura

L'app è a sezione singola: si apre direttamente sull'archivio Buste Paga,
con sotto-navigazione Archivio/Statistiche + import PDF. Persistenza Drift
(SQLite).

```
lib/
  main.dart                    # entry point (ProviderScope, intl 'it_IT')
  theme/                       # design tokens: colori, spaziature, tipografia
  models/                      # BustaPaga, VoceCompetenza, TipoBustaPaga
  data/                        # persistenza Drift (SQLite) — AppDatabase, tabelle
  providers/                   # provider Riverpod (repository buste paga, reminder)
  services/                    # import PDF (file picker, copia file), parser regex, reminder
  screens/
    buste_paga/                  # sezione radice: contenitore, archivio, statistiche,
                                  # form di import, dettaglio
  widgets/                      # componenti riutilizzabili
  utils/                        # utility varie
```

`lib/widgets/` raggruppa per famiglia di stile:
- **Pulse** (`pulse_surface.dart`, `pulse_icon.dart`, `pulse_section_card.dart`,
  `pulse_mesh_background.dart`, `value_tile.dart`, `spring_button.dart`) —
  il materiale a colore pieno standard di card/sezioni/icone.
- **Flat, per barre e popup** (`flat_chip_button.dart`, `app_alert_dialog.dart`) —
  sotto-navigazione, barre di azione e dialoghi di conferma.
- **Specifici busta paga**, condivisi tra dettaglio e form di import
  (`busta_paga_hero_card.dart`, `busta_paga_stat_row.dart`,
  `busta_paga_maturazioni_section.dart`, `busta_paga_documento_chip.dart`,
  `busta_paga_summary_hero.dart`, `busta_paga_list_item.dart`,
  `busta_paga_competenze_section.dart`, `trattenuta_edit_row.dart`,
  `voce_competenza_edit_row.dart`, `period_year_month_picker.dart`).

