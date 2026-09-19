import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/busta_paga.dart';
import '../../providers/buste_paga_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/busta_paga_formatting.dart';
import '../../utils/busta_paga_validation.dart';
import '../../widgets/app_alert_dialog.dart';
import '../../widgets/busta_paga_competenze_section.dart';
import '../../widgets/busta_paga_documento_chip.dart';
import '../../widgets/busta_paga_hero_card.dart';
import '../../widgets/busta_paga_maturazioni_section.dart';
import '../../widgets/busta_paga_stat_row.dart';
import '../../widgets/flat_chip_button.dart';
import '../../widgets/pulse_icon.dart';
import '../../widgets/pulse_section_card.dart';
import '../../widgets/pulse_surface.dart';
import '../../widgets/spring_button.dart';
import '../../widgets/stationary_push_bar.dart';
import '../../widgets/trattenuta_edit_row.dart';
import '../../widgets/voce_competenza_edit_row.dart';

/// Altezza riservata alla barra flottante "Conferma/Modifica" (o
/// "Salva/Annulla" in modifica) in basso, usata come padding in fondo al
/// contenuto scrollabile perché l'ultima card non finisca nascosta/tappabile
/// dietro di essa. Nessun effetto di dissolvenza in questa schermata
/// (abbandonato il 2026-07-31): la hero card resta fissa in alto fuori dalla
/// lista e il resto scorre con scroll naturale — questo valore è quindi un
/// margine di sicurezza puro, non un calcolo legato a uno shader. Più
/// generoso di quanto basterebbe alla sola `_ActionBar` (che da sola misura
/// meno) perché in modifica l'ultimo elemento scrollabile è spesso il footer
/// testuale (due righe) della sezione Trattenute, più alto del contenuto
/// tipico della vista di sola lettura: senza questo margine extra, quel
/// footer restava visibilmente sovrapposto/nascosto dietro la barra invece
/// di poterci scorrere sopra come qualunque altra card.
const double _actionBarReservedHeight = 80;

/// Etichette del tipo busta paga, condivise da hero (sola lettura/modifica)
/// e dal picker `_pickTipo` — stessa mappa duplicata in
/// `busta_paga_form_screen.dart` (nessun modulo condiviso per 3 stringhe).
const _tipoLabels = {
  TipoBustaPaga.mensile: 'Mensile',
  TipoBustaPaga.tredicesima: '13esima',
  TipoBustaPaga.quattordicesima: '14esima',
};

/// Label "Marzo 2026" per una data di periodo, usata solo dal diff (vedi
/// [buildBustaPagaEditDiff]) — estratta da `_BustaPagaDetailScreenState` come
/// funzione di livello file (non usa alcuno stato dell'istanza) insieme al
/// diff stesso, per la stessa ragione di testabilità.
String _periodoLabelForDate(DateTime data) {
  final formatted = DateFormat('MMMM yyyy', 'it_IT').format(data);
  return formatted[0].toUpperCase() + formatted.substring(1);
}

/// Calcola lordo/straordinari/netto derivati dalle competenze/trattenute
/// correntemente in editing — usato sia dal valore mostrato live nell'hero
/// (`build()`) sia dal salvataggio (`_save`), tramite
/// `_BustaPagaDetailScreenState._valoriDerivatiEditing`.
///
/// Funzione pura (nessuna dipendenza da stato del widget): estratta a
/// livello di file per la stessa ragione di testabilità di
/// [buildBustaPagaEditDiff]. `@visibleForTesting`: non è pensata per essere
/// chiamata da altrove nell'app.
///
/// Il fallback al vecchio lordo/straordinari (`corrente.lordo`/
/// `corrente.straordinari`) si applica **solo** se [competenzeVuoteInPartenza]
/// è vero **e** [competenze] è ancora vuota nello stato corrente — cioè una
/// busta paga pre-migrazione mai riaperta in modifica, con competenze mai
/// toccate durante la sessione di editing. Se l'utente parte da una lista
/// vuota e aggiunge righe reali, o parte da una lista non vuota e la svuota
/// esplicitamente (swipe-to-delete di tutte le righe), lordo/straordinari
/// derivano sempre da `computeLordo(competenze)`/
/// `computeStraordinari(competenze)` sullo stato corrente, coerentemente con
/// l'invariante "lordo/straordinari derivati da competenze" di CLAUDE.md. Il
/// netto segue la stessa condizione: si mantiene il vecchio valore solo
/// quando anche il lordo usa il fallback e le [trattenute] correnti sono
/// vuote; in ogni altro caso si ricalcola da lordo/trattenute correnti.
@visibleForTesting
({double lordo, double straordinari, double netto}) valoriDerivatiEditing({
  required BustaPaga corrente,
  required List<VoceCompetenza> competenze,
  required Map<String, double> trattenute,
  required bool competenzeVuoteInPartenza,
}) {
  final usaFallback = competenzeVuoteInPartenza && competenze.isEmpty;
  final lordo = usaFallback ? corrente.lordo : computeLordo(competenze);
  final straordinari =
      usaFallback ? corrente.straordinari : computeStraordinari(competenze);
  final netto = (usaFallback && trattenute.isEmpty)
      ? corrente.netto
      : computeNetto(lordo, trattenute);
  return (lordo: lordo, straordinari: straordinari, netto: netto);
}

