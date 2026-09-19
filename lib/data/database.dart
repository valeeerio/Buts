import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import '../models/busta_paga.dart';

part 'database.g.dart';

/// Serializza/deserializza la mappa `trattenute` (nome trattenuta -> importo)
/// come JSON in una singola colonna testo.
///
/// Scelta architetturale: la mappa `trattenute` di una busta paga è un
/// dettaglio informativo a bassa cardinalità (poche voci per riga, es. INPS/
/// IRPEF/Addizionali), non interrogata singolarmente altrove nell'app (non
/// servono query tipo "somma di IRPEF nel tempo" in v1 — le statistiche
/// previste in piano_progetto_finanze_personali.md §3.5/§5 sono su
/// netto/lordo/ferie/ROL/permessi/ore, non sulle singole trattenute). Una
/// tabella figlia normalizzata (`TrattenutaBustaPaga(bustaPagaId, nome,
/// importo)`) sarebbe più "corretta" relazionalmente ma aggiungerebbe join e
/// gestione transazionale per un beneficio che oggi non serve. Il piano di
/// progetto stesso descrive il campo come `trattenute (json)` (§5). Se in
/// futuro servissero query/aggregazioni sulle singole trattenute, migrare a
/// tabella figlia con una migrazione dedicata.
class TrattenuteConverter extends TypeConverter<Map<String, double>, String> {
  const TrattenuteConverter();

  @override
  Map<String, double> fromSql(String fromDb) {
    if (fromDb.isEmpty) return const {};
    final decoded = jsonDecode(fromDb) as Map<String, dynamic>;
    return decoded
        .map((key, value) => MapEntry(key, (value as num).toDouble()));
  }

  @override
  String toSql(Map<String, double> value) => jsonEncode(value);
}

/// Serializza/deserializza la lista `competenze` (voci di competenza
/// individuali, es. Retribuzione ordinaria/Edr contrattuale/Straordinario)
/// come JSON in una singola colonna testo. Stessa motivazione architetturale
/// di [TrattenuteConverter]: bassa cardinalità, nessuna query prevista sulle
/// singole voci in v1.
class VoceCompetenzaListConverter
    extends TypeConverter<List<VoceCompetenza>, String> {
  const VoceCompetenzaListConverter();

  @override
  List<VoceCompetenza> fromSql(String fromDb) {
    if (fromDb.isEmpty) return const [];
    final decoded = jsonDecode(fromDb) as List<dynamic>;
    return decoded
        .map((e) => e as Map<String, dynamic>)
        .map((e) => VoceCompetenza(
              descrizione: e['descrizione'] as String,
              // `num?` (non `num`): righe scritte da questo fix in avanti
              // possono avere `quantita: null` nel JSON (vedi
              // `VoceCompetenza.quantita`, ora nullable) — le righe scritte
              // PRIMA di questo fix hanno sempre un numero reale (mai
              // `null`, il vecchio bug scriveva 0 anche per una quantità
              // assente), quindi restano compatibili e continuano a
              // leggersi identiche a prima (nessun dato esistente perso o
              // alterato).
              quantita: (e['quantita'] as num?)?.toDouble(),
              importo: (e['importo'] as num).toDouble(),
            ))
        .toList();
  }

  @override
  String toSql(List<VoceCompetenza> value) => jsonEncode(value
      .map((v) => {
            'descrizione': v.descrizione,
            'quantita': v.quantita,
            'importo': v.importo,
          })
      .toList());
}

/// Tabella Drift per l'archivio Buste Paga. Colonne allineate 1:1 al modello
/// di dominio `BustaPaga` (lib/models/busta_paga.dart) e al modello dati di
/// piano_progetto_finanze_personali.md §5.
class BustePagaTable extends Table {
  /// id applicativo (stringa) generato lato Dart, non autoincrement: mantiene
  /// coerenza con gli id già usati dal modello di dominio/mock esistenti
  /// (es. 'bp-2026-05') e semplifica il mapping da/verso `BustaPaga`.
  TextColumn get id => text()();
  DateTimeColumn get periodo => dateTime()();
  TextColumn get fileOrigine => text().nullable()();
  RealColumn get lordo => real()();
  RealColumn get netto => real()();

  /// Mappa nome trattenuta -> importo, serializzata come JSON. Vedi
  /// [TrattenuteConverter] per la motivazione della scelta.
  TextColumn get trattenute => text()
      .map(const TrattenuteConverter())
      .withDefault(const Constant('{}'))();

