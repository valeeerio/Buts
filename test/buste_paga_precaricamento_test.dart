import 'package:buts/data/database.dart';
import 'package:buts/models/busta_paga.dart';
import 'package:buts/providers/buste_paga_provider.dart';
import 'package:buts/services/pdf_import_service.dart';
import 'package:buts/services/pdf_path_resolver.dart';
import 'package:drift/native.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  testWidgets(
      'con stato precaricato il primo frame ha già le buste e '
      'caricamentoCompletato è true', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.bustePagaTable)
        .insertOnConflictUpdate(_busta('bp-1').toCompanion());
    final buste = (await tester.runAsync(() => leggiBusteResilienti(db)))!;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          busteInizialiProvider.overrideWithValue(buste),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            final n = ref.watch(busteRepositoryProvider).length;
            final ok = ref.watch(busteCaricamentoCompletatoProvider);
            return Directionality(
              textDirection: TextDirection.ltr,
              child: Text('n=$n ok=$ok'),
            );
          },
        ),
      ),
    );

    expect(find.text('n=1 ok=true'), findsOneWidget);
  });

  test('leggiBusteResilienti: fallback scarta solo la riga corrotta', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.bustePagaTable)
        .insertOnConflictUpdate(_busta('bp-valida').toCompanion());
    await db.customStatement(
      '''
      INSERT INTO ${db.bustePagaTable.actualTableName}
        (id, periodo, lordo, netto, trattenute, straordinari,
         ferie_maturate, ferie_godute, ferie_residue, rol_maturati,
         rol_goduti, rol_residui, permessi_goduti, ore_lavorate)
      VALUES
        ('bp-corrotta', 1700000000000, 2000, 1500, '{non json',
         0, 0, 0, 0, 0, 0, 0, 0, 168)
      ''',
    );

    final buste = await leggiBusteResilienti(db);
    expect(buste.map((b) => b.id), ['bp-valida']);
  });

  testWidgets('percorso veloce con più righe valide', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    for (final id in ['bp-1', 'bp-2', 'bp-3']) {
      await db
          .into(db.bustePagaTable)
          .insertOnConflictUpdate(_busta(id).toCompanion());
    }
    final buste = (await tester.runAsync(() => leggiBusteResilienti(db)))!;
    expect(buste.map((b) => b.id).toSet(), {'bp-1', 'bp-2', 'bp-3'});

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      busteInizialiProvider.overrideWithValue(buste),
    ]);
    addTearDown(container.dispose);
    expect(container.read(busteRepositoryProvider).length, 3);
    expect(container.read(busteCaricamentoCompletatoProvider), isTrue);
  });

  test('fallback lazy: iniziali null carica dal DB', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.bustePagaTable)
        .insertOnConflictUpdate(_busta('bp-1').toCompanion());
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);

    expect(container.read(busteRepositoryProvider), isEmpty);
    expect(container.read(busteCaricamentoCompletatoProvider), isFalse);
    // Attende il completamento della SELECT iniziale.
    for (var i = 0; i < 50; i++) {
      if (container
          .read(busteRepositoryProvider.notifier)
          .caricamentoCompletato) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(container.read(busteRepositoryProvider).map((b) => b.id), ['bp-1']);
    expect(container.read(busteCaricamentoCompletatoProvider), isTrue);
  });

  test('sweep: non cancella il PDF di una riga corrotta, cancella gli orfani',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final tmp = await Directory.systemTemp.createTemp('buts_sweep');
    addTearDown(() => tmp.delete(recursive: true));
    final pdfDir = Directory(p.join(tmp.path, pdfBusteDirName))
      ..createSync(recursive: true);
    for (final n in ['valida.pdf', 'corrotta.pdf', 'orfano.pdf']) {
      File(p.join(pdfDir.path, n)).writeAsStringSync('x');
    }

    await db.into(db.bustePagaTable).insertOnConflictUpdate(_busta('bp-valida')
        .copyWith(fileOrigine: p.join(pdfBusteDirName, 'valida.pdf'))
        .toCompanion());
    await db.customStatement(
      '''
      INSERT INTO ${db.bustePagaTable.actualTableName}
        (id, periodo, lordo, netto, trattenute, straordinari,
         ferie_maturate, ferie_godute, ferie_residue, rol_maturati,
         rol_goduti, rol_residui, permessi_goduti, ore_lavorate, file_origine)
      VALUES
        ('bp-corrotta', 1700000000000, 2000, 1500, '{non json',
         0, 0, 0, 0, 0, 0, 0, 0, 168, 'buste_paga_pdf/corrotta.pdf')
      ''',
    );

    final iniziali = await leggiBusteResilienti(db);
    expect(iniziali.map((b) => b.id), ['bp-valida']);

    final notifier = BustePagaNotifier(
      db,
      const PdfImportService(),
      iniziali: iniziali,
      documentsDirectory: () async => tmp,
    );
    addTearDown(notifier.dispose);
    await notifier.sweepPdfOrfani();

    expect(File(p.join(pdfDir.path, 'valida.pdf')).existsSync(), isTrue);
    expect(File(p.join(pdfDir.path, 'corrotta.pdf')).existsSync(), isTrue);
    expect(File(p.join(pdfDir.path, 'orfano.pdf')).existsSync(), isFalse);
  });
}