/// Costruisce l'elenco leggibile delle differenze fra due versioni della
/// stessa busta paga, mostrato nel popup "Hai modificato i seguenti dati,
/// confermi?" prima di salvare una modifica inline (vedi
/// `_BustaPagaDetailScreenState._save`/`_buildDiff`, l'unico punto di
/// chiamata reale nell'app).
///
/// Funzione pura di [vecchia]/[nuova] (nessuna dipendenza da stato del
/// widget): estratta a livello di file — invece di restare un metodo privato
/// della `State` — solo per poter essere testata direttamente, senza dover
/// pilotare l'intera schermata attraverso Riverpod/Drift.
/// `@visibleForTesting`: non è pensata per essere chiamata da altrove
/// nell'app.
///
/// Ogni importo (Netto/Lordo, trattenute, importi di competenza) passa
/// sempre da un helper di formattazione con segno di
/// `lib/utils/busta_paga_formatting.dart` (`formatEuroConSegno` per
/// Netto/Lordo/competenze, `formatTrattenuta` per le trattenute — quella
/// convenzione INVERTE il segno mostrato, propria delle sole trattenute), mai
/// da "€ " concatenato a mano davanti a `formatEuro`: sia le trattenute
/// (conguaglio/storno a credito, es. "Differenza di arrotondamento") sia le
/// voci di competenza (storno a debito, vedi `_rigaVoceCompetenza` in
/// `busta_paga_regex_parser.dart`) possono avere un valore negativo, e
/// `formatEuro` da solo antepone già un "-" al numero — una concatenazione
/// manuale produrrebbe un doppio segno fuorviante ("€ -0,14") — bug reale
/// corretto qui, non un'ipotesi.
@visibleForTesting
List<String> buildBustaPagaEditDiff(BustaPaga vecchia, BustaPaga nuova) {
  final diff = <String>[];

  void addIfChanged(String label, double oldValue, double newValue,
      {String Function(double) format = formatNumber}) {
    if (format(oldValue) != format(newValue)) {
      diff.add('$label: ${format(oldValue)} → ${format(newValue)}');
    }
  }

  if (_periodoLabelForDate(vecchia.periodo) !=
      _periodoLabelForDate(nuova.periodo)) {
    diff.add(
      'Periodo: ${_periodoLabelForDate(vecchia.periodo)} → '
      '${_periodoLabelForDate(nuova.periodo)}',
    );
  }
  if (vecchia.tipo != nuova.tipo) {
    diff.add(
      'Tipo: ${_tipoLabels[vecchia.tipo]} → ${_tipoLabels[nuova.tipo]}',
    );
  }
  // `formatEuroConSegno`, non `formatEuro` nudo: Netto/Lordo sono
  // normalmente non negativi ma possono eccezionalmente esserlo (netto se
  // le trattenute superano il lordo, vedi doc di `formatEuroConSegno`) —
  // stesso helper già usato per questi due campi nella hero card
  // (`lordoDisplay`/`nettoDisplay`), per coerenza di stile col resto di
  // questo popup (che mostra sempre "€ " per ogni altro importo) e senza
  // rischio di doppio segno.
  addIfChanged('Netto', vecchia.netto, nuova.netto, format: formatEuroConSegno);
  addIfChanged('Lordo', vecchia.lordo, nuova.lordo, format: formatEuroConSegno);
  addIfChanged('Straordinari', vecchia.straordinari, nuova.straordinari);
  addIfChanged('Ferie maturate', vecchia.ferieMaturate, nuova.ferieMaturate);
  addIfChanged('Ferie godute', vecchia.ferieGodute, nuova.ferieGodute);
  addIfChanged('Ferie residue', vecchia.ferieResidue, nuova.ferieResidue);
  addIfChanged('ROL maturati', vecchia.rolMaturati, nuova.rolMaturati);
  addIfChanged('ROL goduti', vecchia.rolGoduti, nuova.rolGoduti);
  addIfChanged('ROL residui', vecchia.rolResidui, nuova.rolResidui);
  addIfChanged('Permessi goduti', vecchia.permessiGoduti, nuova.permessiGoduti);
  addIfChanged(
      'Permessi (mese)', vecchia.permessiGodutiMese, nuova.permessiGodutiMese);
  addIfChanged('Ex festività maturate', vecchia.exFestivitaMaturate,
      nuova.exFestivitaMaturate);
  addIfChanged('Ex festività godute', vecchia.exFestivitaGodute,
      nuova.exFestivitaGodute);
  addIfChanged('Ex festività residue', vecchia.exFestivitaResidue,
      nuova.exFestivitaResidue);
  addIfChanged('Ore lavorate', vecchia.oreLavorate, nuova.oreLavorate);

  final chiavi = {...vecchia.trattenute.keys, ...nuova.trattenute.keys};
  for (final chiave in chiavi) {
    final prima = vecchia.trattenute[chiave];
    final dopo = nuova.trattenute[chiave];
    // `formatTrattenuta`: stesso helper già usato dalla riga di sola
    // lettura (`trattenutaReadOnlyRow`) e dal prefisso di `trattenutaEditRow`, così
    // questo popup resta coerente con come lo stesso valore è mostrato
    // ovunque altrove in questa schermata — vedi doc del bug sopra.
    if (prima == null && dopo != null) {
      diff.add('Trattenuta $chiave: aggiunta (${formatTrattenuta(dopo)})');
    } else if (prima != null && dopo == null) {
      diff.add('Trattenuta $chiave: rimossa (era ${formatTrattenuta(prima)})');
    } else if (prima != null &&
        dopo != null &&
        formatEuro(prima) != formatEuro(dopo)) {
      diff.add(
        'Trattenuta $chiave: ${formatTrattenuta(prima)} → '
        '${formatTrattenuta(dopo)}',
      );
    }
  }

  // Stesso pattern del diff trattenute, chiave sulla descrizione (unica per
  // voce nell'uso reale di questo layout busta paga).
  final vecchieCompetenze = {
    for (final v in vecchia.competenze) v.descrizione: v
  };
  final nuoveCompetenze = {for (final v in nuova.competenze) v.descrizione: v};
  final descrizioniCompetenze = {
    ...vecchieCompetenze.keys,
    ...nuoveCompetenze.keys
  };
  // Quantità ASSENTE (vedi `VoceCompetenza.quantita`) mostrata come "—" nel
  // diff, stessa convenzione di sola lettura/editing — mai "0", fuorviante.
  String formatQuantita(double? v) => v == null ? '—' : formatNumber(v);
  for (final descrizione in descrizioniCompetenze) {
    final prima = vecchieCompetenze[descrizione];
    final dopo = nuoveCompetenze[descrizione];
    // `formatEuroConSegno`, non `formatTrattenuta`: a differenza delle
    // trattenute, qui il segno mostrato deve coincidere con quello del
    // valore (vedi doc del bug sopra), come per Netto/Lordo.
    if (prima == null && dopo != null) {
      diff.add('Competenza $descrizione: aggiunta '
          '(${formatQuantita(dopo.quantita)}, '
          '${formatEuroConSegno(dopo.importo)})');
    } else if (prima != null && dopo == null) {
      diff.add('Competenza $descrizione: rimossa '
          '(era ${formatQuantita(prima.quantita)}, '
          '${formatEuroConSegno(prima.importo)})');
    } else if (prima != null &&
        dopo != null &&
        (formatQuantita(prima.quantita) != formatQuantita(dopo.quantita) ||
            formatEuro(prima.importo) != formatEuro(dopo.importo))) {
      diff.add(
        'Competenza $descrizione: ${formatQuantita(prima.quantita)}, '
        '${formatEuroConSegno(prima.importo)} → '
        '${formatQuantita(dopo.quantita)}, '
        '${formatEuroConSegno(dopo.importo)}',
      );
    }
  }

  return diff;
}