  RealColumn get straordinari => real()();
  RealColumn get ferieMaturate => real()();
  RealColumn get ferieGodute => real()();
  RealColumn get ferieResidue => real()();
  RealColumn get rolMaturati => real()();
  RealColumn get rolGoduti => real()();
  RealColumn get rolResidui => real()();
  RealColumn get permessiGoduti => real()();

  /// Permessi riduz. orario goduti nel mese (in ore), distinti dal
  /// cumulativo annuo `permessiGoduti` — vedi `BustaPaga.permessiGodutiMese`.
  /// Default 0 per compatibilità con le righe esistenti create prima
  /// dell'introduzione di questo campo (v4 -> v5).
  RealColumn get permessiGodutiMese => real().withDefault(const Constant(0))();

  /// Ex festività maturate/godute/residue — vedi `BustaPaga.exFestivitaMaturate`
  /// e affini. Default 0 per compatibilità con le righe esistenti create
  /// prima dell'introduzione di questi campi (v5 -> v6).
  RealColumn get exFestivitaMaturate => real().withDefault(const Constant(0))();
  RealColumn get exFestivitaGodute => real().withDefault(const Constant(0))();
  RealColumn get exFestivitaResidue => real().withDefault(const Constant(0))();

  RealColumn get oreLavorate => real()();

  /// Voci di competenza individuali, serializzate come JSON. Vedi
  /// [VoceCompetenzaListConverter]. Default lista vuota per compatibilità con
  /// le righe esistenti create prima dell'introduzione di questo campo
  /// (v4 -> v5).
  TextColumn get competenze => text()
      .map(const VoceCompetenzaListConverter())
      .withDefault(const Constant('[]'))();

  /// Stato di verifica (v1: sempre `confermato`, inserimento manuale; il
  /// valore `daConfermare` è predisposto per la Fase 3 AI on-device — vedi
  /// StatoVerificaBustaPaga).
  IntColumn get statoVerifica => intEnum<StatoVerificaBustaPaga>().withDefault(
        Constant(StatoVerificaBustaPaga.confermato.index),
      )();

  /// Tipo mensilità (mensile/13esima/14esima) — vedi `TipoBustaPaga`.
  /// Default `mensile` per compatibilità con le righe esistenti create
  /// prima dell'introduzione di questo campo (v3 -> v4).
  IntColumn get tipo => intEnum<TipoBustaPaga>().withDefault(
        Constant(TipoBustaPaga.mensile.index),
      )();

  /// Layout PDF da cui la busta è stata importata (vedi `PayslipLayout.id`).
  /// Default `job` per compatibilità con le righe create prima di v7.
  TextColumn get layout =>
      text().withDefault(const Constant(kLayoutPredefinito))();

  @override
  Set<Column> get primaryKey => {id};
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'buts.sqlite'));
    return NativeDatabase.createInBackground(
      file,
      setup: (database) {
        // Assicura il binding nativo sqlite3 corretto anche su iOS/Android
        // via sqlite3_flutter_libs (necessario per NativeDatabase).
        applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
      },
    );
  });
}

