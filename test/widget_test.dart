import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:buts/main.dart';

void main() {
  testWidgets('ButsApp avvia senza errori e mostra l\'archivio Buste Paga', (
    WidgetTester tester,
  ) async {
    await initializeDateFormatting('it_IT');
    await tester.pumpWidget(const ButsApp(mostraAnimazioneAvvio: false));
    await tester.pumpAndSettle();

    expect(find.byType(ButsApp), findsOneWidget);
  });
}