/// Vista di dettaglio di una busta paga: hero con i dati principali, tabella
/// riepilogativa di Ferie/ROL/Permessi e sezioni di dettaglio per documento,
/// importi e trattenute. La barra flottante in basso permette di confermare
/// lo stato o attivare la modifica **inline** dei dati (nessuna navigazione
/// verso un form separato): in modifica le stesse card diventano editabili
/// sul posto, mantenendo lo stesso layout della vista di sola lettura.
///
/// `ConsumerStatefulWidget` (non più `ConsumerWidget`/`StatelessWidget`):
/// serve stato locale per la modalità modifica (flag `_isEditing` e un
/// `TextEditingController` per ogni campo numerico + periodo + trattenute).
class BustaPagaDetailScreen extends ConsumerStatefulWidget {
  final BustaPaga bustaPaga;

  const BustaPagaDetailScreen({super.key, required this.bustaPaga});

  @override
  ConsumerState<BustaPagaDetailScreen> createState() =>
      _BustaPagaDetailScreenState();
}

class _BustaPagaDetailScreenState extends ConsumerState<BustaPagaDetailScreen> {
  bool _isEditing = false;

  late DateTime _periodoEdit;
  late TipoBustaPaga _tipoEdit;

  late TextEditingController _oreLavorateCtrl;

  late TextEditingController _ferieMaturateCtrl;
  late TextEditingController _ferieGoduteCtrl;
  late TextEditingController _ferieResidueCtrl;

  late TextEditingController _rolMaturatiCtrl;
  late TextEditingController _rolGodutiCtrl;
  late TextEditingController _rolResiduiCtrl;

  // Nessun campo di editing collegato (sezioni UI rimosse perché ridondanti/
  // mai popolate, vedi CLAUDE.md): valori portati staticamente dal modello
  // fino al salvataggio, senza `TextEditingController` fantasma.
  late double _permessiGoduti;
  late double _permessiGodutiMese;

  late TextEditingController _exFestivitaMaturateCtrl;
  late TextEditingController _exFestivitaGoduteCtrl;
  late TextEditingController _exFestivitaResidueCtrl;

  late List<TrattenutaEditRow> _trattenuteEdit;
  late List<VoceCompetenzaEditRow> _competenzeEdit;

  /// `true` se la busta paga era priva di competenze **all'apertura** di
  /// questa sessione di editing (busta paga pre-migrazione mai riaperta in
  /// modifica, vedi CLAUDE.md — mai popolata). Distinto da
  /// `_competenzeCorrenti.isEmpty`, che riflette invece lo stato *attuale*
  /// dei controller e resta vero anche quando l'utente ha svuotato una lista
  /// che all'apertura non lo era (swipe-to-delete su tutte le righe, o
  /// descrizione dell'unica riga svuotata): in quel caso il fallback al
  /// vecchio lordo/straordinari NON deve applicarsi, l'invariante
  /// "lordo/straordinari derivati da competenze" (CLAUDE.md) impone di
  /// ricalcolarli su una lista vuota (cioè 0) — bug reale corretto qui, non
  /// un'ipotesi. Catturato una sola volta in [_enterEditing], mai
  /// ricalcolato durante la sessione di editing.
  late bool _competenzeVuoteInPartenza;