@DriftDatabase(tables: [
  BustePagaTable,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Costruttore per i test, che permette di iniettare una connessione
  /// in-memory (es. `NativeDatabase.memory()`).
  AppDatabase.forTesting(super.connection);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          // v2 -> v3: pivot di prodotto, l'app si concentra esclusivamente
          // su Buste Paga (vedi CLAUDE.md). Le 4 aree di budget e le relative
          // tabelle (introdotte in v1 -> v2, mai rilasciate) non fanno più
          // parte dello schema: chi arriva da v1/v2 le droppa qui via SQL
          // diretto (`IF EXISTS`, dato che uno schema v1 non le ha mai
          // create), così non restano tabelle orfane nel DB locale.
          // `BustePagaTable` resta invariata, nessun dato dell'archivio
          // buste paga viene toccato.
          if (from < 3) {
            await m.database
                .customStatement('DROP TABLE IF EXISTS movimento_area_table');
            await m.database
                .customStatement('DROP TABLE IF EXISTS voce_ricorrente_table');
            await m.database
                .customStatement('DROP TABLE IF EXISTS mese_budget_table');
            await m.database.customStatement('DROP TABLE IF EXISTS area_table');
          }
          // v3 -> v4: nuova colonna `tipo` (mensile/13esima/14esima, vedi
          // TipoBustaPaga) — migrazione additiva, le righe esistenti
          // ricevono il default `mensile` dichiarato sulla colonna, nessun
          // dato esistente viene toccato o perso.
          if (from < 4) {
            await m.addColumn(bustePagaTable, bustePagaTable.tipo);
          }
          // v4 -> v5: nuove colonne `competenze` (voci di competenza
          // individuali, vedi VoceCompetenza/VoceCompetenzaListConverter) e
          // `permessiGodutiMese` (riga "Permessi riduz. orario goduti" del
          // mese, distinta dal cumulativo annuo `permessiGoduti`) —
          // migrazione additiva, le righe esistenti ricevono i default
          // dichiarati sulle colonne ('[]' e 0), nessun dato esistente viene
          // toccato o perso.
          if (from < 5) {
            await m.addColumn(bustePagaTable, bustePagaTable.competenze);
            await m.addColumn(
                bustePagaTable, bustePagaTable.permessiGodutiMese);
          }
          // v5 -> v6: nuove colonne `exFestivitaMaturate`/`exFestivitaGodute`/
          // `exFestivitaResidue` (terza categoria di ratei del PDF, "EX
          // FESTIVITA'", stessa struttura maturato/goduto/residuo di
          // Ferie/ROL — vedi BustaPaga.exFestivitaMaturate) — migrazione
          // additiva, le righe esistenti ricevono il default 0 dichiarato
          // sulle colonne, nessun dato esistente viene toccato o perso.
          if (from < 6) {
            await m.addColumn(
                bustePagaTable, bustePagaTable.exFestivitaMaturate);
            await m.addColumn(bustePagaTable, bustePagaTable.exFestivitaGodute);
            await m.addColumn(
                bustePagaTable, bustePagaTable.exFestivitaResidue);
          }
          // v6 -> v7: nuova colonna `layout` (layout PDF di origine, vedi
          // PayslipLayout) — migrazione additiva, le righe esistenti
          // ricevono il default 'job', nessun dato esistente toccato.
          if (from < 7) {
            await m.addColumn(bustePagaTable, bustePagaTable.layout);
          }
        },
      );
}

/// Mapping tra la riga Drift generata (`BustePagaTableData`) e il modello di
/// dominio `BustaPaga` usato dal resto dell'app (UI, provider). Mantiene la
/// classe generata da Drift come dettaglio di questo layer di persistenza.
extension BustaPagaRowMapping on BustePagaTableData {
  BustaPaga toDomain() {
    return BustaPaga(
      id: id,
      periodo: periodo,
      fileOrigine: fileOrigine,
      lordo: lordo,
      netto: netto,
      trattenute: trattenute,
      straordinari: straordinari,
      ferieMaturate: ferieMaturate,
      ferieGodute: ferieGodute,
      ferieResidue: ferieResidue,
      rolMaturati: rolMaturati,
      rolGoduti: rolGoduti,
      rolResidui: rolResidui,
      permessiGoduti: permessiGoduti,
      permessiGodutiMese: permessiGodutiMese,
      exFestivitaMaturate: exFestivitaMaturate,
      exFestivitaGodute: exFestivitaGodute,
      exFestivitaResidue: exFestivitaResidue,
      oreLavorate: oreLavorate,
      competenze: competenze,
      statoVerifica: statoVerifica,
      tipo: tipo,
      layout: layout,
    );
  }
}

extension BustaPagaDomainMapping on BustaPaga {
  BustePagaTableCompanion toCompanion() {
    return BustePagaTableCompanion.insert(
      id: id,
      periodo: periodo,
      fileOrigine: Value(fileOrigine),
      lordo: lordo,
      netto: netto,
      trattenute: Value(trattenute),
      straordinari: straordinari,
      ferieMaturate: ferieMaturate,
      ferieGodute: ferieGodute,
      ferieResidue: ferieResidue,
      rolMaturati: rolMaturati,
      rolGoduti: rolGoduti,
      rolResidui: rolResidui,
      permessiGoduti: permessiGoduti,
      permessiGodutiMese: Value(permessiGodutiMese),
      exFestivitaMaturate: Value(exFestivitaMaturate),
      exFestivitaGodute: Value(exFestivitaGodute),
      exFestivitaResidue: Value(exFestivitaResidue),
      oreLavorate: oreLavorate,
      competenze: Value(competenze),
      statoVerifica: Value(statoVerifica),
      tipo: Value(tipo),
      layout: Value(layout),
    );
  }
}
