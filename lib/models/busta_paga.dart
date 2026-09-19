/// Stato di verifica di una busta paga inserita: in v1 (inserimento
/// manuale) è sempre `confermato`; il valore `daConfermare` resta previsto
/// per la Fase 3 (estrazione AI on-device), dove l'utente dovrà confermare
/// i campi estratti automaticamente prima che entrino in archivio.
enum StatoVerificaBustaPaga { daConfermare, confermato }

/// Tipo di mensilità rappresentata dalla busta paga. Rilevato automaticamente
/// dal testo del PDF durante l'import (parole "tredicesima"/"quattordicesima"
/// — vedi `BustaPagaRegexParser`), correggibile manualmente nel dettaglio.
/// Le buste con tipo diverso da `mensile` sono escluse dai grafici
/// Statistiche: netto/lordo/straordinari di una 13esima o 14esima sono
/// importi anomali rispetto al trend mensile, li distorcerebbero se messi in
/// linea con le mensilità normali.
enum TipoBustaPaga { mensile, tredicesima, quattordicesima }

/// Identificatore del layout PDF di default (software paghe "JOB"); usato
/// anche come default della colonna Drift `layout` per le buste già salvate.
const kLayoutPredefinito = 'job';

/// Singola voce di competenza (es. "Retribuzione ordinaria", "Edr
/// contrattuale", "Straordinario diurno (30%)") estratta dal PDF o inserita
/// manualmente nel form/dettaglio. `importo` è 0 quando la riga del PDF non
/// riporta un importo monetario associato (es. righe di sola quantità).
///
/// `quantita` è invece NULLABLE: `null` quando la riga del PDF non riporta
/// alcuna quantità (nessun tag GIORNI/ORE/RATEI, colonna quantità vuota —
/// es. "930 Trattamento integrativo DL 3/2020", "942 Somma integrativa"),
/// distinto da 0 stampato esplicitamente. Un "0" mostrato in UI per una riga
/// che in realtà non ha alcuna quantità (giorni/ore) è fuorviante ("zero
/// giorni/ore" invece di "nessuna quantità associata a questa voce") — va
/// mostrato come assente (un trattino), sia in sola lettura sia in editing,
/// vedi `BustaPagaCompetenzeSection`/`VoceCompetenzaEditRow`.
class VoceCompetenza {
  final String descrizione;
  final double? quantita;
  final double importo;

  const VoceCompetenza({
    required this.descrizione,
    required this.quantita,
    required this.importo,
  });
}

/// Una voce di competenza è considerata "straordinario" quando la sua
/// descrizione inizia (case-insensitive) con "straordinario" — usato sia dal
/// parser sia dalle schermate di editing per calcolare `straordinari` in ore
/// a partire dalla lista `competenze`, unica fonte di verità.
/// Sentinella privata usata da [BustaPaga.copyWith] per distinguere "il
/// chiamante non ha passato [BustaPaga.copyWith.fileOrigine]" da "il
/// chiamante vuole azzerarlo esplicitamente a `null`" — il pattern
/// `fileOrigine ?? this.fileOrigine` non permette quest'ultimo caso.
const _unset = Object();

bool voceEStraordinaria(String descrizione) =>
    descrizione.trim().toLowerCase().startsWith('straordinario');

/// Somma degli importi di tutte le voci di competenza: il "lordo" derivato,
/// da ricalcolare ad ogni salvataggio (vedi CLAUDE.md/istruzioni task) invece
/// di essere un campo editabile indipendente.
double computeLordo(List<VoceCompetenza> competenze) =>
    competenze.fold(0.0, (somma, voce) => somma + voce.importo);

/// Somma delle quantità (ore) delle voci di competenza "straordinario": lo
/// "straordinari" derivato, stessa logica di [computeLordo]. Una quantità
/// ASSENTE (vedi [VoceCompetenza.quantita]) conta come 0 nella somma — un
/// caso mai osservato per una voce di straordinario reale (sempre tag "ORE"
/// sul PDF), ma il tipo nullable del campo richiede comunque di gestirlo.
double computeStraordinari(List<VoceCompetenza> competenze) => competenze
    .where((voce) => voceEStraordinaria(voce.descrizione))
    .fold(0.0, (somma, voce) => somma + (voce.quantita ?? 0));

/// Il "netto" derivato: [lordo] meno la somma di tutte le [trattenute],
/// stessa logica di [computeLordo]/[computeStraordinari] — nessun clamp,
/// può risultare negativo se le trattenute superano il lordo (dato di
/// input incoerente da segnalare altrove, non da mascherare qui).
double computeNetto(double lordo, Map<String, double> trattenute) =>
    lordo - trattenute.values.fold(0.0, (somma, v) => somma + v);