  /// Popola tutti i controller di editing dai valori correnti (letti dal
  /// provider) e attiva la modalità modifica.
  void _enterEditing(BustaPaga corrente) {
    _periodoEdit = corrente.periodo;
    _tipoEdit = corrente.tipo;

    _oreLavorateCtrl =
        TextEditingController(text: formatNumber(corrente.oreLavorate));

    _ferieMaturateCtrl =
        TextEditingController(text: formatNumber(corrente.ferieMaturate));
    _ferieGoduteCtrl =
        TextEditingController(text: formatNumber(corrente.ferieGodute));
    _ferieResidueCtrl =
        TextEditingController(text: formatNumber(corrente.ferieResidue));

    _rolMaturatiCtrl =
        TextEditingController(text: formatNumber(corrente.rolMaturati));
    _rolGodutiCtrl =
        TextEditingController(text: formatNumber(corrente.rolGoduti));
    _rolResiduiCtrl =
        TextEditingController(text: formatNumber(corrente.rolResidui));

    _permessiGoduti = corrente.permessiGoduti;
    _permessiGodutiMese = corrente.permessiGodutiMese;

    _exFestivitaMaturateCtrl =
        TextEditingController(text: formatNumber(corrente.exFestivitaMaturate));
    _exFestivitaGoduteCtrl =
        TextEditingController(text: formatNumber(corrente.exFestivitaGodute));
    _exFestivitaResidueCtrl =
        TextEditingController(text: formatNumber(corrente.exFestivitaResidue));

    _trattenuteEdit = corrente.trattenute.isEmpty
        ? [TrattenutaEditRow()]
        : corrente.trattenute.entries
            .map((e) => TrattenutaEditRow(chiave: e.key, importo: e.value))
            .toList();
    for (final row in _trattenuteEdit) {
      _attachTrattenutaListeners(row);
    }

    _competenzeVuoteInPartenza = corrente.competenze.isEmpty;
    _competenzeEdit = corrente.competenze.isEmpty
        ? [VoceCompetenzaEditRow()]
        : corrente.competenze
            .map((v) => VoceCompetenzaEditRow(
                  descrizione: v.descrizione,
                  // Vuoto (non "0") quando la quantità è ASSENTE, stessa
                  // convenzione già in uso per `importo == 0` subito sotto —
                  // preserva l'assenza al salvataggio senza modifiche, vedi
                  // `VoceCompetenzaEditRow.quantitaValue`.
                  quantita: v.quantita == null ? '' : formatNumber(v.quantita!),
                  // `formatEuro` da solo antepone già un "-" per un importo
                  // negativo (storno a debito, vedi doc di
                  // `VoceCompetenzaEditRow.negativo`): il costruttore della
                  // riga rileva quel segno dalla stringa, lo scorpora nel
                  // proprio campo `negativo` e precompila il controller col
                  // solo valore assoluto — nessun doppio segno col prefisso
                  // "€ "/"− € " dinamico del widget di editing.
                  importo: v.importo == 0 ? '' : formatEuro(v.importo),
                ))
            .toList();
    for (final row in _competenzeEdit) {
      _attachCompetenzaListeners(row);
    }

    setState(() => _isEditing = true);
  }

  /// Rebuild forzato ogni volta che descrizione/quantità/importo di una voce
  /// di competenza cambiano, così le celle Lordo/Straordinari (calcolate
  /// dalla lista competenze, sola lettura anche in editing) restano
  /// sincronizzate live — stesso meccanismo di `_onResiduiChanged`.
  void _attachCompetenzaListeners(VoceCompetenzaEditRow row) {
    row.descrizione.addListener(_onResiduiChanged);
    row.quantita.addListener(_onResiduiChanged);
    row.importo.addListener(_onResiduiChanged);
  }

  /// Rebuild forzato ogni volta che l'importo di una trattenuta cambia, così
  /// il Netto mostrato in hero (derivato da Lordo - trattenute) resta
  /// sincronizzato live — stesso meccanismo di `_attachCompetenzaListeners`.
  void _attachTrattenutaListeners(TrattenutaEditRow row) {
    row.importo.addListener(_onResiduiChanged);
  }

  List<VoceCompetenza> get _competenzeCorrenti => _competenzeEdit
      .where((row) => row.descrizione.text.trim().isNotEmpty)
      .map((row) => VoceCompetenza(
            descrizione: row.descrizione.text.trim(),
            quantita: row.quantitaValue,
            importo: row.importoValue,
          ))
      .toList();

  /// Mappa trattenute correnti da `_trattenuteEdit`, filtrando le righe con
  /// chiave vuota — stesso filtro già usato al salvataggio (`_save`), estratto
  /// qui perché riusato anche per il Netto mostrato live in `build`.
  Map<String, double> get _trattenuteCorrenti {
    final trattenute = <String, double>{};
    for (final row in _trattenuteEdit) {
      final chiave = row.chiave.text.trim();
      if (chiave.isEmpty) continue;
      trattenute[chiave] = row.valoreConSegno;
    }
    return trattenute;
  }

  void _onResiduiChanged() => setState(() {});

  void _disposeEditingControllers() {
    _oreLavorateCtrl.dispose();
    _ferieMaturateCtrl.dispose();
    _ferieGoduteCtrl.dispose();
    _ferieResidueCtrl.dispose();
    _rolMaturatiCtrl.dispose();
    _rolGodutiCtrl.dispose();
    _rolResiduiCtrl.dispose();
    _exFestivitaMaturateCtrl.dispose();
    _exFestivitaGoduteCtrl.dispose();
    _exFestivitaResidueCtrl.dispose();
    for (final row in _trattenuteEdit) {
      row.dispose();
    }
    for (final row in _competenzeEdit) {
      row.dispose();
    }
  }

  void _cancelEditing() {
    _disposeEditingControllers();
    setState(() => _isEditing = false);
  }

  double _parse(TextEditingController controller) =>
      parseItalianNumber(controller.text);

  void _addTrattenuta() {
    setState(() {
      final row = TrattenutaEditRow();
      _attachTrattenutaListeners(row);
      _trattenuteEdit.add(row);
    });
  }

  void _removeTrattenuta(int index) {
    setState(() {
      _trattenuteEdit[index].dispose();
      _trattenuteEdit.removeAt(index);
    });
  }

  void _addCompetenza() {
    setState(() {
      final row = VoceCompetenzaEditRow();
      _attachCompetenzaListeners(row);
      _competenzeEdit.add(row);
    });
  }

  void _removeCompetenza(int index) {
    setState(() {
      _competenzeEdit[index].dispose();
      _competenzeEdit.removeAt(index);
    });
  }

