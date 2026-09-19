import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/busta_paga.dart';
import '../../providers/buste_paga_provider.dart';
import '../../services/busta_paga_regex_parser.dart';
import '../../services/pdf_import_service.dart';
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

/// Altezza riservata alla barra flottante "Salva/Annulla" in basso, usata
/// come padding ESTERNO che riduce il viewport scrollabile (non contentPadding
/// interno) perché l'ultima card non finisca nascosta/tappabile dietro di
/// essa e perché la dissolvenza (`ShaderMask` in `build()`) coincida con le
/// ultime righe davvero visibili sopra la barra — stesso ruolo di
/// `_sidecarReservedHeight` in `buste_paga_section_screen.dart` e stesso
/// valore/motivazione di `_actionBarReservedHeight` in
/// `busta_paga_detail_screen.dart`.
const double _actionBarReservedHeight = 80;

/// Form di revisione di un nuovo import PDF già processato a monte: i campi
/// sono precompilati dal parser regex ([estratti], con [fileOrigine] il path
/// del PDF già copiato) e restano editabili prima della conferma esplicita
/// (bottone "Salva" nella barra flottante in basso). Stesso impianto visivo
/// del dettaglio busta paga in modifica (`BustaPagaDetailScreen`): hero
/// card, riga di statistiche a scomparti, tabella unica Maturazioni, chip
/// documento (qui non tappabile: il file è ancora in fase di revisione),
/// trattenute con swipe-to-delete.
///
/// La modifica di una busta paga già esistente non passa più da qui: dal
/// dettaglio è ora inline nella stessa pagina, senza navigazione verso un
/// form separato. Non esiste più nemmeno una modalità "vuota" per
/// inserimento manuale libero: il PDF viene sempre scelto e processato
/// prima di arrivare qui (vedi `buste_paga_section_screen.dart` / CLAUDE.md).
class BustaPagaFormScreen extends ConsumerStatefulWidget {
  final String fileOrigine;
  final BustaPagaEstratti estratti;

  const BustaPagaFormScreen.daImport({
    super.key,
    required this.fileOrigine,
    required this.estratti,
  });

  @override
  ConsumerState<BustaPagaFormScreen> createState() =>
      _BustaPagaFormScreenState();
}

class _BustaPagaFormScreenState extends ConsumerState<BustaPagaFormScreen> {
  late DateTime _periodo;
  late TipoBustaPaga _tipo;

  /// True quando lordo/trattenute sono stati letti dal percorso a
  /// coordinate del PDF e verificati aritmeticamente contro i totali
  /// stampati (`BustaPagaEstratti.lordoVerificato`/`trattenuteVerificate`,
  /// vedi `busta_paga_regex_parser.dart`): in tal caso le rispettive
  /// sezioni restano in sola lettura invece di editabili, per non
  /// permettere modifiche a dati già verificati.
  late final bool _lordoVerificato;
  late final bool _trattenuteVerificate;

  late final TextEditingController _ferieMaturateController;
  late final TextEditingController _ferieGoduteController;
  late final TextEditingController _ferieResidueController;

  late final TextEditingController _rolMaturatiController;
  late final TextEditingController _rolGodutiController;
  late final TextEditingController _rolResiduiController;

  late final TextEditingController _oreLavorateController;

  late final TextEditingController _exFestivitaMaturateController;
  late final TextEditingController _exFestivitaGoduteController;
  late final TextEditingController _exFestivitaResidueController;

  // Nessun campo di editing collegato (sezioni UI rimosse perché ridondanti/
  // mai popolate, vedi CLAUDE.md): valori portati staticamente dal parser
  // fino al salvataggio, senza `TextEditingController` fantasma.
  late double _permessiGoduti;
  late double _permessiGodutiMese;

  late List<TrattenutaEditRow> _trattenute;
  late List<VoceCompetenzaEditRow> _competenze;

  late final String _fileOrigine;
  late final List<String> _warnings;

  /// True quando i campi sono stati popolati dall'estrazione automatica e
  /// non ancora confermati esplicitamente (salvataggio) dall'utente.
  bool _valoriDaConferma = false;

  /// `true` quando il periodo è stato riconosciuto dal parser, OPPURE
  /// l'utente lo ha confermato esplicitamente tramite `_pickPeriodo()`.
  /// `false` blocca `_save()`.
  bool _periodoConfermato = true;

  final _pdfImportService = const PdfImportService();

