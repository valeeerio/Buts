import 'package:buts/widgets/flat_chip_button.dart';
import 'package:buts/widgets/pulse_icon.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FlatChipButton chip({required bool primary, String label = 'Modifica'}) =>
      FlatChipButton(
        pulseGlyph: PulseIconGlyph.edit,
        label: label,
        color: const Color(0xFF00AAFF),
        primary: primary,
        onPressed: () {},
      );

  // Riproduce `slot()` di dettaglio/form: il chip è figlio NON posizionato di
  // uno `Stack` (quindi riceve vincoli SCIOLTI) con `Positioned.fill` per lo
  // sfondo, dentro un `Expanded`.
  Widget slot(Key key, FlatChipButton child) => Expanded(
        child: ClipRRect(
          key: key,
          child: Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(color: Color(0xFF222222)),
              ),
              child,
            ],
          ),
        ),
      );

  Widget host(double width, List<Widget> rowChildren) => Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: width,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rowChildren,
              ),
            ),
          ),
        ),
      );

  for (final primary in [true, false]) {
    testWidgets(
        'vincoli sciolti (Stack): il chip riempie lo slot (primary=$primary)',
        (tester) async {
      const slotKey = Key('slot');
      await tester.pumpWidget(host(300, [slot(slotKey, chip(primary: primary))]));

      final slotWidth = tester.getSize(find.byKey(slotKey)).width;
      expect(slotWidth, 300);

      final chipFinder = find.byType(FlatChipButton);
      expect(tester.getSize(chipFinder).width, slotWidth);

      final decorated = primary
          ? find.descendant(of: chipFinder, matching: find.byType(DecoratedBox))
          : find.descendant(
              of: chipFinder, matching: find.byType(AnimatedContainer));
      expect(decorated, findsWidgets);
      expect(tester.getSize(decorated.first).width, slotWidth);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Row flex 7/3 con slot stretti: proporzionale, nessun overflow',
      (tester) async {
    const a = Key('a');
    const b = Key('b');
    await tester.pumpWidget(host(300, [
      Expanded(
        flex: 7,
        child: ClipRRect(
          key: a,
          child: Stack(children: [
            const Positioned.fill(child: ColoredBox(color: Color(0xFF222222))),
            chip(primary: true),
          ]),
        ),
      ),
      Expanded(
        flex: 3,
        child: ClipRRect(
          key: b,
          child: Stack(children: [
            const Positioned.fill(child: ColoredBox(color: Color(0xFF222222))),
            chip(primary: false, label: 'Annulla'),
          ]),
        ),
      ),
    ]));

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(a)).width, 210);
    expect(tester.getSize(find.byKey(b)).width, 90);
    final chips = find.byType(FlatChipButton);
    expect(tester.getSize(chips.at(0)).width, 210);
    expect(tester.getSize(chips.at(1)).width, 90);
  });

  testWidgets('slot molto stretto (40px): nessun overflow', (tester) async {
    const slotKey = Key('slot');
    await tester.pumpWidget(host(40, [slot(slotKey, chip(primary: true))]));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(FlatChipButton)).width, 40);
  });
}