  Future<void> _pickPeriodo() async {
    DateTime tempSelection = _periodoEdit;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) {
        final accent =
            CupertinoDynamicColor.resolve(AppColors.pulseAccent, context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            0,
            AppSpacing.screenHorizontal,
            AppSpacing.sm,
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 280,
              child: PulseSurface(
                borderRadius: AppRadius.pulse,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SpringButton(
                          onPressed: () {
                            setState(() => _periodoEdit = tempSelection);
                            Navigator.of(context).pop();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            child: Text(
                              'Fatto',
                              style: AppTextStyles.pulseBodyEmphasis.copyWith(
                                color: accent,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: CupertinoDatePicker(
                        mode: CupertinoDatePickerMode.monthYear,
                        initialDateTime: _periodoEdit,
                        onDateTimeChanged: (value) => tempSelection = value,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickTipo() async {
    final scelta = await showCupertinoModalPopup<TipoBustaPaga>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Tipo busta paga'),
        actions: [
          for (final tipo in TipoBustaPaga.values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(context).pop(tipo),
              child: Text(_tipoLabels[tipo]!),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
      ),
    );
    if (scelta != null) setState(() => _tipoEdit = scelta);
  }

  void _showAlert(String title, String message) {
    final accent =
        CupertinoDynamicColor.resolve(AppColors.pulseAccent, context);
    showAppAlertDialog<void>(
      context: context,
      title: title,
      message: message,
      actions: [
        AppAlertAction(
          pulseGlyph: PulseIconGlyph.checkmark,
          label: 'OK',
          color: accent,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  /// Costruisce il candidato dai controller correnti, calcola il diff
  /// rispetto a [corrente] e, se non vuoto, chiede conferma esplicita
  /// prima di salvare — vedi CLAUDE.md/istruzioni task per il comportamento
  /// dettagliato dei 3 esiti (invariato / conferma / annulla).
  /// Lordo/straordinari/netto derivati dalle competenze/trattenute
  /// correntemente in editing: wrapper sullo stato dell'istanza attorno alla
  /// funzione pura di livello file [valoriDerivatiEditing] (vedi lì per il
  /// comportamento del fallback), usato sia dal valore mostrato live
  /// nell'hero (`build()`) sia dal salvataggio (`_save`) — unica fonte di
  /// verità, evita che il valore mostrato live diverga da quello
  /// effettivamente salvabile.
  ({double lordo, double straordinari, double netto}) _valoriDerivatiEditing(
      BustaPaga corrente) {
    return valoriDerivatiEditing(
      corrente: corrente,
      competenze: _competenzeCorrenti,
      trattenute: _trattenuteCorrenti,
      competenzeVuoteInPartenza: _competenzeVuoteInPartenza,
    );
  }

  /// Coppie etichetta/testo dei campi numerici "semplici" (non di
  /// competenze/trattenute, validate a parte) da controllare al salvataggio —
  /// vedi [firstInvalidNumericFieldLabel].
  List<(String, String)> get _campiNumericiSemplici => [
        ('Ore lavorate', _oreLavorateCtrl.text),
        ('Ferie (Maturato)', _ferieMaturateCtrl.text),
        ('Ferie (Goduto)', _ferieGoduteCtrl.text),
        ('Ferie (Residuo)', _ferieResidueCtrl.text),
        ('Permessi (Maturato)', _rolMaturatiCtrl.text),
        ('Permessi (Goduto)', _rolGodutiCtrl.text),
        ('Permessi (Residuo)', _rolResiduiCtrl.text),
        ('Ex festività (Maturato)', _exFestivitaMaturateCtrl.text),
        ('Ex festività (Goduto)', _exFestivitaGoduteCtrl.text),
        ('Ex festività (Residuo)', _exFestivitaResidueCtrl.text),
      ];

  void _save(BustaPaga corrente) {
    // Validazione "livello 2" (rete di sicurezza oltre agli `inputFormatters`
    // di `inlineNumberField`): blocca il salvataggio se un qualunque campo
    // numerico contiene testo non valido (lettere, formato USA col punto),
    // invece di procedere in silenzio con un valore azzerato/gonfiato — bug
    // reale corretto qui, non un'ipotesi (vedi CLAUDE.md/istruzioni task).
    final campoNonValido = firstInvalidNumericFieldLabel(
      campi: _campiNumericiSemplici,
      competenze: _competenzeEdit,
      trattenute: _trattenuteEdit,
    );
    if (campoNonValido != null) {
      _showAlert(
        'Valore non valido',
        'Il campo "$campoNonValido" non contiene un numero valido. '
            'Correggilo prima di salvare.',
      );
      return;
    }

    // Due righe di trattenuta con lo stesso nome collasserebbero
    // silenziosamente su una sola voce (`_trattenuteCorrenti` costruisce una
    // `Map` sulla chiave digitata) — bug reale corretto qui, non un'ipotesi.
    final chiaveDuplicata = firstDuplicateTrattenutaKey(_trattenuteEdit);
    if (chiaveDuplicata != null) {
      _showAlert(
        'Trattenuta duplicata',
        'Hai più voci di trattenuta chiamate "$chiaveDuplicata". '
            'Rinominale o rimuovi quella in più prima di salvare.',
      );
      return;
    }

    final trattenute = _trattenuteCorrenti;
    final competenze = _competenzeCorrenti;
    final valori = _valoriDerivatiEditing(corrente);

    final candidato = corrente.copyWith(
      periodo: _periodoEdit,
      tipo: _tipoEdit,
      netto: valori.netto,
      lordo: valori.lordo,
      straordinari: valori.straordinari,
      oreLavorate: _parse(_oreLavorateCtrl),
      ferieMaturate: _parse(_ferieMaturateCtrl),
      ferieGodute: _parse(_ferieGoduteCtrl),
      ferieResidue: _parse(_ferieResidueCtrl),
      rolMaturati: _parse(_rolMaturatiCtrl),
      rolGoduti: _parse(_rolGodutiCtrl),
      rolResidui: _parse(_rolResiduiCtrl),
      permessiGoduti: _permessiGoduti,
      permessiGodutiMese: _permessiGodutiMese,
      exFestivitaMaturate: _parse(_exFestivitaMaturateCtrl),
      exFestivitaGodute: _parse(_exFestivitaGoduteCtrl),
      exFestivitaResidue: _parse(_exFestivitaResidueCtrl),
      competenze: competenze,
      trattenute: trattenute,
    );

    // Stesso controllo dell'import (vedi `buste_paga_section_screen.dart`):
    // per le mensili anno+mese+tipo, per 13esima/14esima solo anno+tipo (il
    // mese esatto in cui vengono pagate varia, ma non può essercene più di
    // una dello stesso tipo nello stesso anno). Esclude se stessa dal
    // confronto (l'id non cambia durante la modifica).
    final conflitto = ref.read(busteRepositoryProvider).any((b) {
      if (b.id == candidato.id) return false;
      if (b.tipo != candidato.tipo) return false;
      if (candidato.tipo == TipoBustaPaga.mensile) {
        return b.periodo.year == candidato.periodo.year &&
            b.periodo.month == candidato.periodo.month;
      }
      return b.periodo.year == candidato.periodo.year;
    });
    if (conflitto) {
      _showAlert(
        'Busta paga già presente',
        'Hai già una busta paga per '
            '${periodoDisplayFor(periodo: candidato.periodo, tipo: candidato.tipo)} '
            'in archivio.',
      );
      return;
    }

    final diff = _buildDiff(corrente, candidato);

    if (diff.isEmpty) {
      _cancelEditing();
      return;
    }

    final accent =
        CupertinoDynamicColor.resolve(AppColors.pulseAccent, context);
    final textSecondary =
        CupertinoDynamicColor.resolve(AppColors.pulseTextSecondary, context);
    showAppAlertDialog<void>(
      context: context,
      title: 'Conferma modifiche',
      message: 'Hai modificato i seguenti dati, confermi?\n\n'
          '${diff.join('\n')}',
      actions: [
        AppAlertAction(
          pulseGlyph: PulseIconGlyph.close,
          label: 'Annulla',
          color: textSecondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppAlertAction(
          pulseGlyph: PulseIconGlyph.checkmark,
          label: 'Conferma',
          color: accent,
          onPressed: () async {
            Navigator.of(context).pop();
            try {
              await ref.read(busteRepositoryProvider.notifier).update(
                    candidato.copyWith(
                      statoVerifica: StatoVerificaBustaPaga.daConfermare,
                    ),
                  );
            } catch (_) {
              if (!mounted) return;
              // Salvataggio fallito: resta in modifica con i dati inseriti,
              // non perdere il lavoro dell'utente (vedi istruzioni task).
              _showAlert(
                'Salvataggio non riuscito',
                'Impossibile salvare le modifiche, riprova.',
              );
              return;
            }
            if (!mounted) return;
            _cancelEditing();
          },
        ),
      ],
    );
  }

  /// Costruisce l'elenco leggibile delle differenze fra due versioni della
  /// stessa busta paga per il popup di conferma prima di salvare una
  /// modifica inline. Logica vera e propria estratta nella funzione di
  /// livello file [buildBustaPagaEditDiff] (non un metodo di questa `State`)
  /// per essere testabile senza dover pilotare l'intera schermata attraverso
  /// Riverpod/Drift — questo resta un sottile delegato, unico punto di
  /// chiamata reale nell'app.
  List<String> _buildDiff(BustaPaga vecchia, BustaPaga nuova) =>
      buildBustaPagaEditDiff(vecchia, nuova);

  @override
  void dispose() {
    if (_isEditing) {
      _disposeEditingControllers();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final buste = ref.watch(busteRepositoryProvider);
    final corrente = buste.firstWhere((b) => b.id == widget.bustaPaga.id,
        orElse: () => widget.bustaPaga);
    final periodoLabelVista = _isEditing
        ? periodoDisplayFor(periodo: _periodoEdit, tipo: _tipoEdit)
        : bustaPagaPeriodoDisplay(corrente);

    // Fill leggermente trasparente (stesso token `pulseBackground` dello
    // sfondo piatto della schermata, vedi `_floatingBarBackground`) per il
    // "chrome" della nav bar sopra il contenuto scrollabile sottostante.
    final navBarBackground =
        CupertinoDynamicColor.resolve(AppColors.pulseBackground, context)
            .withValues(alpha: 0.55);

    return ColoredBox(
      color: CupertinoDynamicColor.resolve(AppColors.pulseBackground, context),
      child: CupertinoPageScaffold(
        backgroundColor: CupertinoColors.transparent,
        navigationBar: CupertinoNavigationBar(
          backgroundColor: navBarBackground,
          border: null,
        ),
        child: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenHorizontal,
                      AppSpacing.sm,
                      AppSpacing.screenHorizontal,
                      0,
                    ),
                    child: BustaPagaHeroCard(
                      isConfermato: corrente.statoVerifica ==
                          StatoVerificaBustaPaga.confermato,
                      periodoLabel: periodoLabelVista,
                      lordoDisplay: formatEuroConSegno(_isEditing
                          ? _valoriDerivatiEditing(corrente).lordo
                          : corrente.lordo),
                      nettoDisplay: formatEuroConSegno(_isEditing
                          ? _valoriDerivatiEditing(corrente).netto
                          : corrente.netto),
                      onTapPeriodo: _isEditing ? _pickPeriodo : null,
                      onTapTipo: _isEditing ? _pickTipo : null,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(
                          bottom: _actionBarReservedHeight),
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (rect) {
                          const fadeHeight = 32.0;
                          var topStop =
                              (fadeHeight / rect.height).clamp(0.0, 1.0);
                          final bottomStop =
                              1 - (fadeHeight / rect.height).clamp(0.0, 1.0);
                          topStop = topStop.clamp(0.0, bottomStop);
                          return LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: const [
                              CupertinoColors.transparent,
                              CupertinoColors.white,
                              CupertinoColors.white,
                              CupertinoColors.transparent,
                            ],
                            stops: [0.0, topStop, bottomStop, 1.0],
                          ).createShader(rect);
                        },
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.screenHorizontal,
                            AppSpacing.lg,
                            AppSpacing.screenHorizontal,
                            AppSpacing.xl,
                          ),
                          children: [
                            if (corrente.fileOrigine != null) ...[
                              BustaPagaDocumentoChip(
                                filePath: corrente.fileOrigine!,
                                periodo: corrente.periodo,
                                tipo: corrente.tipo,
                              ),
                              const SizedBox(height: AppSpacing.lg),
                            ],
                            BustaPagaMaturazioniSection(
                              isEditing: _isEditing,
                              ferieMaturate:
                                  formatNumber(corrente.ferieMaturate),
                              ferieGodute: formatNumber(corrente.ferieGodute),
                              ferieResidue: formatNumber(corrente.ferieResidue),
                              rolMaturati: formatNumber(corrente.rolMaturati),
                              rolGoduti: formatNumber(corrente.rolGoduti),
                              rolResidui: formatNumber(corrente.rolResidui),
                              exFestivitaMaturate:
                                  formatNumber(corrente.exFestivitaMaturate),
                              exFestivitaGodute:
                                  formatNumber(corrente.exFestivitaGodute),
                              exFestivitaResidue:
                                  formatNumber(corrente.exFestivitaResidue),
                              ferieMaturateCtrl:
                                  _isEditing ? _ferieMaturateCtrl : null,
                              ferieGoduteCtrl:
                                  _isEditing ? _ferieGoduteCtrl : null,
                              ferieResidueCtrl:
                                  _isEditing ? _ferieResidueCtrl : null,
                              rolMaturatiCtrl:
                                  _isEditing ? _rolMaturatiCtrl : null,
                              rolGodutiCtrl: _isEditing ? _rolGodutiCtrl : null,
                              rolResiduiCtrl:
                                  _isEditing ? _rolResiduiCtrl : null,
                              exFestivitaMaturateCtrl:
                                  _isEditing ? _exFestivitaMaturateCtrl : null,
                              exFestivitaGoduteCtrl:
                                  _isEditing ? _exFestivitaGoduteCtrl : null,
                              exFestivitaResidueCtrl:
                                  _isEditing ? _exFestivitaResidueCtrl : null,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            BustaPagaStatRow(items: [
                              (
                                'Ore lavorate',
                                _isEditing
                                    ? inlineNumberField(
                                        _oreLavorateCtrl,
                                        style: AppTextStyles.pulseDisplaySmall,
                                      )
                                    : Text(formatNumber(corrente.oreLavorate),
                                        textAlign: TextAlign.center),
                              ),
                              (
                                'Straordinari',
                                Text(
                                  '${formatNumber(_isEditing ? _valoriDerivatiEditing(corrente).straordinari : corrente.straordinari)} h',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ]),
                            const SizedBox(height: AppSpacing.lg),
                            BustaPagaCompetenzeSection(
                              isEditing: _isEditing,
                              competenze: corrente.competenze,
                              righeEdit: _isEditing ? _competenzeEdit : null,
                              onAggiungi: _isEditing ? _addCompetenza : null,
                              onRimuovi: _isEditing ? _removeCompetenza : null,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            _trattenuteSection(
                              context,
                              footer: _isEditing
                                  ? 'Aggiungi le voci di trattenuta indicate in busta '
                                      'paga (es. INPS, IRPEF).'
                                  : null,
                              rows: _isEditing
                                  ? [
                                      for (var i = 0;
                                          i < _trattenuteEdit.length;
                                          i++)
                                        trattenutaEditRow(
                                          _trattenuteEdit[i],
                                          onDismissed: () =>
                                              _removeTrattenuta(i),
                                        ),
                                      _aggiungiVoceButton(context),
                                    ]
                                  : corrente.trattenute.isEmpty
                                      ? [
                                          trattenutaReadOnlyRow(
                                              'Nessuna trattenuta', '—')
                                        ]
                                      : corrente.trattenute.entries
                                          .map((e) => trattenutaReadOnlyRow(
                                              e.key, formatTrattenuta(e.value)))
                                          .toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: AppSpacing.screenHorizontal,
              right: AppSpacing.screenHorizontal,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: StationaryPushBar(
                    child: _ActionBar(
                      bustaPaga: corrente,
                      isEditing: _isEditing,
                      onConferma: () async {
                        try {
                          await ref
                              .read(busteRepositoryProvider.notifier)
                              .update(
                                corrente.copyWith(
                                  statoVerifica:
                                      StatoVerificaBustaPaga.confermato,
                                ),
                              );
                        } catch (_) {
                          if (!context.mounted) return;
                          _showAlert(
                            'Salvataggio non riuscito',
                            'Impossibile confermare i dati, riprova.',
                          );
                          return;
                        }
                        if (!context.mounted) return;
                        showAppAlertDialog<void>(
                          context: context,
                          title: 'Dati confermati',
                          actions: [
                            AppAlertAction(
                              pulseGlyph: PulseIconGlyph.checkmark,
                              label: 'OK',
                              color: CupertinoDynamicColor.resolve(
                                  AppColors.pulseAccent, context),
                              onPressed: () => Navigator.of(context)
                                  .popUntil((route) => route.isFirst),
                            ),
                          ],
                        );
                      },
                      onModifica: () => _enterEditing(corrente),
                      onSalva: () => _save(corrente),
                      onAnnulla: _cancelEditing,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sezione "Trattenute": header testuale + card `PulseSectionCard`
  /// condivisa (stesso impianto di
  /// `BustaPagaCompetenzeSection`/`BustaPagaMaturazioniSection`). L'header
  /// segue lo stesso pattern di `_WarningsSection` in
  /// `busta_paga_form_screen.dart` ("Da verificare"): senza un'intestazione
  /// propria la card risultava visivamente ambigua, come se continuasse la
  /// card Competenze sopra invece di essere una sezione distinta.
  Widget _trattenuteSection(
    BuildContext context, {
    required List<Widget> rows,
    String? footer,
  }) {
    final textSecondary =
        CupertinoDynamicColor.resolve(AppColors.pulseTextSecondary, context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.md,
            bottom: AppSpacing.xs,
          ),
          child: Text(
            'Trattenute',
            style: AppTextStyles.pulseLabel.copyWith(color: textSecondary),
          ),
        ),
        PulseSectionCard(rows: rows, footer: footer),
      ],
    );
  }

  Widget _aggiungiVoceButton(BuildContext context) {
    final accent =
        CupertinoDynamicColor.resolve(AppColors.pulseAccent, context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: SpringButton(
        onPressed: _addTrattenuta,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PulseIcon(glyph: PulseIconGlyph.add, color: accent, size: 18),
            const SizedBox(width: AppSpacing.xs),
            Text('Aggiungi voce',
                style: AppTextStyles.pulseBodyEmphasis.copyWith(color: accent)),
          ],
        ),
      ),
    );
  }
}

/// Barra flottante in basso: chip piatti senza superficie di vetro attorno
/// (nessun "pill" bianco dietro), stesso trattamento del "+" nella sidecar
/// (`_BustePagaSidecar`). Tre stati:
/// - non in modifica + "Da confermare": Conferma (verde, 70%) + Modifica
///   (blu, 30%);
/// - non in modifica + "Confermato": solo Modifica (blu, intera larghezza);
/// - in modifica: Salva (blu, 50%) + Annulla (grigio, 50%).
class _ActionBar extends StatelessWidget {
  final BustaPaga bustaPaga;
  final bool isEditing;
  final VoidCallback onConferma;
  final VoidCallback onModifica;
  final VoidCallback onSalva;
  final VoidCallback onAnnulla;

  const _ActionBar({
    required this.bustaPaga,
    required this.isEditing,
    required this.onConferma,
    required this.onModifica,
    required this.onSalva,
    required this.onAnnulla,
  });

  @override
  Widget build(BuildContext context) {
    final accent =
        CupertinoDynamicColor.resolve(AppColors.pulseAccent, context);
    final greenAccent =
        CupertinoDynamicColor.resolve(AppColors.pulsePositive, context);
    final secondaryAccent =
        CupertinoDynamicColor.resolve(AppColors.pulseTextSecondary, context);

    // Ogni chip porta il proprio sfondo sfocato "chrome", clippato con gli
    // STESSI bound del chip che gli sta sopra (entrambi figli dello stesso
    // `Expanded`): niente più un unico sfondo rettangolare condiviso dietro
    // l'intera `Row`, che lasciava scoperti — e quindi visibili come una
    // rima/ombra scura — i quattro angoli arrotondati di OGNI chip. Tutti e 4
    // gli angoli di ciascun chip sono arrotondati (nessun raggio parziale):
    // i due chip restano forme indipendenti, separate da un gap centrale
    // vuoto (nessuno sfondo) che lascia vedere il contenuto sottostante — è
    // il comportamento voluto, conferma visivamente che sono due chip
    // distinti. Vedi `_floatingBarBackground` più sotto.
    Widget slot(
      Widget chip, {
      BorderRadius borderRadius = const BorderRadius.all(
        Radius.circular(AppRadius.glassSmall),
      ),
    }) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            Positioned.fill(child: _floatingBarBackground(context)),
            chip,
          ],
        ),
      );
    }

    // Spazio vuoto reale tra i due chip: lascia vedere il contenuto
    // sottostante, così i due chip restano visivamente separati invece di
    // sembrare un'unica barra cucita.
    const gap = SizedBox(width: AppSpacing.sm);

    final Widget content;
    if (isEditing) {
      content = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: slot(
                FlatChipButton(
                  pulseGlyph: PulseIconGlyph.checkmark,
                  label: 'Salva',
                  color: accent,
                  primary: true,
                  onPressed: onSalva,
                ),
              ),
            ),
            gap,
            Expanded(
              child: slot(
                FlatChipButton(
                  pulseGlyph: PulseIconGlyph.close,
                  label: 'Annulla',
                  color: secondaryAccent,
                  onPressed: onAnnulla,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      final daConfermare =
          bustaPaga.statoVerifica == StatoVerificaBustaPaga.daConfermare;

      content = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (daConfermare) ...[
              Expanded(
                flex: 7,
                child: slot(
                  FlatChipButton(
                    pulseGlyph: PulseIconGlyph.checkmark,
                    label: 'Conferma',
                    color: greenAccent,
                    onColor: AppColors.pulseOnPositive,
                    primary: true,
                    onPressed: onConferma,
                  ),
                ),
              ),
              gap,
              Expanded(
                flex: 3,
                child: slot(
                  FlatChipButton(
                    pulseGlyph: PulseIconGlyph.edit,
                    label: 'Modifica',
                    color: accent,
                    primary: true,
                    onPressed: onModifica,
                  ),
                ),
              ),
            ] else
              Expanded(
                child: slot(
                  FlatChipButton(
                    pulseGlyph: PulseIconGlyph.edit,
                    label: 'Modifica',
                    color: accent,
                    primary: true,
                    onPressed: onModifica,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return content;
  }
}

/// Sfondo "chrome" piatto dietro ogni chip della barra flottante
/// "Conferma/Modifica"/"Salva/Annulla": riempimento a tinta piena
/// `AppColors.pulseSurface` (stesso token delle superfici `PulseSurface`),
/// niente `BackdropFilter`/blur — coerente con lo stile "Pulse" (vedi
/// CLAUDE.md, sezione "Stile visivo": "nessun `BackdropFilter`/blur in
/// nessuna superficie"). Sostituisce il blur ereditato dal redesign Liquid
/// Glass precedente, rimasto per svista durante la migrazione a Pulse (nessun
/// bug di rendering Impeller documentato per questo punto specifico). Il
/// clip arrotondato che allinea questo sfondo al chip sovrastante è
/// applicato dal chiamante (`ClipRRect` in `_ActionBar.slot`), non qui, per
/// garantire che sfondo e chip condividano esattamente lo stesso raggio e gli
/// stessi bound.
Widget _floatingBarBackground(BuildContext context) {
  final fill =
      CupertinoDynamicColor.resolve(AppColors.pulseSurface, context);
  return DecoratedBox(decoration: BoxDecoration(color: fill));
}
