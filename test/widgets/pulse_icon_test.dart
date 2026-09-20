import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buts/widgets/pulse_icon.dart';

void main() {
  for (final size in [22.0, 18.0]) {
    testWidgets('tutti i glifi Pulse si dipingono a size $size', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Wrap(
            children: [
              for (final g in PulseIconGlyph.values)
                PulseIcon(
                  glyph: g,
                  size: size,
                  color: const Color(0xFFFFFFFF),
                ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(PulseIcon), findsNWidgets(PulseIconGlyph.values.length));
    });
  }
}
