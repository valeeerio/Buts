import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show ValueListenable, debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/busta_paga.dart';
import '../../providers/buste_paga_provider.dart';
import '../../providers/home_widget_provider.dart';
import '../../providers/reminder_scheduler_provider.dart';
import '../../services/busta_paga_regex_parser.dart';
import '../../services/home_widget_launch.dart';
import '../../services/pdf_import_service.dart';
import '../../services/reminder_notifications.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/busta_paga_formatting.dart';
import '../../widgets/app_alert_dialog.dart';
import '../../widgets/custom_illustration.dart';
import '../../widgets/period_filter_button.dart';
import '../../widgets/pulse_icon.dart';
import '../../widgets/pulse_surface.dart';
import '../../widgets/spring_button.dart';
import 'busta_paga_detail_screen.dart';
import 'busta_paga_form_screen.dart';
import 'buste_paga_archivio_view.dart';
import 'buste_paga_statistiche_screen.dart';

/// Sotto-navigazione interna alla sezione Buste Paga (unica sezione
/// dell'app, non c'è una navigazione radice).
enum _BustePagaTab { archivio, statistiche }

/// Saluto dinamico in base all'ora corrente. Funzione pura per testabilità
/// (vedi piano sessione "barra di benvenuto dinamica").
String greetingFor(DateTime now) {
  final hour = now.hour;
  if (hour >= 5 && hour < 13) return 'Buongiorno Valerio';
  if (hour >= 13 && hour < 18) return 'Buon pomeriggio Valerio';
  return 'Buonasera Valerio';
}

/// Altezza approssimativa riservata alla sidecar flottante in basso
/// (barra + margini), da sottrarre al contenuto scrollabile sottostante
/// perché non finisca nascosto dietro di essa.
const double _sidecarReservedHeight = 96;

/// Schermata radice dell'app: barra di benvenuto, titolo di sezione,
/// contenuto Archivio/Statistiche e sidecar flottante in basso con la
/// sotto-navigazione e la CTA "+" (import PDF).
class BustePagaSectionScreen extends ConsumerStatefulWidget {
  const BustePagaSectionScreen({super.key, this.avvioCompletato});

  /// Se presente e `false`, onboarding promemoria e richieste pendenti
  /// (import/dettaglio da notifica o widget) attendono che diventi `true`
  /// (fine animazione di avvio). `null` = nessuna attesa.
  final ValueListenable<bool>? avvioCompletato;

  @override
  ConsumerState<BustePagaSectionScreen> createState() =>
      _BustePagaSectionScreenState();
}

