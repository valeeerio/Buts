import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/database.dart';
import 'models/busta_paga.dart';
import 'providers/buste_paga_provider.dart';
import 'providers/reminder_scheduler_provider.dart';
import 'screens/buste_paga/buste_paga_section_screen.dart';
import 'services/home_widget_launch.dart';
import 'services/payslip_reminder_service.dart';
import 'services/reminder_notifications.dart';
import 'widgets/app_launch_overlay.dart';

/// Subscription dell'ascolto "tap sul widget ad app già in esecuzione"
/// (`registraAscoltoHomeWidgetClicked`), tenuta viva per l'intera sessione
/// app in una variabile top-level: senza un riferimento esterno mantenuto
/// esplicitamente, non c'è garanzia che l'oggetto non venga raccolto dal
/// garbage collector (lo `StreamSubscription` restituito non viene mai
/// letto/cancellato altrove). Non serve mai leggerla: esiste solo per
/// tenere viva la subscription.
// ignore: unused_element
late final StreamSubscription<Uri?> _homeWidgetClickSub;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it_IT');

  // Avvia subito la lettura del DB, prima delle init dei promemoria/widget,
  // così procede in parallelo (le Future partono eagerly). Gli errori sono
  // gestiti più sotto, all'await; `ignore()` evita l'errore "unhandled" se le
  // init sotto falliscono/ritardano prima che la Future venga attesa. Il
  // costruttore `AppDatabase()` apre la connessione in modo lazy e
  // `leggiBusteResilienti` è `async` (non lancia mai in modo sincrono), quindi
  // non serve un try/catch attorno a questa parte.
  final db = AppDatabase();
  final busteFuture = leggiBusteResilienti(db)..ignore();

  final reminderScheduler = LocalNotificationsScheduler();
  // `null` finché la costruzione sotto non va a buon fine: resta `null` se
  // una qualunque delle chiamate nel `try` fallisce, e in tal caso
  // `payslipReminderServiceProvider` NON viene sovrascritto più sotto — resta
  // sul default `null` del provider (vedi `reminder_scheduler_provider.dart`).
  // Questo è deliberatamente un guard diverso da quello di
  // `reminderSchedulerProvider`, che viene sempre iniettato: qui un guasto
  // (SharedPreferences non disponibile, plugin di notifiche non
  // inizializzabile) non deve mai propagarsi come provider "rotto" da
  // leggere più avanti — l'app deve aprirsi comunque sull'archivio, solo
  // senza promemoria in questa sessione.
  PayslipReminderService? payslipReminderService;
  try {
    // Ordine critico: `consumaLaunchDetails()` legge se l'app è stata aperta
    // dal tap su una notifica mentre era terminata (cold start) e aggiorna
    // `pendingImportRequest` di conseguenza — va fatto PRIMA di `runApp`,
    // perché la schermata radice che osserverà quel valore (fase successiva)
    // viene costruita subito dopo e non deve perdersi il segnale.
    await reminderScheduler.init();
    await reminderScheduler.consumaLaunchDetails();
    // Widget iOS della home screen: stesso spirito del promemoria appena
    // sopra, un guasto qui (App Group non configurato, plugin nativo
    // assente) non deve mai impedire l'apertura dell'archivio buste paga —
    // vedi il commento sul try/catch che avvolge questo intero blocco.
    await HomeWidget.setAppGroupId('group.com.buts.buts');
    await consumaHomeWidgetLaunch();
    _homeWidgetClickSub = registraAscoltoHomeWidgetClicked();
    final preferences = await SharedPreferences.getInstance();
    payslipReminderService = PayslipReminderService(
      scheduler: reminderScheduler,
      preferences: preferences,
    );
  } catch (_) {
    // Un promemoria rotto (permessi, plugin non disponibile, storage delle
    // preferenze non disponibile, qualunque eccezione) non può impedire
    // l'accesso all'archivio delle buste paga: l'app si avvia comunque,
    // semplicemente senza notifiche funzionanti in questa sessione.
  }

  // Precaricamento DB: la lettura parte subito, in parallelo con le init
  // sopra, e qui la si attende (di norma già completata). Un errore non
  // blocca l'avvio: senza override si ricade sul caricamento lazy.
  List<BustaPaga>? buste;
  try {
    buste = await busteFuture;
  } catch (e) {
    debugPrint('Precaricamento buste paga fallito, ripiego sul lazy: $e');
    buste = null;
  }

  runApp(
    ButsApp(
      overrides: [
        // Il DB già aperto viene riusato anche se il precaricamento è
        // fallito (in tal caso il notifier ricade sul caricamento lazy).
        databaseProvider.overrideWithValue(db),
        if (buste != null) busteInizialiProvider.overrideWithValue(buste),
        reminderSchedulerProvider.overrideWithValue(reminderScheduler),
        if (payslipReminderService != null)
          payslipReminderServiceProvider.overrideWithValue(
            payslipReminderService,
          ),
      ],
    ),
  );
}

/// L'app è a sezione singola: Buste Paga è la root, nessuna sotto-navigazione
/// radice (vedi CLAUDE.md).
class ButsApp extends StatelessWidget {
  const ButsApp({
    super.key,
    this.overrides = const [],
    this.mostraAnimazioneAvvio = true,
  });

  /// Override dei provider Riverpod da iniettare sul `ProviderScope` radice.
  /// Vuoto di default (usato anche dai widget test, che non hanno bisogno di
  /// un [ReminderScheduler] reale): `main()` lo popola con l'istanza di
  /// [LocalNotificationsScheduler] già inizializzata prima di `runApp`, vedi
  /// [reminderSchedulerProvider].
  final List<Override> overrides;

  /// Mostra l'animazione di avvio (anello) sopra l'archivio. I test la
  /// disattivano per evitare timer/animazioni pendenti.
  final bool mostraAnimazioneAvvio;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: overrides,
      child: CupertinoApp(
        title: 'Buts',
        debugShowCheckedModeBanner: false,
        theme: const CupertinoThemeData(brightness: Brightness.dark),
        localizationsDelegates: const [
          DefaultCupertinoLocalizations.delegate,
        ],
        home: _ButsHome(mostraAnimazioneAvvio: mostraAnimazioneAvvio),
      ),
    );
  }
}

class _ButsHome extends StatefulWidget {
  const _ButsHome({required this.mostraAnimazioneAvvio});

  final bool mostraAnimazioneAvvio;

  @override
  State<_ButsHome> createState() => _ButsHomeState();
}

class _ButsHomeState extends State<_ButsHome> {
  late bool _animazioneAttiva = widget.mostraAnimazioneAvvio;
  final _progress = ValueNotifier<double>(0);
  // Vero quando l'archivio può aprire dialog/route (fine animazione, o subito
  // se l'animazione è disattivata).
  late final _avvioCompletato =
      ValueNotifier<bool>(!widget.mostraAnimazioneAvvio);

  @override
  void dispose() {
    _progress.dispose();
    _avvioCompletato.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // L'archivio (già popolato al primo frame) entra come unico blocco
    // (opacità + salita) in sincrono con l'overlay, che sta sopra.
    return CupertinoPageScaffold(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AppLaunchReveal(
            progress: _animazioneAttiva ? _progress : null,
            child: BustePagaSectionScreen(avvioCompletato: _avvioCompletato),
          ),
          if (_animazioneAttiva)
            Positioned.fill(
              child: AppLaunchOverlay(
                progress: _progress,
                onDone: () {
                  if (!mounted) return;
                  _avvioCompletato.value = true;
                  setState(() => _animazioneAttiva = false);
                },
              ),
            ),
        ],
      ),
    );
  }
}