/// Dati ricavabili da una busta paga. Nomi campo allineati 1:1 a
/// piano_progetto_finanze_personali.md §5 per rendere meccanica la futura
/// mappatura a tabella Drift (skill drift-migration / agent
/// drift-schema-architect) quando si passerà dalla persistenza in-memory
/// a SQLite.
class BustaPaga {
  final String id;
  final DateTime periodo;
  final String? fileOrigine;
  final double lordo;
  final double netto;
  final Map<String, double> trattenute;
  final double straordinari;
  final double ferieMaturate;
  final double ferieGodute;
  final double ferieResidue;
  final double rolMaturati;
  final double rolGoduti;
  final double rolResidui;
  final double permessiGoduti;

  /// Permessi riduz. orario goduti nel mese (in ore), distinti dal
  /// cumulativo annuo [permessiGoduti] (che coincide con i ROL goduti in
  /// questo layout busta paga). Campo scalare a sé, non fa parte di
  /// [competenze].
  final double permessiGodutiMese;

  /// Ex festività maturate/godute/residue (giorni festivi soppressi
  /// accantonati come banking di ore/giorni, stessa natura di Ferie/ROL —
  /// terza categoria della tabella ratei del PDF, vedi intestazione "FERIE /
  /// PERMESSI (R.O.L.) / EX FESTIVITA'"). Default 0 per retrocompatibilità
  /// con le buste paga salvate prima dell'introduzione di questi campi.
  final double exFestivitaMaturate;
  final double exFestivitaGodute;
  final double exFestivitaResidue;

  final double oreLavorate;

  /// Voci di competenza individuali (es. Retribuzione ordinaria, Edr
  /// contrattuale, Straordinario per fascia). Vuota di default per
  /// retrocompatibilità con le buste paga salvate prima dell'introduzione di
  /// questo campo. [lordo]/[straordinari]/[netto] restano colonne
  /// memorizzate, ricalcolate rispettivamente da questa lista e da
  /// [trattenute] al momento del salvataggio (vedi
  /// `computeLordo`/`computeStraordinari`/`computeNetto`), non getter
  /// derivati al volo.
  final List<VoceCompetenza> competenze;

  final StatoVerificaBustaPaga statoVerifica;
  final TipoBustaPaga tipo;

  const BustaPaga({
    required this.id,
    required this.periodo,
    this.fileOrigine,
    required this.lordo,
    required this.netto,
    required this.trattenute,
    required this.straordinari,
    required this.ferieMaturate,
    required this.ferieGodute,
    required this.ferieResidue,
    required this.rolMaturati,
    required this.rolGoduti,
    required this.rolResidui,
    required this.permessiGoduti,
    this.permessiGodutiMese = 0,
    this.exFestivitaMaturate = 0,
    this.exFestivitaGodute = 0,
    this.exFestivitaResidue = 0,
    required this.oreLavorate,
    this.competenze = const [],
    this.statoVerifica = StatoVerificaBustaPaga.confermato,
    this.tipo = TipoBustaPaga.mensile,
  });

  BustaPaga copyWith({
    String? id,
    DateTime? periodo,
    Object? fileOrigine = _unset,
    double? lordo,
    double? netto,
    Map<String, double>? trattenute,
    double? straordinari,
    double? ferieMaturate,
    double? ferieGodute,
    double? ferieResidue,
    double? rolMaturati,
    double? rolGoduti,
    double? rolResidui,
    double? permessiGoduti,
    double? permessiGodutiMese,
    double? exFestivitaMaturate,
    double? exFestivitaGodute,
    double? exFestivitaResidue,
    double? oreLavorate,
    List<VoceCompetenza>? competenze,
    StatoVerificaBustaPaga? statoVerifica,
    TipoBustaPaga? tipo,
  }) {
    return BustaPaga(
      id: id ?? this.id,
      periodo: periodo ?? this.periodo,
      fileOrigine: identical(fileOrigine, _unset)
          ? this.fileOrigine
          : fileOrigine as String?,
      lordo: lordo ?? this.lordo,
      netto: netto ?? this.netto,
      trattenute: trattenute ?? this.trattenute,
      straordinari: straordinari ?? this.straordinari,
      ferieMaturate: ferieMaturate ?? this.ferieMaturate,
      ferieGodute: ferieGodute ?? this.ferieGodute,
      ferieResidue: ferieResidue ?? this.ferieResidue,
      rolMaturati: rolMaturati ?? this.rolMaturati,
      rolGoduti: rolGoduti ?? this.rolGoduti,
      rolResidui: rolResidui ?? this.rolResidui,
      permessiGoduti: permessiGoduti ?? this.permessiGoduti,
      permessiGodutiMese: permessiGodutiMese ?? this.permessiGodutiMese,
      exFestivitaMaturate: exFestivitaMaturate ?? this.exFestivitaMaturate,
      exFestivitaGodute: exFestivitaGodute ?? this.exFestivitaGodute,
      exFestivitaResidue: exFestivitaResidue ?? this.exFestivitaResidue,
      oreLavorate: oreLavorate ?? this.oreLavorate,
      competenze: competenze ?? this.competenze,
      statoVerifica: statoVerifica ?? this.statoVerifica,
      tipo: tipo ?? this.tipo,
    );
  }
}