class _BustePagaSectionScreenState extends ConsumerState<BustePagaSectionScreen>
    with WidgetsBindingObserver {
  _BustePagaTab _tab = _BustePagaTab.archivio;
  // Sincronizza tap sulla nav bar e swipe orizzontale sul corpo pagina: un
  // solo `PageController` guida entrambi. Il tap chiama `_changeTab`, che
  // anima il controller verso la pagina corrispondente; lo swipe manuale
  // dell'utente aggiorna direttamente il controller e `onPageChanged` è
  // l'unico punto che scrive `_tab` — così le due modalità non possono mai
  // disallinearsi (nessuno stato duplicato, `_tab` riflette sempre la pagina
  // effettivamente mostrata, anche a metà di un'animazione indotta dal tap).
  final _pageController = PageController();
  final _pdfImportService = const PdfImportService();
  final _regexParser = const BustaPagaRegexParser();
  bool _importingPdf = false;
  bool _searchActive = false;
  final _searchController = TextEditingController();

  /// Periodo selezionato dallo slider di Statistiche (`null` = nessun
  /// filtro, tutti i periodi disponibili). Vive qui, non in un provider
  /// Riverpod: è stato di UI locale alla sessione, non dato di dominio,
  /// stesso trattamento di `_tab`/`_searchActive`.
  ({DateTime start, DateTime end})? _periodoFiltro;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Copre il tap "a caldo" (app già in esecuzione quando l'utente tocca la
    // notifica): `main()` gestisce già il cold start impostando
    // `pendingImportRequest` PRIMA che questa schermata esista, quindi quel
    // caso è coperto sotto, nello stesso `addPostFrameCallback`.
    pendingImportRequest.addListener(_consumaPendingImportRequestSePresente);
    pendingBustaDetailId.addListener(_consumaPendingBustaDetailIdSePresente);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _attendiAvvioCompletato();
      if (!mounted) return;
      // Prima l'eventuale onboarding (spiega il promemoria all'utente),
      // poi l'eventuale richiesta di import in sospeso: se l'app è stata
      // aperta da un tap su notifica, l'onboarding è già stato completato
      // in una sessione precedente (altrimenti la notifica non sarebbe mai
      // stata schedulata), quindi in pratica non si accavallano mai — ma
      // l'ordine resta comunque quello più sensato se dovesse succedere.
      await _maybeShowReminderOnboarding();
      if (!mounted) return;
      _consumaPendingImportRequestSePresente();
      _consumaPendingBustaDetailIdSePresente();
      // Chiamata iniziale di ri-scheduling: copre sia il caso in cui
      // l'archivio sia già stato caricato dal provider prima di questo primo
      // frame, sia il caso — più delicato — di un archivio genuinamente
      // vuoto, per cui nessun evento di caricamento successivo arriverebbe
      // a correggere una schedulazione mai fatta. Se invece l'archivio sta
      // ancora caricando in modo asincrono (`BustePagaNotifier._initialize`),
      // questa chiamata può operare temporaneamente su una lista vuota: il
      // `ref.listen` più sotto, in `build`, ri-schedula da capo (cancellando
      // prima tutto, vedi `PayslipReminderService.reschedule`) non appena lo
      // stato reale arriva, quindi non lascia promemoria scorretti.
      unawaited(_rescheduleRemindersSafe());
      // Stesso ragionamento per il widget iOS della home screen: allinea lo
      // snapshot allo stato corrente dell'archivio non appena disponibile,
      // senza aspettare la prima mutazione (`ref.listen` più sotto copre
      // solo i cambiamenti successivi).
      unawaited(_updateHomeWidgetSafe());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pendingImportRequest.removeListener(_consumaPendingImportRequestSePresente);
    pendingBustaDetailId
        .removeListener(_consumaPendingBustaDetailIdSePresente);
    _searchController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_rescheduleRemindersSafe());
    }
  }

  /// Wrapper di [_rescheduleReminders] che intercetta qualunque eccezione
  /// invece di lasciarla propagare come errore non gestito — stesso spirito
  /// del try/catch che avvolge già l'intero bootstrap del sistema di
  /// promemoria in `main.dart`. Necessario perché questo metodo viene
  /// sempre invocato tramite `unawaited()` (init, resume, `ref.listen`
  /// sull'archivio): senza gestione esplicita, un guasto dello scheduler
  /// nativo (plugin non disponibile, mismatch di scheduling, ecc.)
  /// diventerebbe un'eccezione non gestita invece di degradare
  /// silenziosamente il solo sottosistema dei promemoria.
  Future<void> _rescheduleRemindersSafe() async {
    try {
      await _rescheduleReminders();
    } catch (error, stackTrace) {
      debugPrint('Reschedule promemoria fallito: $error\n$stackTrace');
    }
  }

  /// Se l'utente ha appena toccato una notifica di promemoria (a caldo,
  /// osservato qui, o a freddo, già impostato da `main()` prima ancora che
  /// questa schermata esistesse), riporta il flag a `false` e avvia
  /// direttamente il flusso di import — stesso identico percorso del "+",
  /// nessuna logica di import duplicata.
  bool get _avvioCompleto => widget.avvioCompletato?.value ?? true;

  Future<void> _attendiAvvioCompletato() {
    final avvio = widget.avvioCompletato;
    if (avvio == null || avvio.value) return Future.value();
    final completer = Completer<void>();
    void listener() {
      if (!avvio.value) return;
      avvio.removeListener(listener);
      completer.complete();
    }

    avvio.addListener(listener);
    return completer.future;
  }

  void _consumaPendingImportRequestSePresente() {
    if (!_avvioCompleto) return;
    if (!pendingImportRequest.value) return;
    pendingImportRequest.value = false;
    _startImport();
  }

  /// Se l'utente ha appena toccato il widget iOS della home screen (a
  /// caldo, osservato qui, o a freddo, già impostato da `main()` prima
  /// ancora che questa schermata esistesse), riporta il notifier a `null` e
  /// apre direttamente il dettaglio della busta paga referenziata — se
  /// esiste ancora in archivio (fallback silenzioso altrimenti: può essere
  /// stata eliminata nel frattempo).
  void _consumaPendingBustaDetailIdSePresente() {
    if (!_avvioCompleto) return;
    final id = pendingBustaDetailId.value;
    if (id == null) return;
    pendingBustaDetailId.value = null;
    final bustaPaga = ref
        .read(busteRepositoryProvider)
        .cast<BustaPaga?>()
        .firstWhere((b) => b?.id == id, orElse: () => null);
    if (bustaPaga == null) return;
    _openDetail(context, bustaPaga);
  }

  Future<void> _rescheduleReminders() async {
    final service = ref.read(payslipReminderServiceProvider);
    if (service == null) return;
    await service.reschedule(ref.read(busteRepositoryProvider));
  }

  /// Wrapper di [HomeWidgetService.aggiorna] che intercetta qualunque
  /// eccezione, stesso spirito di [_rescheduleRemindersSafe]: un guasto nel
  /// canale nativo del widget (App Group non ancora configurato lato Xcode,
  /// piattaforma non disponibile) non deve mai propagarsi come eccezione non
  /// gestita né bloccare l'archivio.
  Future<void> _updateHomeWidgetSafe() async {
    try {
      await ref
          .read(homeWidgetServiceProvider)
          .aggiorna(ref.read(busteRepositoryProvider));
    } catch (error, stackTrace) {
      debugPrint('Aggiornamento widget home fallito: $error\n$stackTrace');
    }
  }

  /// Gancio di debug invisibile in una build di release: attivato dal
  /// long-press sul "+" della sidecar (vedi `_BustePagaSidecar`, wired solo
  /// sotto `kDebugMode` anche lì), schedula la notifica di prova via
  /// `schedulaNotificaDiProvaPerDebug()` e conferma con un alert — senza
  /// questo riscontro, verificare le notifiche su device richiederebbe
  /// aspettare il vero 1°/8°/15° del mese.
  Future<void> _avviaNotificaDiProvaDebug() async {
    if (!kDebugMode) return;
    final service = ref.read(payslipReminderServiceProvider);
    if (service == null) return;
    await service.schedulaNotificaDiProvaPerDebug();
    if (!mounted) return;

    final accent =
        CupertinoDynamicColor.resolve(AppColors.pulseAccent, context);
    await showAppAlertDialog<void>(
      context: context,
      title: 'Notifica di prova',
      message: 'Arriverà tra circa 60 secondi. Metti l\'app in background '
          'per vederla.',
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

  /// Alert esplicativo una-tantum del promemoria mensile, mostrato al primo
  /// frame finché `onboardingDaMostrare` resta `true`. `null` il servizio
  /// (init delle notifiche fallita in `main()`, vedi
  /// `payslipReminderServiceProvider`) significa semplicemente "nessun
  /// promemoria disponibile in questa sessione": nessun alert, nessun
  /// errore.
  Future<void> _maybeShowReminderOnboarding() async {
    final service = ref.read(payslipReminderServiceProvider);
    if (service == null || !service.onboardingDaMostrare) return;
    if (!mounted) return;

    final accent =
        CupertinoDynamicColor.resolve(AppColors.pulseAccent, context);
    final secondary =
        CupertinoDynamicColor.resolve(AppColors.labelSecondary, context);

    await showAppAlertDialog<void>(
      context: context,
      illustration: const CustomIllustration(
        variant: CustomIllustrationVariant.onboardingNotifiche,
        size: 72,
      ),
      title: 'Promemoria busta paga',
      message: 'Il 1° di ogni mese Buts può ricordarti di importare la '
          'busta paga del mese appena concluso, con altri due solleciti '
          'l\'8 e il 15 finché non risulta in archivio. Serve il permesso '
          'di iOS per le notifiche.',
      actions: [
        AppAlertAction(
          icon: CupertinoIcons.bell,
          label: 'Attiva',
          color: accent,
          onPressed: () async {
            Navigator.of(context).pop();
            final concesso = await service.completaOnboarding();
            if (!mounted) return;
            await service.reschedule(ref.read(busteRepositoryProvider));
            if (!concesso && mounted) {
              _showPermessoNotificheNegatoAlert();
            }
          },
        ),
        AppAlertAction(
          icon: CupertinoIcons.bell_slash,
          label: 'Non ora',
          color: secondary,
          onPressed: () {
            Navigator.of(context).pop();
            service.rifiutaOnboarding();
          },
        ),
      ],
    );
  }

  /// Mostrato solo se l'utente ha accettato l'onboarding nell'app ma poi ha
  /// negato il permesso nel prompt di sistema: iOS non lo ripropone mai una
  /// seconda volta, va spiegato che si riattiva da Impostazioni.
  void _showPermessoNotificheNegatoAlert() {
    if (!mounted) return;
    final accent =
        CupertinoDynamicColor.resolve(AppColors.pulseAccent, context);
    showAppAlertDialog<void>(
      context: context,
      title: 'Notifiche disattivate',
      message: 'Il permesso è stato negato: iOS non lo richiede una '
          'seconda volta. Per attivare il promemoria in futuro, vai su '
          'Impostazioni > Buts > Notifiche.',
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

  /// Tap su un tab della nav bar: anima il `PageController` verso la pagina
  /// corrispondente (durata/curva coerenti con `AnimatedContainer` di
  /// `FlatChipButton`, vedi CLAUDE.md). Non scrive `_tab` direttamente —
  /// `_onPageChanged` lo fa già durante l'animazione, unico punto di verità
  /// condiviso con lo swipe manuale.
  void _changeTab(_BustePagaTab tab) {
    _pageController.animateToPage(
      tab.index,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  /// Unico punto che aggiorna `_tab`: chiamato sia da uno swipe manuale
  /// dell'utente sia (indirettamente) da `animateToPage` in `_changeTab`.
  void _onPageChanged(int index) {
    setState(() {
      _tab = _BustePagaTab.values[index];
      if (_tab != _BustePagaTab.archivio) _closeSearch();
    });
  }

  void _closeSearch() {
    _searchActive = false;
    _searchController.clear();
  }

  void _openDetail(BuildContext context, BustaPaga bustaPaga) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => BustaPagaDetailScreen(bustaPaga: bustaPaga),
      ),
    );
  }

  /// CTA "+": avvia direttamente l'import PDF, niente più form vuoto per
  /// inserimento manuale libero (vedi CLAUDE.md / piano sessione).
  ///
  /// Il guard di rientranza (`_importingPdf`) resta attivo per l'intera
  /// durata del flusso — non solo per la selezione del file — dentro un
  /// `try/finally`: senza questo, un tap sul "+" nella finestra tra la
  /// chiusura del file picker e l'apertura effettiva del form (parsing,
  /// controllo anti-duplicati, eventuale rinomina del file) apriva un
  /// secondo file picker sopra il form — bug reale corretto qui, non
  /// un'ipotesi. Il reset in `finally` copre anche i rami d'errore (return
  /// anticipati) e non attende il pop del form: una volta chiamato
  /// `Navigator.push`, il "+" sottostante non è comunque più raggiungibile
  /// (coperto dalla schermata push-ata), quindi riabilitarlo súbito dopo non
  /// crea alcuna finestra di doppio tap aggiuntiva, ed evita che resti
  /// "in caricamento" fino a quando l'utente non chiude il form.
  Future<void> _startImport() async {
    if (_importingPdf) return;
    setState(() => _importingPdf = true);
    try {
      final result = await _pdfImportService.pickAndImport();
      if (!mounted) return;

      switch (result.status) {
        case PdfImportStatus.cancelled:
          return;
        case PdfImportStatus.noExtractableText:
          _showImportError(
            'PDF non supportato',
            'Questo PDF sembra una scansione o un\'immagine, senza testo '
                'selezionabile. In questa versione sono supportati solo PDF '
                'testuali generati da un software paghe.',
          );
          return;
        case PdfImportStatus.error:
          _showImportError(
            'Import non riuscito',
            result.errorMessage ?? 'Si è verificato un errore imprevisto.',
          );
          return;
        case PdfImportStatus.success:
          break;
      }

      final testo = result.extractedText;
      final risultato = testo == null
          ? null
          : _regexParser.parse(testo, result.ratei, result.voci);

      if (risultato == null ||
          (risultato.netto == null && risultato.periodo == null)) {
        // Il file è già stato copiato in `buste_paga_pdf/` da
        // `pickAndImport()` prima ancora di arrivare qui: se il parser non
        // riconosce i dati principali il form non si apre mai, va ripulito
        // qui per non lasciare un PDF orfano su disco (vedi
        // `BustePagaNotifier._sweepPdfOrfani` per la spazzata degli orfani
        // già esistenti da prima di questo fix).
        await _pdfImportService.deleteFile(result.filePath!);
        if (!mounted) return;
        _showImportError(
          'Formato non riconosciuto',
          'Non è stato possibile riconoscere i dati principali in questo '
              'PDF. Prova con un altro file oppure verifica che sia una '
              'busta paga generata dal software paghe supportato.',
        );
        return;
      }

      final periodoEstratto = _periodoDaStringa(risultato.periodo);

      // Controllo anti-duplicati subito dopo la scelta del file, prima di
      // aprire il form di revisione: per le mensili anno+mese+tipo, per
      // 13esima/14esima solo anno+tipo, stesso identico controllo già
      // presente in `BustaPagaFormScreen._save()` (mantenuto lì come difesa
      // in profondità, per il caso in cui l'utente cambi tipo/periodo mentre
      // è già nel form). Il fallback del parser sul tipo (da "Mens.
      // supplementare") rende ora affidabile bloccare qui, prima ancora di
      // aprire il form.
      if (periodoEstratto != null) {
        final conflitto = ref.read(busteRepositoryProvider).any((b) {
          if (b.tipo != risultato.tipo) return false;
          if (risultato.tipo == TipoBustaPaga.mensile) {
            return b.periodo.year == periodoEstratto.year &&
                b.periodo.month == periodoEstratto.month;
          }
          return b.periodo.year == periodoEstratto.year;
        });
        if (conflitto) {
          await _pdfImportService.deleteFile(result.filePath!);
          if (!mounted) return;
          _showImportError(
            'Busta paga già presente',
            'Hai già una busta paga per '
                '${periodoDisplayFor(periodo: periodoEstratto, tipo: risultato.tipo)} '
                'in archivio. Per correggerla, modificala dal dettaglio invece '
                'di reimportarla.',
          );
          return;
        }
      }

      var fileOrigine = result.filePath!;
      if (risultato.tipo != TipoBustaPaga.mensile && periodoEstratto != null) {
        try {
          fileOrigine = await _pdfImportService.rinominaPerSupplementare(
            fileOrigine,
            mese: periodoEstratto.month,
            anno: periodoEstratto.year,
            tipo: risultato.tipo,
          );
        } catch (_) {
          // La rinomina è fallita: `fileOrigine` non è stato riassegnato
          // (l'`await` sopra non è arrivato a completare l'assignment),
          // contiene quindi ancora il path del file copiato da
          // `pickAndImport()` — va ripulito per non lasciare un orfano.
          await _pdfImportService.deleteFile(fileOrigine);
          if (!mounted) return;
          _showImportError(
            'Import non riuscito',
            'Impossibile preparare il file del documento, riprova.',
          );
          return;
        }
      }

      if (!mounted) return;
      Navigator.of(context).push(
        CupertinoPageRoute(
          builder: (_) => BustaPagaFormScreen.daImport(
            fileOrigine: fileOrigine,
            estratti: risultato,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _importingPdf = false);
    }
  }

  /// Sostituisce il titolo "Archivio buste paga" con un campo di ricerca
  /// minimale (nessun bordo/riempimento) quando la lente è attiva: icona
  /// lente come prefix (tappabile per chiudere), campo borderless, tasto
  /// "Annulla" per chiudere in alternativa.
  Widget _buildSearchField(Color textPrimary, Color textSecondary) {
    final accent =
        CupertinoDynamicColor.resolve(AppColors.pulseAccent, context);
    return Row(
      children: [
        Semantics(
          label: 'Chiudi ricerca',
          button: true,
          child: SpringButton(
            onPressed: () => setState(_closeSearch),
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              child: PulseIcon(
                glyph: PulseIconGlyph.search,
                size: 20,
                color: accent,
              ),
            ),
          ),
        ),
        Expanded(
          child: CupertinoTextField.borderless(
            controller: _searchController,
            autofocus: true,
            padding: EdgeInsets.zero,
            placeholder: 'Cerca per mese o anno',
            placeholderStyle: AppTextStyles.pulseBody.copyWith(
              color: textSecondary,
            ),
            style: AppTextStyles.pulseBody.copyWith(color: textPrimary),
            onChanged: (_) => setState(() {}),
          ),
        ),
        SpringButton(
          onPressed: () => setState(_closeSearch),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            height: 44,
            alignment: Alignment.center,
            child: Text(
              'Annulla',
              style: AppTextStyles.pulseBodyEmphasis.copyWith(color: accent),
            ),
          ),
        ),
      ],
    );
  }

  /// Converte il periodo estratto dal parser (stringa `YYYY-MM`) in un
  /// `DateTime`, `null` se assente o malformato — stessa logica minimale di
  /// `_periodoFromEstratti` in `BustaPagaFormScreen`.
  ///
  /// Il mese è validato nell'intervallo 1-12: `DateTime(anno, mese)` da solo
  /// accetta silenziosamente anche 0/13 e li normalizza rispettivamente a
  /// dicembre dell'anno precedente/gennaio di quello successivo (es. un PDF
  /// con "Mens.supplementare 13/2026" letto dal parser regex, il cui gruppo
  /// mese non è a sua volta vincolato a 1-12) — un periodo silenziosamente
  /// sbagliato invece di un mancato riconoscimento esplicito, bug reale
  /// corretto qui, non un'ipotesi. Un periodo respinto qui torna `null`,
  /// stesso trattamento di "periodo non trovato": il flusso di import
  /// prosegue senza controllo anti-duplicati/rinomina basati sul periodo, e
  /// il form che si apre subito dopo mostra comunque il warning "Periodo non
  /// riconosciuto automaticamente" (vedi `_periodoFromEstratti` in
  /// `BustaPagaFormScreen`, stesso fallback).
  DateTime? _periodoDaStringa(String? periodo) {
    if (periodo == null) return null;
    final parti = periodo.split('-');
    final anno = int.tryParse(parti.elementAtOrNull(0) ?? '');
    final mese = int.tryParse(parti.elementAtOrNull(1) ?? '');
    if (anno == null || mese == null) return null;
    if (mese < 1 || mese > 12) return null;
    return DateTime(anno, mese);
  }

  void _showImportError(String title, String message) {
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

  @override
  Widget build(BuildContext context) {
    final textPrimary =
        CupertinoDynamicColor.resolve(AppColors.pulseTextPrimary, context);
    final textSecondary =
        CupertinoDynamicColor.resolve(AppColors.pulseTextSecondary, context);
    final accent =
        CupertinoDynamicColor.resolve(AppColors.pulseAccent, context);
    final now = DateTime.now();
    // Ogni volta che il range disponibile cambia (nuova busta paga importata
    // con un periodo più vecchio/recente di quelli già filtrati), un filtro
    // impostato manualmente in precedenza smette di coprire tutti i dati:
    // per evitare che l'utente debba riallargare lo slider a mano ogni
    // volta, il filtro torna a "nessun filtro" (range completo) — vedi
    // richiesta utente "il range deve sempre comprendere di default il
    // minimo e il massimo delle date".
    ref.listen(periodoRangeDisponibileProvider, (previous, next) {
      if (previous != null && previous != next) {
        setState(() => _periodoFiltro = null);
      }
    });
    // Ri-schedula i promemoria ad ogni cambiamento dell'archivio (import,
    // modifica, eliminazione) — copre anche il momento in cui
    // `BustePagaNotifier._initialize()` finisce di caricare lo stato reale
    // dal DB, correggendo l'eventuale chiamata iniziale fatta su una lista
    // ancora vuota (vedi `initState`/`_rescheduleReminders`).
    ref.listen<List<BustaPaga>>(busteRepositoryProvider, (previous, next) {
      final service = ref.read(payslipReminderServiceProvider);
      if (service != null) {
        unawaited(
          service.reschedule(next).catchError((Object error, StackTrace st) {
            debugPrint('Reschedule promemoria fallito: $error\n$st');
          }),
        );
      }
      unawaited(
        ref.read(homeWidgetServiceProvider).aggiorna(next).catchError(
          (Object error, StackTrace st) {
            debugPrint('Aggiornamento widget home fallito: $error\n$st');
          },
        ),
      );
    });
    final periodoRangeDisponibile = ref.watch(periodoRangeDisponibileProvider);
    final dataLabel = () {
      final formatted = DateFormat('EEEE d MMMM', 'it_IT').format(now);
      return formatted[0].toUpperCase() + formatted.substring(1);
    }();

    return ColoredBox(
      color: CupertinoDynamicColor.resolve(AppColors.pulseBackground, context),
      child: Stack(
        children: [
          Column(
            children: [
              // Header di benvenuto: saluto dinamico + data, sempre fisso
              // sopra il contenuto scrollabile (fuori da
              // Expanded/CustomScrollView). Niente più fascia a gradiente
              // colorato — direzione "Pulse" (vedi CLAUDE.md), il saluto
              // vive direttamente sullo sfondo della pagina. Nella tab
              // Archivio, il bottone di ricerca sostituisce il saluto con il
              // campo di ricerca quando attivo.
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenHorizontal,
                    AppSpacing.lg,
                    AppSpacing.screenHorizontal,
                    AppSpacing.md,
                  ),
                  child: _tab == _BustePagaTab.archivio && _searchActive
                      ? _buildSearchField(textPrimary, textSecondary)
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: _tab == _BustePagaTab.statistiche
                                    ? [
                                        Text(
                                          'Statistiche',
                                          style: AppTextStyles.pulseDisplay
                                              .copyWith(color: textPrimary),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Netto, ferie, straordinari',
                                          style: AppTextStyles.pulseBody
                                              .copyWith(color: textSecondary),
                                        ),
                                      ]
                                    : [
                                        Text(
                                          greetingFor(now),
                                          style: AppTextStyles.pulseDisplay
                                              .copyWith(color: textPrimary),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          dataLabel,
                                          style: AppTextStyles.pulseBody
                                              .copyWith(color: textSecondary),
                                        ),
                                      ],
                              ),
                            ),
                            if (_tab == _BustePagaTab.archivio)
                              Semantics(
                                label: 'Cerca',
                                button: true,
                                child: SpringButton(
                                  onPressed: () =>
                                      setState(() => _searchActive = true),
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    alignment: Alignment.center,
                                    child: PulseIcon(
                                      glyph: PulseIconGlyph.search,
                                      size: 22,
                                      color: accent,
                                    ),
                                  ),
                                ),
                              )
                            else if (_tab == _BustePagaTab.statistiche &&
                                periodoRangeDisponibile != null)
                              PeriodFilterButton(
                                minDate: periodoRangeDisponibile.start,
                                maxDate: periodoRangeDisponibile.end,
                                startValue: _periodoFiltro?.start ??
                                    periodoRangeDisponibile.start,
                                endValue: _periodoFiltro?.end ??
                                    periodoRangeDisponibile.end,
                                onChanged: (range) =>
                                    setState(() => _periodoFiltro = range),
                              ),
                          ],
                        ),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    if (_tab == _BustePagaTab.statistiche &&
                        periodoRangeDisponibile != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.screenHorizontal,
                          vertical: AppSpacing.sm,
                        ),
                        child: Container(
                          height: 0.5,
                          color: textSecondary.withValues(alpha: 0.24),
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          bottom: _sidecarReservedHeight,
                        ),
                        // Swipe orizzontale <-> tab della nav bar, vedi
                        // `_changeTab`/`_onPageChanged`. Asse ortogonale allo
                        // scroll verticale interno di entrambe le pagine
                        // (`CustomScrollView`), nessun conflitto di gesture:
                        // gli unici gesti orizzontali già presenti nelle due
                        // viste (swipe-to-delete `Dismissible` in Archivio,
                        // scroll orizzontale dei chip periodo in Statistiche)
                        // sono più annidati del `PageView` e vincono
                        // l'arena quando hanno effettivamente spazio per
                        // scorrere/essere trascinati, comportamento standard
                        // di Flutter per scroll/drag orizzontali annidati
                        // (stesso principio di un `ListView` orizzontale
                        // dentro una `TabBarView`).
                        child: PageView(
                          controller: _pageController,
                          onPageChanged: _onPageChanged,
                          children: [
                            BustePagaArchivioView(
                              onOpenDetail: (bustaPaga) =>
                                  _openDetail(context, bustaPaga),
                              onAdd: () => _startImport(),
                              searchActive: _searchActive,
                              query: _searchController.text,
                            ),
                            BustePagaStatisticheScreen(
                              periodoFiltro: _periodoFiltro,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            left: AppSpacing.screenHorizontal,
            right: AppSpacing.screenHorizontal,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _BustePagaNavBar(
                  tab: _tab,
                  onTabChanged: _changeTab,
                  onAdd: _importingPdf ? null : () => _startImport(),
                  importing: _importingPdf,
                  onDebugLongPress:
                      kDebugMode ? _avviaNotificaDiProvaDebug : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra di navigazione flottante ancorata in basso (redesign "Pulse", vedi
/// CLAUDE.md): `PulseSurface` non filled con i due tab Archivio/Statistiche,
/// più il bottone "+" (import PDF) come cerchio pieno separato accanto ad
/// essa.
class _BustePagaNavBar extends StatelessWidget {
  final _BustePagaTab tab;
  final ValueChanged<_BustePagaTab> onTabChanged;
  final VoidCallback? onAdd;
  final bool importing;

  /// Gancio di debug (vedi `_BustePagaSectionScreenState._avviaNotificaDiProvaDebug`),
  /// `null` fuori da `kDebugMode`: in quel caso nessun `GestureDetector` di
  /// long-press viene istanziato attorno al "+", il gesto non esiste
  /// proprio in una build di release, nessuna differenza visiva in
  /// nessuna delle due build.
  final VoidCallback? onDebugLongPress;

  const _BustePagaNavBar({
    required this.tab,
    required this.onTabChanged,
    required this.onAdd,
    required this.importing,
    this.onDebugLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final accent =
        CupertinoDynamicColor.resolve(AppColors.pulseAccent, context);
    final onAccent =
        CupertinoDynamicColor.resolve(AppColors.pulseOnAccent, context);
    final textSecondary =
        CupertinoDynamicColor.resolve(AppColors.pulseTextSecondary, context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: PulseSurface(
            borderRadius: AppRadius.pulse,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            child: IntrinsicHeight(
              child: Stack(
                children: [
                  // Pillola di sfondo del tab attivo: stessa durata/curva di
                  // `AnimatedContainer` in `FlatChipButton._buildFlat`
                  // (200ms/`Curves.easeOut`), coerente col resto della UI.
                  // Colore `pulseAccent` a bassa opacità, non un riempimento
                  // pieno (stesso principio dello stato "filled" di
                  // `FlatChipButton`).
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    alignment: tab == _BustePagaTab.archivio
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: 0.5,
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(AppRadius.pulseSmall),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _NavBarTab(
                          glyph: PulseIconGlyph.archive,
                          label: 'Archivio',
                          active: tab == _BustePagaTab.archivio,
                          accent: accent,
                          inactive: textSecondary,
                          onPressed: () =>
                              onTabChanged(_BustePagaTab.archivio),
                        ),
                      ),
                      Expanded(
                        child: _NavBarTab(
                          glyph: PulseIconGlyph.chart,
                          label: 'Statistiche',
                          active: tab == _BustePagaTab.statistiche,
                          accent: accent,
                          inactive: textSecondary,
                          onPressed: () =>
                              onTabChanged(_BustePagaTab.statistiche),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Semantics(
          label: 'Aggiungi busta paga',
          button: true,
          // Long-press per la notifica di prova: SOLO sotto kDebugMode (vedi
          // `onDebugLongPress`), un GestureDetector aggiuntivo attorno al
          // "+", nessun cambiamento visivo — stessa icona, stesso colore,
          // stesso layout in entrambe le build.
          child: onDebugLongPress == null
              ? _plusButton(accent, onAccent)
              : GestureDetector(
                  onLongPress: onDebugLongPress,
                  child: _plusButton(accent, onAccent),
                ),
        ),
      ],
    );
  }

  Widget _plusButton(Color accent, Color onAccent) {
    return SpringButton(
      onPressed: onAdd ?? () {},
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: importing
            ? CupertinoActivityIndicator(color: onAccent)
            : PulseIcon(
                glyph: PulseIconGlyph.add,
                size: 24,
                color: onAccent,
              ),
      ),
    );
  }
}

/// Singolo tab della barra di navigazione: icona+label, colorati con
/// `accent` quando attivo, `inactive` altrimenti. L'indicatore di sfondo del
/// tab attivo (pillola animata) vive un livello sopra, in `_BustePagaNavBar`
/// (`AnimatedAlign` dietro questa `Row`), non qui: questo widget si limita al
/// colore di icona/testo.
class _NavBarTab extends StatelessWidget {
  final PulseIconGlyph glyph;
  final String label;
  final bool active;
  final Color accent;
  final Color inactive;
  final VoidCallback onPressed;

  const _NavBarTab({
    required this.glyph,
    required this.label,
    required this.active,
    required this.accent,
    required this.inactive,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? accent : inactive;
    return SpringButton(
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PulseIcon(glyph: glyph, size: 22, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTextStyles.pulseLabel.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