  /// True dopo un salvataggio riuscito (`_save`): controlla sia il guard di
  /// rientranza su "Salva"/"Annulla" durante il salvataggio, sia — insieme a
  /// [_saved] — la pulizia del PDF quando la schermata viene chiusa (vedi
  /// `PopScope` in `build`).
  bool _saving = false;

  /// True dopo un salvataggio riuscito: il PDF in `_fileOrigine` è ormai
  /// associato a una busta paga salvata e NON va mai cancellato all'uscita
  /// dalla schermata. Se la schermata viene chiusa (bottone "Annulla", back
  /// chevron della nav bar, swipe-back iOS) con questo flag ancora `false`
  /// (nessun salvataggio riuscito, incluso il caso in cui l'utente abbandona
  /// dopo un rifiuto per duplicato al salvataggio), il PDF copiato in
  /// `buste_paga_pdf/` da `PdfImportService.pickAndImport()` prima ancora di
  /// aprire questo form va invece cancellato: altrimenti resta un file
  /// orfano su disco, mai più referenziato da nessuna busta paga (vedi
  /// CLAUDE.md/istruzioni task). Centralizzare la pulizia in un unico posto
  /// (`PopScope.onPopInvokedWithResult`, che si attiva per QUALUNQUE modo di
  /// uscire dalla schermata) invece di cancellare subito dentro il ramo
  /// "duplicato rilevato" è una scelta deliberata: periodo/tipo sono
  /// modificabili nell'hero anche dopo quel rifiuto, quindi l'utente può
  /// correggerli e salvare con successo riusando lo STESSO file — cancellarlo
  /// subito lo romperebbe per quel salvataggio successivo.
  bool _saved = false;

  final _scrollController = ScrollController();

