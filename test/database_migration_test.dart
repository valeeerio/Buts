import 'dart:io';

import 'package:buts/data/database.dart';
import 'package:buts/models/busta_paga.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// Copre il percorso di migrazione `AppDatabase.migration.onUpgrade`
/// (`lib/data/database.dart`, circa righe 187-236), da uno schema v3 fino
/// all'attuale `schemaVersion => 7`, con righe di dati preesistenti nella
/// tabella `BustePagaTable`.
///
/// Ad oggi nessun test copre `onUpgrade`: gli altri test Drift del progetto
/// (`buste_paga_provider_test.dart`, `busta_paga_form_screen_test.dart`, ecc.)
/// creano sempre `AppDatabase.forTesting(NativeDatabase.memory())`, che passa
/// sempre da `onCreate` già a schema corrente. Questo è un rischio concreto:
/// ci sono già buste paga salvate su device reali con schemi precedenti a
/// v6, e ogni step additivo (v3->v4 `tipo`, v4->v5 `competenze`/
/// `permessiGodutiMese`, v5->v6 le tre colonne ex festività, v6->v7 `layout`) deve applicarsi
/// senza perdere né alterare i dati già presenti.
///
/// Il DB v3 di partenza viene creato con `package:sqlite3` direttamente
/// (bypassando Drift) su un file temporaneo, scrivendo lo schema SQL v3
/// dedotto da `database.dart` togliendo le colonne aggiunte in `onUpgrade`
/// dopo v3 (`tipo`, `competenze`, `permessi_goduti_mese`,
/// `ex_festivita_maturate/godute/residue`) e impostando
/// `PRAGMA user_version = 3`. Poi lo stesso file viene riaperto con
/// `AppDatabase.forTesting`, che forza l'esecuzione di `onUpgrade` da 3 a 7
/// (`schemaVersion` attuale) alla prima query.
void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('buts_migration_test');
    dbFile = File(p.join(tempDir.path, 'buts_v3.sqlite'));
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// Crea il file sqlite con lo schema v3 (nessuna delle colonne aggiunte in
  /// v4/v5/v6/v7) e una riga di dati realistica, tramite `package:sqlite3`
  /// diretto (bypassa completamente Drift, come farebbe un DB reale creato
  /// da una versione precedente dell'app).
  void seedSchemaV3() {
    final raw = sqlite3.sqlite3.open(dbFile.path);
    raw.execute('''
      CREATE TABLE buste_paga_table (
        id TEXT NOT NULL,
        periodo INTEGER NOT NULL,
        file_origine TEXT NULL,
        lordo REAL NOT NULL,
        netto REAL NOT NULL,
        trattenute TEXT NOT NULL DEFAULT '{}',
        straordinari REAL NOT NULL,
        ferie_maturate REAL NOT NULL,
        ferie_godute REAL NOT NULL,
        ferie_residue REAL NOT NULL,
        rol_maturati REAL NOT NULL,
        rol_goduti REAL NOT NULL,
        rol_residui REAL NOT NULL,
        permessi_goduti REAL NOT NULL,
        ore_lavorate REAL NOT NULL,
        stato_verifica INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY (id)
      )
    ''');
    raw.execute('''
      INSERT INTO buste_paga_table (
        id, periodo, file_origine, lordo, netto, trattenute, straordinari,
        ferie_maturate, ferie_godute, ferie_residue, rol_maturati,
        rol_goduti, rol_residui, permessi_goduti, ore_lavorate,
        stato_verifica
      ) VALUES (
        'bp-legacy-2025-06', 1748736000, 'busta-giugno.pdf', 2200.5,
        1650.75, '{"INPS":150.0,"IRPEF":300.25}', 8.5, 22.0, 10.0, 12.0,
        5.0, 2.0, 3.0, 4.0, 168.0, 1
      )
    ''');
    raw.execute('PRAGMA user_version = 3');
    raw.close();
  }

  group('AppDatabase — migrazione onUpgrade v3 -> v7 con dati preesistenti',
      () {
    test(
        'righe preesistenti restano leggibili e intatte, nuove colonne '
        'ricevono i default documentati, nessuna eccezione', () async {
      seedSchemaV3();

      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);

      // Forza l'apertura effettiva della connessione (e quindi
      // l'esecuzione di onUpgrade) con la prima query.
      final righe = await db.select(db.bustePagaTable).get();

      expect(righe, hasLength(1));
      final riga = righe.single;

      // Colonne pre-esistenti in v3: valori originali intatti.
      expect(riga.id, 'bp-legacy-2025-06');
      expect(
        riga.periodo,
        DateTime.fromMillisecondsSinceEpoch(1748736000 * 1000),
      );
      expect(riga.fileOrigine, 'busta-giugno.pdf');
      expect(riga.lordo, closeTo(2200.5, 0.001));
      expect(riga.netto, closeTo(1650.75, 0.001));
      expect(riga.trattenute, {'INPS': 150.0, 'IRPEF': 300.25});
      expect(riga.straordinari, closeTo(8.5, 0.001));
      expect(riga.ferieMaturate, closeTo(22.0, 0.001));
      expect(riga.ferieGodute, closeTo(10.0, 0.001));
      expect(riga.ferieResidue, closeTo(12.0, 0.001));
      expect(riga.rolMaturati, closeTo(5.0, 0.001));
      expect(riga.rolGoduti, closeTo(2.0, 0.001));
      expect(riga.rolResidui, closeTo(3.0, 0.001));
      expect(riga.permessiGoduti, closeTo(4.0, 0.001));
      expect(riga.oreLavorate, closeTo(168.0, 0.001));
      expect(riga.statoVerifica, StatoVerificaBustaPaga.confermato);

      // Nuove colonne additive: default documentati in database.dart, non
      // valori arbitrari né eccezioni per riga assente.
      expect(riga.tipo, TipoBustaPaga.mensile);
      expect(riga.competenze, isEmpty);
      expect(riga.permessiGodutiMese, closeTo(0.0, 0.001));
      expect(riga.exFestivitaMaturate, closeTo(0.0, 0.001));
      expect(riga.exFestivitaGodute, closeTo(0.0, 0.001));
      expect(riga.exFestivitaResidue, closeTo(0.0, 0.001));
      expect(riga.layout, 'job'); // default della colonna aggiunta in v7
    });

    test(
        'dopo la migrazione è possibile inserire una nuova riga con tutte '
        'le colonne, incluse quelle aggiunte in v4/v5/v6/v7', () async {
      seedSchemaV3();

      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);

      // Forza la migrazione prima di scrivere la nuova riga.
      await db.select(db.bustePagaTable).get();

      final nuovaBusta = BustaPaga(
        id: 'bp-nuova-2026-01',
        periodo: DateTime(2026, 1),
        lordo: 2500,
        netto: 1900,
        trattenute: const {'INPS': 200},
        straordinari: 4,
        ferieMaturate: 20,
        ferieGodute: 5,
        ferieResidue: 15,
        rolMaturati: 6,
        rolGoduti: 1,
        rolResidui: 5,
        permessiGoduti: 2,
        permessiGodutiMese: 1,
        exFestivitaMaturate: 3,
        exFestivitaGodute: 1,
        exFestivitaResidue: 2,
        oreLavorate: 168,
        competenze: const [
          VoceCompetenza(
            descrizione: 'Retribuzione ordinaria',
            quantita: null,
            importo: 2000,
          ),
        ],
        tipo: TipoBustaPaga.tredicesima,
        layout: 'altro',
      );

      await db
          .into(db.bustePagaTable)
          .insertOnConflictUpdate(nuovaBusta.toCompanion());

      final righe = await db.select(db.bustePagaTable).get();
      expect(righe, hasLength(2));

      final riletta = righe.firstWhere((r) => r.id == 'bp-nuova-2026-01');
      expect(riletta.tipo, TipoBustaPaga.tredicesima);
      expect(riletta.layout, 'altro');
      expect(riletta.competenze, hasLength(1));
      expect(riletta.exFestivitaMaturate, closeTo(3.0, 0.001));
    });
  });
}
