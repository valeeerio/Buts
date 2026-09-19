// Copre `BustePagaSectionScreen(avvioCompletato: ...)`: onboarding promemoria
// e richieste pendenti (import da notifica, dettaglio da widget) devono
// attendere la fine dell'animazione di avvio, e partire una sola volta.
import 'package:buts/data/database.dart';
import 'package:buts/main.dart';
import 'package:buts/models/busta_paga.dart';
import 'package:buts/providers/buste_paga_provider.dart';
import 'package:buts/providers/reminder_scheduler_provider.dart';
import 'package:buts/screens/buste_paga/busta_paga_detail_screen.dart';
import 'package:buts/screens/buste_paga/buste_paga_section_screen.dart';
import 'package:buts/services/home_widget_launch.dart';
import 'package:buts/services/payslip_reminder_service.dart';
import 'package:buts/services/pdf_import_service.dart';
import 'package:buts/services/reminder_notifications.dart';
import 'package:buts/widgets/app_launch_overlay.dart';
import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeScheduler implements ReminderScheduler {
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> cancelAll() async {}
  @override
  Future<void> schedule({
    required int id,
    required DateTime quando,
    required String titolo,
    required String corpo,
  }) async {}
  @override
  Future<void> consumaLaunchDetails() async {}
}

BustaPaga _busta(String id) => BustaPaga(
      id: id,
      periodo: DateTime(2026, 1),
      lordo: 2000,
      netto: 1500,
      trattenute: const {},
      straordinari: 0,
      ferieMaturate: 0,
      ferieGodute: 0,
      ferieResidue: 0,
      rolMaturati: 0,
      rolGoduti: 0,
      rolResidui: 0,
      permessiGoduti: 0,
      oreLavorate: 168,
    );

Future<({AppDatabase db, BustePagaNotifier notifier})> _setUp(
  WidgetTester tester, {
  List<BustaPaga> buste = const [],
}) async {
  late final AppDatabase db;
  late final BustePagaNotifier notifier;
  await tester.runAsync(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    notifier = BustePagaNotifier(db, const PdfImportService());
    await Future<void>.delayed(Duration.zero);
    for (final b in buste) {
      await notifier.add(b);
    }
  });
  return (db: db, notifier: notifier);
}

Future<PayslipReminderService> _service() async {
  SharedPreferences.setMockInitialValues({});
  return PayslipReminderService(
    scheduler: _FakeScheduler(),
    preferences: await SharedPreferences.getInstance(),
  );
}

Future<void> _pump(
  WidgetTester tester,
  BustePagaNotifier notifier, {
  ValueListenable<bool>? avvio,
  PayslipReminderService? service,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        busteRepositoryProvider.overrideWith((ref) => notifier),
        if (service != null)
          payslipReminderServiceProvider.overrideWithValue(service),
      ],
      child: CupertinoApp(home: BustePagaSectionScreen(avvioCompletato: avvio)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('it_IT');
  });

  // Conta le aperture del file picker (= avvii dell'import) e simula
  // "annullato".
  late int pickerCalls;
  setUp(() {
    pickerCalls = 0;
    pendingImportRequest.value = false;
    pendingBustaDetailId.value = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/file_selector'),
      (call) async {
        if (call.method == 'openFile') pickerCalls++;
        return null;
      },
    );
  });
  tearDown(() {
    pendingImportRequest.value = false;
    pendingBustaDetailId.value = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/file_selector'), null);
  });

  testWidgets('onboarding promemoria parte solo dopo avvioCompletato',
      (tester) async {
    final repo = await _setUp(tester);
    final avvio = ValueNotifier<bool>(false);
    await _pump(tester, repo.notifier, avvio: avvio, service: await _service());

    expect(find.text('Promemoria busta paga'), findsNothing);

    avvio.value = true;
    await tester.pumpAndSettle();
    expect(find.text('Promemoria busta paga'), findsOneWidget);

    await tester.runAsync(() => repo.db.close());
  });

  testWidgets(
      'import e dettaglio pendenti attendono l\'avvio, poi partono '
      'una sola volta', (tester) async {
    final repo = await _setUp(tester, buste: [_busta('bp-1')]);
    pendingImportRequest.value = true;
    pendingBustaDetailId.value = 'bp-1';
    final avvio = ValueNotifier<bool>(false);

    await _pump(tester, repo.notifier, avvio: avvio);

    expect(pickerCalls, 0);
    expect(find.byType(BustaPagaDetailScreen), findsNothing);
    expect(pendingImportRequest.value, isTrue);
    expect(pendingBustaDetailId.value, 'bp-1');

    avvio.value = true;
    await tester.pumpAndSettle();

    expect(pickerCalls, 1);
    expect(find.byType(BustaPagaDetailScreen), findsOneWidget);
    expect(pendingImportRequest.value, isFalse);
    expect(pendingBustaDetailId.value, isNull);

    // Altri cambi del notifier non riavviano nulla.
    avvio.value = false;
    avvio.value = true;
    await tester.pumpAndSettle();
    expect(pickerCalls, 1);

    await tester.runAsync(() => repo.db.close());
  });

  testWidgets('con avvioCompletato null il comportamento e invariato',
      (tester) async {
    final repo = await _setUp(tester, buste: [_busta('bp-1')]);
    pendingImportRequest.value = true;
    pendingBustaDetailId.value = 'bp-1';

    await _pump(tester, repo.notifier, service: await _service());

    // Onboarding e' il primo a partire e blocca in attesa dell'utente:
    // i pendenti restano finche' non viene chiuso.
    expect(find.text('Promemoria busta paga'), findsOneWidget);
    await tester.tap(find.text('Non ora'));
    await tester.pumpAndSettle();

    expect(pickerCalls, 1);
    expect(find.byType(BustaPagaDetailScreen), findsOneWidget);
    expect(pendingImportRequest.value, isFalse);
    expect(pendingBustaDetailId.value, isNull);

    await tester.runAsync(() => repo.db.close());
  });

  testWidgets(
      'dispose prima della fine avvio: nessun errore alla successiva '
      'transizione', (tester) async {
    final repo = await _setUp(tester);
    final avvio = ValueNotifier<bool>(false);
    await _pump(tester, repo.notifier, avvio: avvio);

    await tester.pumpWidget(const SizedBox());
    avvio.value = true;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => repo.db.close());
  });

  testWidgets(
      'ButsApp: overlay rimosso a fine animazione senza rimontare la '
      'schermata', (tester) async {
    final repo = await _setUp(tester);
    await tester.pumpWidget(ButsApp(overrides: [
      busteRepositoryProvider.overrideWith((ref) => repo.notifier),
    ]));
    expect(find.byType(AppLaunchOverlay), findsOneWidget);
    final prima = tester.element(find.byType(BustePagaSectionScreen));

    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();

    expect(find.byType(AppLaunchOverlay), findsNothing);
    final dopo = tester.element(find.byType(BustePagaSectionScreen));
    expect(identical(prima, dopo), isTrue);
    expect((dopo as StatefulElement).state.mounted, isTrue);

    await tester.pumpAndSettle();
    await tester.runAsync(() => repo.db.close());
  });
}
