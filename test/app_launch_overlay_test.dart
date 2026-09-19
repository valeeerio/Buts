import 'package:buts/widgets/app_launch_overlay.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({bool disableAnimations = false, VoidCallback? onDone}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(children: [
        Positioned.fill(child: AppLaunchOverlay(onDone: onDone)),
      ]),
    ),
  );
}

class _Sonda extends StatefulWidget {
  const _Sonda(this.log);
  final List<String> log;
  @override
  State<_Sonda> createState() => _SondaState();
}

class _SondaState extends State<_Sonda> {
  @override
  void initState() {
    super.initState();
    widget.log.add('init');
  }

  @override
  void dispose() {
    widget.log.add('dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

/// Monta un [AppLaunchReveal] con [progress] fisso e ne restituisce i
/// finder utili.
Future<void> _pumpReveal(
  WidgetTester tester,
  ValueNotifier<double> progress, {
  bool disableAnimations = false,
}) {
  return tester.pumpWidget(MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: AppLaunchReveal(progress: progress, child: const SizedBox()),
    ),
  ));
}

bool _ignoring(WidgetTester tester) => tester
    .widget<IgnorePointer>(find.descendant(
        of: find.byType(AppLaunchReveal), matching: find.byType(IgnorePointer)))
    .ignoring;

void main() {
  testWidgets('a t=0 anello con sweep 285', (tester) async {
    await tester.pumpWidget(_host());
    final painter = tester
        .widget<CustomPaint>(find.descendant(
            of: find.byType(AppLaunchOverlay),
            matching: find.byType(CustomPaint)))
        .painter! as LaunchRingPainter;
    expect(painter.ms, 0);
    expect(LaunchRingPainter.sweepAt(painter.ms), 285);
    expect(LaunchRingPainter.sweepAt(1000), 360);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump();
  });

  testWidgets('finisce a 1500 ms e chiama onDone', (tester) async {
    var done = false;
    await tester.pumpWidget(_host(onDone: () => done = true));
    await tester.pump(const Duration(milliseconds: 1400));
    expect(done, isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    expect(done, isTrue);
  });

  testWidgets('con disableAnimations dura 200 ms', (tester) async {
    var done = false;
    await tester
        .pumpWidget(_host(disableAnimations: true, onDone: () => done = true));
    await tester.pump(const Duration(milliseconds: 150));
    expect(done, isFalse);
    await tester.pump(const Duration(milliseconds: 100));
    expect(done, isTrue);
  });

  group('AppLaunchReveal', () {
    testWidgets('lo State del figlio sopravvive a onDone', (tester) async {
      final log = <String>[];
      final progress = ValueNotifier<double>(0);
      var attiva = true;
      late StateSetter rebuild;
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(builder: (context, setState) {
          rebuild = setState;
          return Stack(children: [
            AppLaunchReveal(
                progress: attiva ? progress : null, child: _Sonda(log)),
            if (attiva)
              Positioned.fill(
                child: AppLaunchOverlay(
                  progress: progress,
                  onDone: () => rebuild(() => attiva = false),
                ),
              ),
          ]);
        }),
      ));
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump();
      expect(attiva, isFalse);
      expect(log, ['init']);
    });

    testWidgets('archivio ignora i tocchi finche non e visibile',
        (tester) async {
      final progress = ValueNotifier<double>(0);
      await _pumpReveal(tester, progress);
      expect(_ignoring(tester), isTrue);
      progress.value = 1;
      await tester.pump();
      expect(_ignoring(tester), isFalse);
    });

    testWidgets('soglia tocchi: progress 0.59 ignora, 0.601 no', (tester) async {
      final progress = ValueNotifier<double>(0.59);
      await _pumpReveal(tester, progress);
      expect(_ignoring(tester), isTrue);
      // 0.6 esatto darebbe 0.6*1.5 = 0.8999... in double: si usa 0.601.
      progress.value = 0.601;
      await tester.pump();
      expect(_ignoring(tester), isFalse);
    });

    testWidgets('con disableAnimations nessuna salita (offset 0)',
        (tester) async {
      final progress = ValueNotifier<double>(0.6);
      await _pumpReveal(tester, progress, disableAnimations: true);
      double dy() => tester
          .widget<Transform>(find.descendant(
              of: find.byType(AppLaunchReveal),
              matching: find.byType(Transform)))
          .transform
          .getTranslation()
          .y;
      expect(dy(), 0);

      // Controprova: senza disableAnimations la salita c'e' (a t=0).
      await _pumpReveal(tester, ValueNotifier<double>(0.6));
      expect(dy(), 14);
    });
  });
}