  // true finché non si è scrollato fino in fondo alla lista — nasconde la
  // dissolvenza di fondo (ShaderMask) non appena non c'è più altro sotto:
  // stesso meccanismo/motivazione di `_showBottomFade` in
  // `buste_paga_archivio_view.dart`.
  bool _showBottomFade = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateBottomFade);
    final estratti = widget.estratti;
    _lordoVerificato = estratti.lordoVerificato;
    _trattenuteVerificate = estratti.trattenuteVerificate;

    _fileOrigine = widget.fileOrigine;
    _valoriDaConferma = true;

    // Il picker mese/anno dell'hero (`CupertinoDatePicker.monthYear`)
    // richiede sempre una data concreta: se il parser non ha riconosciuto il
    // periodo dal PDF (`estratti.periodo == null`), qui si precompila sul
    // mese corrente solo come valore di partenza per il picker, MAI come
    // dato affidabile. Senza un avviso esplicito l'utente rischia di non
    // accorgersi che è un default e salvare in silenzio un periodo sbagliato
    // — e un import successivo per lo stesso mese verrebbe poi rifiutato con
    // un "Hai già una busta paga per ..." incomprensibile (il periodo non fu
    // mai scelto consapevolmente la prima volta). Per rendere il caso
    // esplicito si riusa lo stesso meccanismo già presente per i campi che
    // il parser non riesce a determinare con sufficiente confidenza
    // (`_WarningsSection`, sotto), in cima alla lista perché è il warning più
    // impattante: nessuna modifica al parser regex, il warning è costruito
    // qui in base a `estratti.periodo == null`, non in `estratti.warnings`.
    _periodo = _periodoFromEstratti(estratti.periodo) ??
        DateTime(DateTime.now().year, DateTime.now().month);
    _tipo = estratti.tipo;
    _periodoConfermato = estratti.periodo != null;

    _warnings = [
      if (estratti.periodo == null)
        'Periodo non riconosciuto automaticamente: scegli il mese e '
            'l\'anno corretti toccando il periodo qui sopra — non potrai '
            'salvare finché non lo confermi.',
      ...estratti.warnings,
    ];

    // Se il periodo non è stato riconosciuto, forza subito l'utente a
    // sceglierlo aprendo il picker al primo frame — one-shot dedicato,
    // separato da `_updateBottomFade` (che gira a ogni frame/build).
    if (!_periodoConfermato) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _periodoConfermato) return;
        _pickPeriodo();
      });
    }

    _ferieMaturateController =
        TextEditingController(text: formatNumber(estratti.ferieMaturate));
    _ferieGoduteController =
        TextEditingController(text: formatNumber(estratti.ferieGodute));
    _ferieResidueController =
        TextEditingController(text: formatNumber(estratti.ferieResidue));

    _rolMaturatiController =
        TextEditingController(text: formatNumber(estratti.rolMaturati));
    _rolGodutiController =
        TextEditingController(text: formatNumber(estratti.rolGoduti));
    _rolResiduiController =
        TextEditingController(text: formatNumber(estratti.rolResidui));

    _permessiGoduti = estratti.permessiGoduti;
    _permessiGodutiMese = estratti.permessiGodutiMese;
    _oreLavorateController = TextEditingController(
        text: estratti.oreLavorate == null
            ? ''
            : formatNumber(estratti.oreLavorate!));

    _exFestivitaMaturateController =
        TextEditingController(text: formatNumber(estratti.exFestivitaMaturate));
    _exFestivitaGoduteController =
        TextEditingController(text: formatNumber(estratti.exFestivitaGodute));
    _exFestivitaResidueController =
        TextEditingController(text: formatNumber(estratti.exFestivitaResidue));

    final trattenuteIniziali = estratti.trattenute;
    _trattenute = trattenuteIniziali.isEmpty
        ? [TrattenutaEditRow()]
        : trattenuteIniziali.entries
            .map((e) => TrattenutaEditRow(chiave: e.key, importo: e.value))
            .toList();
    for (final row in _trattenute) {
      _attachTrattenutaListeners(row);
    }

    final competenzeIniziali = estratti.competenze;
    _competenze = competenzeIniziali.isEmpty
        ? [VoceCompetenzaEditRow()]
        : competenzeIniziali
            .map((v) => VoceCompetenzaEditRow(
                  descrizione: v.descrizione,
                  // Vuoto (non "0") quando la quantità è ASSENTE, stessa
                  // convenzione già in uso per `importo == 0` subito sotto —
                  // vedi `VoceCompetenzaEditRow.quantitaValue`.
                  quantita: v.quantita == null ? '' : formatNumber(v.quantita!),
                  importo: v.importo == 0 ? '' : formatEuro(v.importo),
                ))
            .toList();
    for (final row in _competenze) {
      _attachCompetenzaListeners(row);
    }
  }

  void _onResiduiChanged() => setState(() {});

  void _updateBottomFade() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final showFade = position.pixels < position.maxScrollExtent - 1;
    if (showFade != _showBottomFade) {
      setState(() => _showBottomFade = showFade);
    }
  }

  /// Il mese è validato nell'intervallo 1-12, stessa motivazione di
  /// `_periodoDaStringa` in `buste_paga_section_screen.dart` (da cui questa
  /// funzione è duplicata deliberatamente, vedi CLAUDE.md): senza questo
  /// controllo `DateTime(anno, mese)` normalizza silenziosamente un mese 0/13
  /// nel mese adiacente dell'anno prima/dopo invece di far scattare il
  /// fallback "periodo non riconosciuto" già previsto sotto in [initState].
  static DateTime? _periodoFromEstratti(String? periodo) {
    if (periodo == null) return null;
    final parti = periodo.split('-');
    final anno = int.tryParse(parti.elementAtOrNull(0) ?? '');
    final mese = int.tryParse(parti.elementAtOrNull(1) ?? '');
    if (anno == null || mese == null) return null;
    if (mese < 1 || mese > 12) return null;
    return DateTime(anno, mese);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateBottomFade);
    _scrollController.dispose();
    _ferieMaturateController.dispose();
    _ferieGoduteController.dispose();
    _ferieResidueController.dispose();
    _rolMaturatiController.dispose();
    _rolGodutiController.dispose();
    _rolResiduiController.dispose();
    _oreLavorateController.dispose();
    _exFestivitaMaturateController.dispose();
    _exFestivitaGoduteController.dispose();
    _exFestivitaResidueController.dispose();
    for (final row in _trattenute) {
      row.dispose();
    }
    for (final row in _competenze) {
      row.dispose();
    }
    super.dispose();
  }

  double _parse(TextEditingController controller) =>
      parseItalianNumber(controller.text);

  String get _periodoLabel => periodoDisplayFor(periodo: _periodo, tipo: _tipo);

  static const _tipoLabels = {
    TipoBustaPaga.mensile: 'Mensile',
    TipoBustaPaga.tredicesima: '13esima',
    TipoBustaPaga.quattordicesima: '14esima',
  };

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
    if (scelta != null) setState(() => _tipo = scelta);
  }

  Future<void> _pickPeriodo() async {
    DateTime tempSelection = _periodo;
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
                            setState(() {
                              _periodo = tempSelection;
                              _periodoConfermato = true;
                            });
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
                        initialDateTime: _periodo,
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

  /// Rebuild forzato ogni volta che l'importo di una trattenuta cambia, così
  /// il Netto mostrato in hero (derivato da Lordo - trattenute) resta
  /// sincronizzato live — stesso meccanismo di `_attachCompetenzaListeners`.
  void _attachTrattenutaListeners(TrattenutaEditRow row) {
    row.importo.addListener(_onResiduiChanged);
  }

  /// Mappa trattenute correnti da `_trattenute`, filtrando le righe con
  /// chiave vuota — stesso filtro già usato al salvataggio (`_save`), estratto
  /// qui perché riusato anche per il Netto mostrato live in `build`.
  Map<String, double> get _trattenuteCorrenti {
    final trattenute = <String, double>{};
    for (final row in _trattenute) {
      final chiave = row.chiave.text.trim();
      if (chiave.isEmpty) continue;
      trattenute[chiave] = row.valoreConSegno;
    }
    return trattenute;
  }

  void _addTrattenuta() {
    setState(() {
      final row = TrattenutaEditRow();
      _attachTrattenutaListeners(row);
      _trattenute.add(row);
    });
  }

  void _removeTrattenuta(int index) {
    setState(() {
      _trattenute[index].dispose();
      _trattenute.removeAt(index);
    });
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

  void _addCompetenza() {
    setState(() {
      final row = VoceCompetenzaEditRow();
      _attachCompetenzaListeners(row);
      _competenze.add(row);
    });
  }

  void _removeCompetenza(int index) {
    setState(() {
      _competenze[index].dispose();
      _competenze.removeAt(index);
    });
  }

  List<VoceCompetenza> get _competenzeCorrenti => _competenze
      .where((row) => row.descrizione.text.trim().isNotEmpty)
      .map((row) => VoceCompetenza(
            descrizione: row.descrizione.text.trim(),
            quantita: row.quantitaValue,
            importo: row.importoValue,
          ))
      .toList();

  /// Coppie etichetta/testo dei campi numerici "semplici" (non di
  /// competenze/trattenute, validate a parte) da controllare al salvataggio —
  /// vedi [firstInvalidNumericFieldLabel].
  List<(String, String)> get _campiNumericiSemplici => [
        ('Ore lavorate', _oreLavorateController.text),
        ('Ferie (Maturato)', _ferieMaturateController.text),
        ('Ferie (Goduto)', _ferieGoduteController.text),
        ('Ferie (Residuo)', _ferieResidueController.text),
        ('Permessi (Maturato)', _rolMaturatiController.text),
        ('Permessi (Goduto)', _rolGodutiController.text),
        ('Permessi (Residuo)', _rolResiduiController.text),
        ('Ex festività (Maturato)', _exFestivitaMaturateController.text),
        ('Ex festività (Goduto)', _exFestivitaGoduteController.text),
        ('Ex festività (Residuo)', _exFestivitaResidueController.text),
      ];

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

  Future<void> _save() async {
    // Guard di rientranza: `SpringButton` invoca `onPressed` a ogni
    // `onTapUp`, e senza questo guard un doppio tap sul chip "Salva" innesca
    // due `_save()` sovrapposte — la seconda, partita mentre la prima è
    // ancora in attesa dell'insert Drift, rilegge lo stato del repository
    // PRIMA che l'insert della prima sia arrivato al DB ma DOPO che
    // `add()` lo ha già aggiunto otticamente a `state` (vedi
    // `BustePagaNotifier.add`), quindi trova la busta appena inserita e la
    // segnala come duplicato — un falso "Busta paga già presente" per un
    // import che in realtà è già riuscito. Il bottone "Salva"/"Annulla" in
    // `build` resta disattivo (no-op) finché `_saving` è vero — bug reale
    // corretto qui, non un'ipotesi.
    if (_saving) return;
    setState(() => _saving = true);

    if (!_periodoConfermato) {
      setState(() => _saving = false);
      _showAlert(
        'Periodo da confermare',
        'Scegli il mese e l\'anno corretti toccando il periodo in alto '
            'prima di salvare.',
      );
      return;
    }

    // Validazione "livello 2" (rete di sicurezza oltre agli `inputFormatters`
    // di `inlineNumberField`), stesso controllo del dettaglio
    // (`busta_paga_detail_screen.dart._save`): blocca il salvataggio se un
    // qualunque campo numerico contiene testo non valido, invece di
    // procedere in silenzio con un valore azzerato/gonfiato — bug reale
    // corretto qui, non un'ipotesi (vedi CLAUDE.md/istruzioni task).
    final campoNonValido = firstInvalidNumericFieldLabel(
      campi: _campiNumericiSemplici,
      competenze: _competenze,
      trattenute: _trattenute,
    );
    if (campoNonValido != null) {
      setState(() => _saving = false);
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
    final chiaveDuplicata = firstDuplicateTrattenutaKey(_trattenute);
    if (chiaveDuplicata != null) {
      setState(() => _saving = false);
      _showAlert(
        'Trattenuta duplicata',
        'Hai più voci di trattenuta chiamate "$chiaveDuplicata". '
            'Rinominale o rimuovi quella in più prima di salvare.',
      );
      return;
    }

    // Stesso controllo anti-duplicati già usato dal dettaglio
    // (`busta_paga_detail_screen.dart._save()`): per le mensili anno+mese+
    // tipo, per 13esima/14esima solo anno+tipo. Qui è sempre un nuovo
    // inserimento, nessuna esclusione per id necessaria — spostato qui
    // (invece che nel pre-import) perché l'utente possa correggere prima il
    // tipo/periodo se il parser li ha dedotti male.
    final conflitto = ref.read(busteRepositoryProvider).any((b) {
      if (b.tipo != _tipo) return false;
      if (_tipo == TipoBustaPaga.mensile) {
        return b.periodo.year == _periodo.year &&
            b.periodo.month == _periodo.month;
      }
      return b.periodo.year == _periodo.year;
    });
    if (conflitto) {
      setState(() => _saving = false);
      _showAlert(
        'Busta paga già presente',
        'Hai già una busta paga per '
            '${periodoDisplayFor(periodo: _periodo, tipo: _tipo)} '
            'in archivio. Per correggerla, modificala dal dettaglio invece '
            'di reimportarla.',
      );
      return;
    }

    final trattenute = _trattenuteCorrenti;

    // Lordo/straordinari/netto sono derivati dalla lista competenze/
    // trattenute correntemente in editing (vedi
    // computeLordo/computeStraordinari/computeNetto): per un nuovo
    // inserimento, se le liste sono vuote non c'è un "valore precedente" da
    // preservare, quindi restano 0.
    final competenze = _competenzeCorrenti;
    final lordo = computeLordo(competenze);

    final bustaPaga = BustaPaga(
      id: 'bp-${DateTime.now().millisecondsSinceEpoch}',
      periodo: _periodo,
      fileOrigine: _fileOrigine,
      lordo: lordo,
      netto: computeNetto(lordo, trattenute),
      trattenute: trattenute,
      straordinari: computeStraordinari(competenze),
      ferieMaturate: _parse(_ferieMaturateController),
      ferieGodute: _parse(_ferieGoduteController),
      ferieResidue: _parse(_ferieResidueController),
      rolMaturati: _parse(_rolMaturatiController),
      rolGoduti: _parse(_rolGodutiController),
      rolResidui: _parse(_rolResiduiController),
      permessiGoduti: _permessiGoduti,
      permessiGodutiMese: _permessiGodutiMese,
      exFestivitaMaturate: _parse(_exFestivitaMaturateController),
      exFestivitaGodute: _parse(_exFestivitaGoduteController),
      exFestivitaResidue: _parse(_exFestivitaResidueController),
      oreLavorate: _parse(_oreLavorateController),
      competenze: competenze,
      tipo: _tipo,
      layout: widget.estratti.layoutId,
      statoVerifica: _valoriDaConferma
          ? StatoVerificaBustaPaga.daConfermare
          : StatoVerificaBustaPaga.confermato,
    );

    try {
      await ref.read(busteRepositoryProvider.notifier).add(bustaPaga);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showAlert(
        'Salvataggio non riuscito',
        'Impossibile salvare la busta paga, riprova.',
      );
      return;
    }
    if (!mounted) return;
    // Il PDF in `_fileOrigine` è ora associato alla busta paga appena
    // salvata: `PopScope` (vedi `build`) non deve cancellarlo all'uscita.
    _saved = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final accent =
        CupertinoDynamicColor.resolve(AppColors.pulseAccent, context);
    final secondaryAccent =
        CupertinoDynamicColor.resolve(AppColors.pulseTextSecondary, context);

    // Fill leggermente trasparente (stesso token `pulseBackground` dello
    // sfondo piatto della schermata, vedi `_pinnedBackground`) per il
    // "chrome" della nav bar sopra il contenuto scrollabile sottostante.
    final navBarBackground =
        CupertinoDynamicColor.resolve(AppColors.pulseBackground, context)
            .withValues(alpha: 0.55);

    final saveEnabled = !_saving && _periodoConfermato;

    // Ricontrolla dopo ogni layout (non solo sullo scroll dell'utente): il
    // contenuto del form può cambiare (aggiunta/rimozione trattenute) e con
    // esso può cambiare se c'è ancora altro da scorrere sotto — stesso
    // pattern di `BustePagaArchivioView.build()`.
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateBottomFade());

    return PopScope(
      // Bloccato mentre un salvataggio è in corso (`_saving`): stessa
      // finestra di rientranza protetta su "Salva"/"Annulla" sotto, chiude
      // anche l'uscita dalla schermata (back chevron della nav bar,
      // swipe-back iOS) durante quella breve finestra.
      canPop: !_saving,
      onPopInvokedWithResult: (didPop, result) {
        // `onPopInvokedWithResult` si attiva per QUALUNQUE modo in cui la
        // schermata viene chiusa — bottone "Annulla" (`Navigator.pop()`
        // esplicito sotto), back chevron automatico della nav bar, swipe-back
        // iOS — non solo il gesto di sistema (a differenza del vecchio
        // `WillPopScope`, un `Navigator.pop()` diretto notifica comunque
        // questo callback). Unico punto centralizzato di pulizia del PDF
        // orfano, vedi doc di [_saved].
        if (didPop && !_saved) {
          _pdfImportService.deleteFile(_fileOrigine);
        }
      },
      child: ColoredBox(
        color: CupertinoDynamicColor.resolve(AppColors.pulseBackground, context),
        child: CupertinoPageScaffold(
          backgroundColor: CupertinoColors.transparent,
          navigationBar: CupertinoNavigationBar(
            middle: const Text('Nuova busta paga'),
            backgroundColor: navBarBackground,
            border: null,
          ),
          child: Stack(
            children: [
              Padding(
                padding:
                    const EdgeInsets.only(bottom: _actionBarReservedHeight),
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) {
                    final fadeHeight = _showBottomFade ? 120.0 : 0.0;
                    final stop = 1 - (fadeHeight / rect.height).clamp(0.0, 1.0);
                    return LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: const [
                        CupertinoColors.white,
                        CupertinoColors.white,
                        CupertinoColors.transparent,
                      ],
                      stops: [0.0, stop, 1.0],
                    ).createShader(rect);
                  },
                  child: SafeArea(
                    child: ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenHorizontal,
                        AppSpacing.sm,
                        AppSpacing.screenHorizontal,
                        AppSpacing.sm,
                      ),
                      children: [
                        if (_valoriDaConferma) ...[
                          const _EstrazioneAutomaticaBanner(),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                        BustaPagaHeroCard(
                          isConfermato: false,
                          periodoLabel: _periodoLabel,
                          lordoDisplay: formatEuroConSegno(
                              computeLordo(_competenzeCorrenti)),
                          nettoDisplay: formatEuroConSegno(computeNetto(
                            computeLordo(_competenzeCorrenti),
                            _trattenuteCorrenti,
                          )),
                          onTapPeriodo: _pickPeriodo,
                          onTapTipo: _pickTipo,
                        ),
                        if (_warnings.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.lg),
                          _WarningsSection(warnings: _warnings),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        BustaPagaDocumentoChip(
                          filePath: _fileOrigine,
                          periodo: _periodo,
                          tipo: _tipo,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        BustaPagaMaturazioniSection(
                          isEditing: true,
                          ferieMaturate:
                              formatNumber(_parse(_ferieMaturateController)),
                          ferieGodute:
                              formatNumber(_parse(_ferieGoduteController)),
                          ferieResidue:
                              formatNumber(_parse(_ferieResidueController)),
                          rolMaturati:
                              formatNumber(_parse(_rolMaturatiController)),
                          rolGoduti: formatNumber(_parse(_rolGodutiController)),
                          rolResidui:
                              formatNumber(_parse(_rolResiduiController)),
                          exFestivitaMaturate: formatNumber(
                              _parse(_exFestivitaMaturateController)),
                          exFestivitaGodute: formatNumber(
                              _parse(_exFestivitaGoduteController)),
                          exFestivitaResidue: formatNumber(
                              _parse(_exFestivitaResidueController)),
                          ferieMaturateCtrl: _ferieMaturateController,
                          ferieGoduteCtrl: _ferieGoduteController,
                          ferieResidueCtrl: _ferieResidueController,
                          rolMaturatiCtrl: _rolMaturatiController,
                          rolGodutiCtrl: _rolGodutiController,
                          rolResiduiCtrl: _rolResiduiController,
                          exFestivitaMaturateCtrl:
                              _exFestivitaMaturateController,
                          exFestivitaGoduteCtrl: _exFestivitaGoduteController,
                          exFestivitaResidueCtrl: _exFestivitaResidueController,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        BustaPagaStatRow(items: [
                          (
                            'Ore lavorate',
                            inlineNumberField(
                              _oreLavorateController,
                              style: AppTextStyles.pulseDisplaySmall,
                            ),
                          ),
                          (
                            'Straordinari',
                            Text(
                              '${formatNumber(computeStraordinari(_competenzeCorrenti))} h',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ]),
                        const SizedBox(height: AppSpacing.lg),
                        BustaPagaCompetenzeSection(
                          isEditing: !_lordoVerificato,
                          competenze:
                              _lordoVerificato ? _competenzeCorrenti : const [],
                          righeEdit: _lordoVerificato ? null : _competenze,
                          onAggiungi: _lordoVerificato ? null : _addCompetenza,
                          onRimuovi:
                              _lordoVerificato ? null : _removeCompetenza,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        PulseSectionCard(
                          footer: _trattenuteVerificate
                              ? null
                              : 'Aggiungi le voci di trattenuta indicate in '
                                  'busta paga (es. INPS, IRPEF).',
                          rows: _trattenuteVerificate
                              ? (widget.estratti.trattenute.isEmpty
                                  ? [
                                      trattenutaReadOnlyRow(
                                          'Nessuna trattenuta', '—'),
                                    ]
                                  : [
                                      for (final e
                                          in widget.estratti.trattenute.entries)
                                        trattenutaReadOnlyRow(
                                            e.key, formatTrattenuta(e.value)),
                                    ])
                              : [
                                  for (var i = 0; i < _trattenute.length; i++)
                                    trattenutaEditRow(
                                      _trattenute[i],
                                      onDismissed: () => _removeTrattenuta(i),
                                    ),
                                  _aggiungiVoceButton(accent),
                                ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: AppSpacing.screenHorizontal,
                right: AppSpacing.screenHorizontal,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: StationaryPushBar(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      // Ogni chip porta il proprio sfondo sfocato "chrome",
                      // clippato con gli STESSI bound del chip che gli sta
                      // sopra (entrambi figli dello stesso `Expanded`):
                      // niente più un unico sfondo rettangolare condiviso
                      // dietro l'intera `Row`, che lasciava scoperti — e
                      // quindi visibili come una rima/ombra scura — i quattro
                      // angoli arrotondati di OGNI chip. Tutti e 4 gli
                      // angoli di ciascun chip sono arrotondati: i due chip
                      // restano forme indipendenti, separate da un gap
                      // centrale vuoto (nessuno sfondo) che lascia vedere il
                      // contenuto sottostante — è il comportamento voluto,
                      // conferma visivamente che sono due chip distinti.
                      // Vedi `_floatingBarBackground` più sotto in questo
                      // file.
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: saveEnabled ? 1.0 : 0.45,
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.all(
                                    Radius.circular(AppRadius.glassSmall),
                                  ),
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                          child:
                                              _floatingBarBackground(context)),
                                      FlatChipButton(
                                        pulseGlyph: PulseIconGlyph.checkmark,
                                        label: 'Salva',
                                        color: accent,
                                        primary: true,
                                        // No-op mentre `_saving` è vero o il periodo
                                        // non è ancora stato confermato: stesso guard
                                        // di rientranza di `_save()`, vedi la sua doc,
                                        // più il blocco esplicito su periodo non
                                        // confermato (CLAUDE.md/istruzioni task).
                                        onPressed: saveEnabled ? _save : () {},
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Spazio vuoto reale tra i due chip: lascia
                            // vedere lo sfondo della pagina sottostante,
                            // così i due chip restano visivamente separati
                            // invece di sembrare un'unica barra cucita.
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(AppRadius.glassSmall),
                                ),
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                        child: _floatingBarBackground(context)),
                                    FlatChipButton(
                                      pulseGlyph: PulseIconGlyph.close,
                                      label: 'Annulla',
                                      color: secondaryAccent,
                                      // Stesso guard: uscire mentre un salvataggio è
                                      // in corso, prima che `_saved` diventi vero,
                                      // farebbe cancellare dal `PopScope` sopra un
                                      // PDF ormai associato a un salvataggio riuscito
                                      // (l'insert Drift potrebbe già essere andata a
                                      // buon fine nella finestra tra il tap e questo
                                      // controllo).
                                      onPressed: _saving
                                          ? () {}
                                          : () => Navigator.of(context).pop(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _aggiungiVoceButton(Color accent) {
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

/// Sfondo "chrome" piatto dietro ogni chip della barra flottante
/// "Salva/Annulla": riempimento a tinta piena `AppColors.pulseSurface`
/// (stesso token delle superfici `PulseSurface`), niente
/// `BackdropFilter`/blur — coerente con lo stile "Pulse" (vedi CLAUDE.md,
/// sezione "Stile visivo": "nessun `BackdropFilter`/blur in nessuna
/// superficie"). Sostituisce il blur ereditato dal redesign Liquid Glass
/// precedente, rimasto per svista durante la migrazione a Pulse (nessun bug
/// di rendering Impeller documentato per questo punto specifico). Il clip
/// arrotondato che allinea questo sfondo al chip sovrastante è applicato dal
/// chiamante (`ClipRRect` attorno a ciascuno slot della `Row`), non qui, per
/// garantire che sfondo e chip condividano esattamente lo stesso raggio e
/// gli stessi bound.
Widget _floatingBarBackground(BuildContext context) {
  final fill =
      CupertinoDynamicColor.resolve(AppColors.pulseSurface, context);
  return DecoratedBox(decoration: BoxDecoration(color: fill));
}

/// Banner informativo fisso, sempre visibile mentre `_valoriDaConferma ==
/// true` (indipendentemente dalla presenza di warning specifici del parser
/// in `_WarningsSection` sotto): ricorda che i campi del form sono stati
/// precompilati automaticamente dal parser regex e vanno verificati prima
/// del salvataggio. Tono volutamente neutro/informativo (icona
/// `info_circle` in `pulseAccent`, testo in `pulseTextSecondary`, contenitore
/// `PulseSurface`) per non essere confuso con gli warning puntuali
/// (`systemOrange`) che restano più sotto.
class _EstrazioneAutomaticaBanner extends StatelessWidget {
  const _EstrazioneAutomaticaBanner();

  @override
  Widget build(BuildContext context) {
    final accent =
        CupertinoDynamicColor.resolve(AppColors.pulseAccent, context);
    final textSecondary =
        CupertinoDynamicColor.resolve(AppColors.pulseTextSecondary, context);
    return PulseSurface(
      borderRadius: AppRadius.pulseSmall,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.info_circle, color: accent, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Dati estratti automaticamente, verifica prima di salvare.',
              style: AppTextStyles.pulseBody.copyWith(color: textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sezione sola lettura con i warning del parser regex (campi che non è
/// riuscito a determinare con sufficiente confidenza) — visibile solo
/// nell'import, non ha equivalente nel dettaglio (concetto legato solo
/// all'estrazione automatica da PDF). Colore `systemOrange`, non
/// `systemRed`: quest'ultimo resta riservato agli alert veri (vedi
/// CLAUDE.md).
class _WarningsSection extends StatelessWidget {
  final List<String> warnings;

  const _WarningsSection({required this.warnings});

  @override
  Widget build(BuildContext context) {
    final orange =
        CupertinoDynamicColor.resolve(AppColors.systemOrange, context);
    final textPrimary =
        CupertinoDynamicColor.resolve(AppColors.pulseTextPrimary, context);
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
            'Da verificare',
            style: AppTextStyles.pulseLabel.copyWith(color: textSecondary),
          ),
        ),
        PulseSectionCard(
          rows: [
            for (final warning in warnings)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(CupertinoIcons.exclamationmark_triangle,
                        color: orange, size: 18),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        warning,
                        style: AppTextStyles.pulseBody
                            .copyWith(color: textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
