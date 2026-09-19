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

void main() {
  _testReveal();
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

void _testReveal() {
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
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: AppLaunchReveal(progress: progress, child: const SizedBox()),
    ));
    bool ignoring() => tester
        .widget<IgnorePointer>(find.descendant(
            of: find.byType(AppLaunchReveal),
            matching: find.byType(IgnorePointer)))
        .ignoring;
    expect(ignoring(), isTrue);
    progress.value = 1;
    await tester.pump();
    expect(ignoring(), isFalse);
  });
}
