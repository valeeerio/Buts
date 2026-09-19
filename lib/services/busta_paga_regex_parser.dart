/// Estrazione automatica dei campi di [BustaPaga] da testo PDF (output di
/// [PdfImportService]) tramite pattern regex mirati al layout del software
/// payroll "JOB" (Sistemi S.p.A.) — non un parser generico per qualunque
/// busta paga italiana.
///
/// Il testo estratto da `syncfusion_flutter_pdf` per questo layout non
/// rispecchia l'ordine visivo della tabella (celle su colonne diverse
/// finiscono concatenate senza separatore). I pattern sotto sono stati
/// derivati manualmente confrontando 3 buste paga reali dello stesso
/// software, sfruttando regolarità strutturali stabili:
/// - le quantità hanno sempre 3 decimali ("22,000"), le tariffe orarie 5
///   decimali ("69,65818"), gli importi 2 decimali ("1.532,48") — questo
///   evita ambiguità nel separare numeri concatenati senza spazi;
/// - il blocco "ratei" (ferie/ROL/ex festività) usa i tag letterali
///   "(GIORNI)"/"(ORE)" come ancore non numeriche per delimitare i 3
///   blocchi (Ferie/ROL/Ex festività) sui cui cercare un numero VARIABILE
///   di valori (2-4, a seconda di quali celle il cedolino lascia vuote quel
///   mese invece di stampare "0,00" — vedi `_interpretaBloccoRatei`),
///   invece di pretendere un conteggio fisso.
///
/// Se il layout del software payroll cambia, questi pattern smettono di
/// funzionare silenziosamente (ritornano `null`/campi a 0) — è un limite
/// noto e accettato: l'alternativa (LLM locale) è stata valutata e scartata
/// per ora, vedi BACKLOG.md.
///
/// Per ferie/ROL/ex festività esiste anche una fonte alternativa, più
/// affidabile quando disponibile: [RateiEstrattiDaCoordinate], letta da
/// `PdfImportService` per COORDINATE (X/Y) dalla pagina invece che dal
/// testo linearizzato di cui sopra — quest'ultimo perde l'allineamento a
/// colonna della tabella "RATEI" (celle vuote che spariscono, numeri di
/// colonne diverse che finiscono incollati senza separatore), mentre la
/// posizione di ogni numero sulla pagina resta univoca. Passata come
/// argomento opzionale a [BustaPagaRegexParser.parse]: se presente ha
/// priorità sul percorso testuale sopra descritto, categoria per categoria.
///
/// Analogamente, per competenze/lordo/trattenute/netto esiste
/// [VociEstratteDaCoordinate]: voci della tabella
/// "VOCE/DESCRIZIONE/.../TRATTENUTE/COMPETENZE", contributi C/DIPENDENTE,
/// trattenuta IRPEF e riga totali, letti anch'essi per COORDINATE dalla
/// stessa pagina invece che dal testo linearizzato — che qui perde la
/// distinzione fra le colonne TRATTENUTE e COMPETENZE (concatenate senza
/// separatore riconoscibile), oltre a non leggere affatto le righe prive di
/// tag GIORNI/ORE/RATEI (es. "930 Trattamento integrativo DL 3/2020").
/// Passata come terzo argomento opzionale a [BustaPagaRegexParser.parse]:
/// quando [VociEstratteDaCoordinate.haDatiSufficienti], ha priorità sul
/// percorso testuale per questi campi — a differenza di
/// [RateiEstrattiDaCoordinate] qui la scelta è tutto-o-niente, non per
/// singolo campo (vedi doc su [VociEstratteDaCoordinate.haDatiSufficienti]
/// per il perché).
library;

import '../models/busta_paga.dart';

class BustaPagaEstratti {
  final String? periodo; // formato YYYY-MM
  final double? lordo;
  final double? netto;
  final Map<String, double> trattenute;
  final double straordinari;
  final double ferieMaturate;
  final double ferieGodute;
  final double ferieResidue;
  final double rolMaturati;
  final double rolGoduti;
  final double rolResidui;
  final double permessiGoduti;

  /// Permessi riduz. orario goduti nel mese — vedi
  /// `BustaPaga.permessiGodutiMese`.
  final double permessiGodutiMese;

  /// Ex festività maturate/godute/residue — vedi
  /// `BustaPaga.exFestivitaMaturate` e affini.
  final double exFestivitaMaturate;
  final double exFestivitaGodute;
  final double exFestivitaResidue;

  final double? oreLavorate;

  /// Voci di competenza individuali estratte dal PDF (vedi
  /// [BustaPagaRegexParser._rigaVoceCompetenza]).
  final List<VoceCompetenza> competenze;

  /// Tipo mensilità (mensile/13esima/14esima), rilevato cercando le parole
  /// "tredicesima"/"quattordicesima" nel testo del PDF — sempre valorizzato
  /// (default `mensile` se non trovate), a differenza degli altri campi che
  /// possono mancare.
  final TipoBustaPaga tipo;

  /// Campi che il parser non è riuscito a determinare con sufficiente
  /// confidenza (es. "netto", "ore lavorate stimate") — da mostrare
  /// all'utente come promemoria di verifica manuale.
  final List<String> warnings;

  /// `true` solo quando il lordo è stato letto dal percorso a coordinate
  /// ([VociEstratteDaCoordinate]) E il controllo aritmetico contro il totale
  /// competenze stampato sul PDF è tornato positivo (nessuna divergenza oltre
  /// la tolleranza) — vedi `BustaPagaRegexParser.parse`. Sempre `false` sul
  /// percorso testuale.
  final bool lordoVerificato;

  /// `true` solo quando le trattenute sono state lette dal percorso a
  /// coordinate E sia l'IRPEF sia il totale trattenute sono stati letti e
  /// riconciliati correttamente (vedi `_trattenuteDaCoordinate`). Sempre
  /// `false` sul percorso testuale.
  final bool trattenuteVerificate;

  /// `true` solo quando [lordoVerificato] e [trattenuteVerificate] sono
  /// entrambi `true` E il netto derivato coincide (entro tolleranza) col
  /// netto in busta stampato sul PDF. Sempre `false` sul percorso testuale.
  final bool nettoVerificato;

  /// Identificatore del layout PDF che ha prodotto questi dati (vedi
  /// `PayslipLayout.id`); persistito in `BustaPaga.layout`.
  final String layoutId;

  const BustaPagaEstratti({
    this.periodo,
    this.lordo,
    this.netto,
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
    this.oreLavorate,
    this.competenze = const [],
    this.tipo = TipoBustaPaga.mensile,
    required this.warnings,
    this.lordoVerificato = false,
    this.trattenuteVerificate = false,
    this.nettoVerificato = false,
    this.layoutId = kLayoutPredefinito,
  });

  /// Copia identica a questa ma con [layoutId] diverso (lo usa il registro
  /// dei layout per stampare l'id del layout che ha prodotto i dati).
  BustaPagaEstratti conLayoutId(String id) => BustaPagaEstratti(
        periodo: periodo,
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
        tipo: tipo,
        warnings: warnings,
        lordoVerificato: lordoVerificato,
        trattenuteVerificate: trattenuteVerificate,
        nettoVerificato: nettoVerificato,
        layoutId: id,
      );
}

/// Un singolo rateo (maturato/goduto/residuo, più l'eventuale residuo
/// dell'anno precedente) di una delle 3 categorie della tabella "RATEI" del
/// PDF (Ferie / Permessi R.O.L. / Ex festività), letto per COORDINATE (X/Y)
/// dalla pagina invece che dal testo linearizzato — vedi doc di libreria in
/// testa al file, [RateiEstrattiDaCoordinate] e l'uso in
/// [BustaPagaRegexParser.parse].
///
/// Ogni campo è singolarmente nullable: `null` significa "cella non
/// determinata con sufficiente confidenza" (colonna/riga non riconosciuta
/// nel documento), non "letta e zero" — un cedolino lascia scritto "0,00"
/// solo per alcune celle, altre le lascia proprio vuote: la lettura per
/// coordinate distingue correttamente "cella vuota = 0" da "colonna non
/// trovata affatto = dato mancante", a differenza del percorso testuale.
class RateoCategoria {
  /// "RESIDUI A.P." — residuo dell'anno precedente: solo un dato
  /// intermedio per la verifica di bilancio in [BustaPagaRegexParser.parse]
  /// (mai esposto in [BustaPagaEstratti]/`BustaPaga`).
  final double? residuoAnnoPrecedente;
  final double? maturato;

  /// Somma delle due sotto-colonne "GODUTI A.P." e "GODUTI A.C." della
  /// tabella (vedi intestazione "GODUTI" sopra "A.P."/"A.C." nel PDF):
  /// `null` solo se NESSUNA delle due sotto-colonne è stata letta, non se
  /// una delle due manca (in quel caso la mancante conta come 0 nella
  /// somma).
  final double? goduto;
  final double? residuo;

  const RateoCategoria({
    this.residuoAnnoPrecedente,
    this.maturato,
    this.goduto,
    this.residuo,
  });

  /// Nessun campo determinato — equivalente a "riga di categoria non
  /// trovata nella tabella" (etichetta assente o pagina non riconosciuta),
  /// il default di [RateiEstrattiDaCoordinate] per ciascuna categoria.
  static const vuoto = RateoCategoria();

  /// `true` se almeno un campo è stato letto — usato da
  /// [BustaPagaRegexParser.parse] per decidere se questa categoria ha dati
  /// per coordinate da preferire al percorso testuale, oppure se ricadere
  /// su quest'ultimo.
  bool get haAlmenoUnValore =>
      residuoAnnoPrecedente != null ||
      maturato != null ||
      goduto != null ||
      residuo != null;
}

/// Ratei (Ferie, Permessi R.O.L., Ex festività) letti per coordinate dalla
/// tabella "RATEI" del PDF (vedi `PdfImportService`), passati come input
/// OPZIONALE a [BustaPagaRegexParser.parse]: quando una categoria ha
/// [RateoCategoria.haAlmenoUnValore], è la fonte autoritativa per quella
/// categoria; altrimenti [BustaPagaRegexParser.parse] ricade sul percorso
/// testuale per quella categoria. Non passare questo argomento a `parse`
/// (default `null`) lascia il comportamento esattamente com'era prima
/// dell'introduzione di questo tipo: solo testo.
class RateiEstrattiDaCoordinate {
  final RateoCategoria ferie;
  final RateoCategoria rol;
  final RateoCategoria exFestivita;

  const RateiEstrattiDaCoordinate({
    this.ferie = RateoCategoria.vuoto,
    this.rol = RateoCategoria.vuoto,
    this.exFestivita = RateoCategoria.vuoto,
  });
}

/// Colonna della tabella "VOCE / DESCRIZIONE / ... / TRATTENUTE / COMPETENZE"
/// in cui è stampato l'importo di una riga, letta per COORDINATE (X) — vedi
/// [RigaVoceCoordinate].
enum ColonnaVoceCoordinate { trattenute, competenze }

/// Una singola riga della tabella voci del PDF (layout "JOB"), letta per
/// COORDINATE (X/Y) invece che dal testo linearizzato — vedi
/// [VociEstratteDaCoordinate] e `PdfImportService.classificaVociDaCoordinate`
/// (in `pdf_import_service.dart`) per il perché: il testo linearizzato perde
/// la distinzione fra le colonne TRATTENUTE e COMPETENZE (entrambe finiscono
/// concatenate senza un separatore riconoscibile), mentre la posizione X di
/// ogni importo sulla pagina resta univoca.
///
/// [flagN] riflette il flag "N" (colonna più a destra della tabella,
/// intestazione "N*" — legenda del PDF: "N - Considerato nel netto in
/// busta") stampato come "*" su questa riga: SOLO le righe con questo flag
/// entrano nel lordo/nelle trattenute (vedi uso in
/// [BustaPagaRegexParser.parse]) — alcune righe della colonna COMPETENZE sono
/// puramente informative (es. "Addizionale Regionale Dovuta", un dato
/// dell'anno precedente stampato per promemoria) e non vanno sommate,
/// distinguibili SOLO tramite questo flag — non esiste un prefisso testuale
/// affidabile della descrizione per escluderle, a differenza di "Ferie
/// godute"/"Permessi riduz." sul percorso testuale.
class RigaVoceCoordinate {
  final String codice;
  final String descrizione;

  /// Tag letterale della riga ("GIORNI"/"ORE"/"RATEI"), se presente — righe
  /// come "930 Trattamento integrativo DL 3/2020" non hanno alcun tag (né
  /// quantità), a differenza delle righe "ordinarie" del cedolino.
  final String? tag;

  /// Quantità (colonna "Quantita'"), `null` quando la riga non ne stampa
  /// alcuna (righe senza tag, vedi [tag] — es. "930 Trattamento integrativo
  /// DL 3/2020") — distinto da 0 stampato esplicitamente, propagato così
  /// com'è in [VoceCompetenza.quantita] (vedi [BustaPagaRegexParser
  /// ._competenzeDaCoordinate]).
  final double? quantita;

  /// Importo della riga, dalla colonna [colonna].
  final double importo;
  final ColonnaVoceCoordinate colonna;
  final bool flagN;

  /// `true` quando la riga aveva un valore letto SIA in colonna TRATTENUTE
  /// SIA in colonna COMPETENZE (caso anomalo/inatteso, mai osservato sui PDF
  /// di riferimento): in quel caso [colonna]/[importo] riflettono solo la
  /// colonna COMPETENZE (data la precedenza), l'altro valore è scartato —
  /// vedi il warning aggiunto da [BustaPagaRegexParser.parse] quando questo
  /// flag è `true`, così l'ambiguità non passa inosservata.
  final bool entrambeColonneValorizzate;

  const RigaVoceCoordinate({
    required this.codice,
    required this.descrizione,
    this.tag,
    required this.quantita,
    required this.importo,
    required this.colonna,
    required this.flagN,
    this.entrambeColonneValorizzate = false,
  });
}

/// Riga totali del cedolino (fondo della prima pagina, dopo "Firma per
/// quietanza"): TOTALE COMPETENZE / TOTALE TRATTENUTE / ARR. PRECED. /
/// ARR. ATTUALE / NETTO IN BUSTA, letta per COORDINATE — usata sia come
/// fonte diretta del netto sia come riferimento per la verifica incrociata
/// contro i valori ricalcolati dalle singole righe (vedi
/// [BustaPagaRegexParser.parse]).
///
/// Identità verificata su PDF reali (sempre esatta, mai un'approssimazione):
/// `nettoInBusta == totaleCompetenze - totaleTrattenute - arrPreced + arrAttuale`.
class TotaliCoordinate {
  final double totaleCompetenze;
  final double totaleTrattenute;

  /// Differenza di arrotondamento riportata dal mese precedente/al mese
  /// attuale — pochi centesimi, 0 quando il cedolino non la stampa quel mese
  /// (cella assente quel mese, non "0,00" stampato — a differenza di
  /// [RateoCategoria] non serve distinguere le due cose per questi due
  /// campi: l'assenza è comunque 0 ai fini del calcolo del netto).
  final double arrPreced;
  final double arrAttuale;
  final double nettoInBusta;

  const TotaliCoordinate({
    required this.totaleCompetenze,
    required this.totaleTrattenute,
    this.arrPreced = 0,
    this.arrAttuale = 0,
    required this.nettoInBusta,
  });
}

/// Voci del cedolino (tabella "VOCE/DESCRIZIONE/.../TRATTENUTE/COMPETENZE",
/// contributi C/DIPENDENTE, IRPEF trattenuta, riga totali) lette per
/// COORDINATE dalla prima pagina del PDF — vedi
/// `PdfImportService.classificaVociDaCoordinate` e la doc di libreria in
/// testa al file. Passata come argomento OPZIONALE a
/// [BustaPagaRegexParser.parse]: quando [haDatiSufficienti], è la fonte
/// preferita per competenze/trattenute/lordo/netto, altrimenti
/// [BustaPagaRegexParser.parse] ricade sul percorso testuale per questi
/// campi (a differenza di [RateiEstrattiDaCoordinate], qui la scelta è
/// tutto-o-niente e non per singola categoria: competenze/trattenute/netto
/// sono troppo interdipendenti — in particolare la verifica aritmetica
/// Σtrattenute==TOTALE TRATTENUTE — perché abbia senso mescolare fonti
/// diverse campo per campo).
class VociEstratteDaCoordinate {
  final List<RigaVoceCoordinate> righe;

  /// Quota C/DIPENDENTE di ciascun contributo (INPS, CONTRIBUTO EBILOG,
  /// FONDO INTEGR. SALARIALE - FIS, ecc.), chiave = descrizione del
  /// contributo così come stampata sul PDF. La quota C/DITTA (a carico del
  /// datore di lavoro, MAI una trattenuta del dipendente) non è mai inclusa
  /// qui — vedi `PdfImportService.classificaVociDaCoordinate`.
  final Map<String, double> contributiDipendente;

  /// Trattenuta IRPEF (riga "IRPEF + IMP. SOST."), `null` se non
  /// riconosciuta.
  final double? irpefTrattenuta;

  /// Riga totali, `null` se non riconosciuta.
  final TotaliCoordinate? totali;

  const VociEstratteDaCoordinate({
    this.righe = const [],
    this.contributiDipendente = const {},
    this.irpefTrattenuta,
    this.totali,
  });

  /// `true` quando ci sono abbastanza dati per preferire questo percorso al
  /// testo linearizzato: almeno una riga di voce E la riga totali (serve da
  /// riferimento per la verifica aritmetica di
  /// [BustaPagaRegexParser.parse] — senza di essa non c'è modo di sapere se
  /// le righe lette bastano a ricostruire correttamente lordo/trattenute).
  bool get haDatiSufficienti => righe.isNotEmpty && totali != null;
}

class BustaPagaRegexParser {
  const BustaPagaRegexParser();

  static const _mesi = {
    'gennaio': 1,
    'febbraio': 2,
    'marzo': 3,
    'aprile': 4,
    'maggio': 5,
    'giugno': 6,
    'luglio': 7,
    'agosto': 8,
    'settembre': 9,
    'ottobre': 10,
    'novembre': 11,
    'dicembre': 12,
  };

  // Riga unificata di una voce di competenza (Retribuzione ordinaria, Edr
  // contrattuale, Straordinario per fascia, ecc.): descrizione in chiaro,
  // seguita dal tag "GIORNI"/"ORE", seguita dalla quantità (3 decimali) ed
  // eventualmente da tariffa (2-5 decimali, scartata) e importo (2 decimali,
  // con eventuale separatore delle migliaia "."). Tollerante a whitespace
  // generico (spazi O newline, `\s*`/`\s+`) tra questi elementi: verificato
  // che il testo reale estratto da `syncfusion_flutter_pdf` per questo
  // layout separa descrizione/tag/quantità con newline (CRLF), ma la
  // regex non fa più affidamento su un newline letterale per restare
  // robusta anche se il layout linearizza diversamente in altri casi. Il
  // gruppo descrizione (`[^\n]+?`, non-greedy) è generico — cattura
  // qualunque testo fino al tag GIORNI/ORE più vicino sulla stessa riga —
  // e validato sul campione di PDF reali disponibile: potrebbe richiedere
  // aggiustamenti su layout mai visti finora. Il segno "-" davanti
  // all'importo è opzionale (a differenza di quantità/tariffa, che non sono
  // mai negative): un conguaglio/storno a debito nel cedolino può comparire
  // come voce di competenza con importo negativo, e va propagato in
  // `VoceCompetenza.importo` così com'è — scartarlo (come accadeva prima)
  // invertirebbe silenziosamente il suo effetto in `computeLordo`.
  static final _rigaVoceCompetenza = RegExp(
    r'([^\n]+?)\s*(?:GIORNI|ORE)\s*(\d+,\d{3})'
    r'(?:\s+[\d.]+,\d{2,5}\s+(-?[\d.]+,\d{2}))?',
  );

  // Variante del pattern sopra per le mensilità supplementari (13esima/
  // 14esima): verificato su un PDF reale ("Mens.supplementare 6/2026") che il
  // blocco competenze di questo layout non usa il tag "GIORNI"/"ORE" ma il
  // tag letterale "RATEI", seguito direttamente da quantità (3 decimali) e
  // importo (2 decimali) SENZA il campo tariffa intermedio presente nel
  // formato mensile (nessun terzo numero da scartare tra i due). Osservato un
  // solo rateo per documento finora ("14.ma mensilita'", 11,000 mesi
  // maturati, 1.404,77 di importo) ma il pattern è generico/ripetibile come
  // `_rigaVoceCompetenza` nel caso un domani un cedolino ne stampi più di
  // uno. Il tag "RATEI" compare anche da solo nell'intestazione della
  // tabella ratei più in alto nel documento (colonna "RATEI" della tabella
  // Ferie/ROL/Ex festività): non produce un match spurio perché lì non è
  // seguito da una quantità a 3 decimali, condizione richiesta da questa
  // regex.
  static final _rigaVoceCompetenzaSupplementare = RegExp(
    r'([^\n]+?)\s*RATEI\s*(\d+,\d{3})\s+(-?[\d.]+,\d{2})',
  );

  // Descrizioni (confronto case-insensitive, su prefisso trimmato) escluse
  // da `competenze`: le righe Ferie/Permessi sono già modellate altrove
  // (tabella Maturazioni, `permessiGodutiMese`) e non vanno duplicate qui,
  // pur avendo la stessa struttura sintattica di una riga di competenza.
  static const _descrizioniEscluseDaCompetenze = [
    'ferie godute',
    'permessi riduz',
  ];

  static final _rigaPermessiMese = RegExp(
    r'Permessi\s+riduz\.?\s*orario\s+goduti[^\n]*\n\s*(?:ORE|GIORNI)\s*\n\s*(\d+,\d{3})',
  );

  // Percorso testuale di fallback per ferie/ROL/ex festività (usato quando
  // `ratei` — lettura per coordinate, vedi doc di libreria in testa al file
  // — non è fornito o non ha dati per una categoria). I tre blocchi sono
  // delimitati dai tag letterali "(GIORNI)" (chiude Ferie) e "(ORE)" (chiude
  // ROL il primo, Ex festività il secondo) — cercati con `indexOf` semplice
  // sulle STRINGHE, non con una regex sui numeri: i confini dei blocchi non
  // devono dipendere dal successo del parsing dei numeri di un blocco
  // precedente (in particolare Ex festività non dipende più dal blocco ROL,
  // a differenza di prima — vedi `parse()`).
  static const _tagGiorni = '(GIORNI)';
  static const _tagOre = '(ORE)';

  // Un singolo numero di rateo (2 decimali) — usato per estrarre TUTTI i
  // valori grezzi di un blocco delimitato dai tag sopra (2, 3 o 4 a seconda
  // di quali celle il cedolino lascia vuote quel mese invece di stampare
  // "0,00"), a differenza delle vecchie regex a conteggio fisso che
  // smettevano di funzionare non appena il numero di valori per riga
  // cambiava.
  static final _numeroRateo = RegExp(r'\d+,\d{2}');

  // Un valore di rateo (giorni/ore maturati/goduti/residui in un mese)
  // implausibilmente grande indica che il regex ha catturato un numero
  // "residuo anno precedente" incollato SENZA spazio al valore reale nel
  // testo estratto — visto su alcuni PDF reali (es. "670003,67" invece di
  // "3,67"), non su tutti: l'assenza dello spazio separatore è un
  // artefatto incostante di `syncfusion_flutter_pdf`, non deterministico
  // (dipende da come il layout PDF posiziona quella cella quel mese),
  // quindi non recuperabile con un regex più specifico. Soglia scelta ben
  // sopra qualunque residuo realisticamente accumulabile (un dipendente che
  // non gode ferie/ROL/ex festività per diversi anni consecutivi può
  // arrivare a qualche centinaio di ore/giorni residui: 100 era troppo
  // aggressiva e avrebbe scartato dati legittimi in quel caso, es. un
  // residuo di 150 ore) ma ben sotto ai numeri concatenati osservati
  // (dell'ordine di 670000+) — 1000 lascia comunque un ampio margine da
  // entrambi i lati.
  bool _valoreRateoImplausibile(double v) => v.abs() >= 1000;

  // Numeri grezzi (sinistra->destra) del blocco Ferie: a differenza di
  // ROL/Ex festività (delimitati da tag su ENTRAMBI i lati, vedi
  // `_valoriBloccoDelimitato` sotto), Ferie è il PRIMO blocco della tabella
  // ratei e non ha un'ancora testuale non numerica sulla sinistra — è
  // preceduto invece da un'altra riga della tabella (retribuzione
  // oraria/mensile) i cui valori restano incollati SENZA spazio all'ultimo
  // valore Ferie quando quest'ultimo la segue immediatamente (artefatto di
  // `extractText()`, non un problema del PDF: vedi doc di libreria in testa
  // al file). Cammina a ritroso nei token separati da whitespace a partire
  // dal tag "(GIORNI)", raccogliendo l'ULTIMO numero di ciascun token (per
  // tollerare un token "incollato" — es. "06/12/241.509,8100022,670007,17"
  // — il cui numero utile è sempre quello più vicino al blocco Ferie reale,
  // cioè il più a destra: le cifre iniziali spurie non alterano il valore
  // numerico anche quando lo "rubano" come zeri iniziali, es. "0007,17" =
  // 7,17), fino al primo token privo di un numero riconoscibile (confine
  // col testo non numerico che precede, es. "-CCNL") o dopo aver raccolto 4
  // valori (il massimo possibile: residuo A.P., maturato, goduto, residuo).
  List<double> _valoriFerieARitroso(String testoPrimaDiGiorni) {
    final token = testoPrimaDiGiorni.trim().split(RegExp(r'\s+'));
    final raccolti = <double>[];
    for (var i = token.length - 1; i >= 0 && raccolti.length < 4; i--) {
      if (token[i].isEmpty) continue;
      final matches = _numeroRateo.allMatches(token[i]);
      if (matches.isEmpty) break;
      raccolti.insert(0, _toDouble(matches.last.group(0)!));
    }
    return raccolti;
  }

  // Numeri grezzi (sinistra->destra) di un blocco ROL/Ex festività,
  // delimitato dai tag su ENTRAMBI i lati (a differenza di Ferie sopra):
  // nessun rischio di "incollarsi" a testo non correlato, il segmento è già
  // esattamente il contenuto delle celle.
  List<double> _valoriBloccoDelimitato(String testoFraTag) => _numeroRateo
      .allMatches(testoFraTag)
      .map((m) => _toDouble(m.group(0)!))
      .toList();

  // Interpreta gli 0-4 numeri grezzi (nell'ordine di apparizione nel testo)
  // di un blocco ratei (Ferie, ROL o Ex festività) nella terna
  // maturato/goduto/residuo — generalizza a tutte e 3 le categorie la
  // disambiguazione a 3 numeri nata per le sole ex festività (bilancio
  // "residuo = residuo A.P. + maturato - goduto", tolleranza 0,05):
  // - 4 valori: lettura posizionale [residuo A.P., maturato, goduto,
  //   residuo] — il conteggio stesso individua il significato di ogni
  //   posizione (comportamento posizionale invariato rispetto a prima di
  //   questo fix, che già leggeva così ROL/Ex festività). Il bilancio è
  //   verificato anche qui, ma SOLO quando il chiamante passa
  //   `verificaBilancio4Valori: true` (vedi doc sul parametro sotto): se non
  //   torna, `maturato` torna `double.infinity` (stessa sentinella del caso
  //   a 3 valori sotto) — mai un dato accettato in silenzio quando la
  //   verifica è attiva e non torna;
  // - 3 valori: due letture posizionali possibili — [maturato, goduto,
  //   residuo] (nessun residuo A.P.) oppure [residuo A.P. (scartato),
  //   maturato, residuo] (nessun goduto, cella lasciata vuota) —
  //   disambiguate col bilancio (SEMPRE verificato qui, a differenza del
  //   caso a 4 valori sopra: con soli 3 numeri il bilancio è l'UNICO modo di
  //   scegliere fra le due letture, non un controllo opzionale aggiuntivo);
  //   se NESSUNA delle due torna, `maturato` torna `double.infinity`
  //   (sentinella: il chiamante la tratta come valore implausibile via
  //   `_valoreRateoImplausibile`, stesso meccanismo di sempre); se tornano
  //   ENTRAMBE (caso degenere goduto=0, le due condizioni diventano
  //   aritmeticamente identiche) `ambiguo` è `true` e il chiamante deve
  //   segnalarlo esplicitamente, non scegliere in silenzio;
  // - 2 valori: [maturato, residuo], residuo A.P. e goduto impliciti a
  //   zero — visto sui PDF reali quando nessuno dei due è presente quel
  //   mese;
  // - 0 o 1 valori: dati insufficienti, `null` ("non trovati").
  //
  // [verificaBilancio4Valori] esiste perché il caso a 4 valori NON è
  // ugualmente rischioso per tutte e 3 le categorie. ROL/Ex festività (vedi
  // `_valoriBloccoDelimitato`) sono delimitati da tag SU ENTRAMBI I LATI: i
  // 4 numeri raccolti sono sempre esattamente il contenuto delle celle,
  // senza rischio di includerne uno estraneo — imporre lì il bilancio
  // scarterebbe dati legittimi che quel controllo non è mai stato pensato
  // per validare (es. un residuo alto ma legittimo accumulato in più anni
  // senza godimento, vedi test dedicato). Ferie invece cammina a ritroso
  // tramite `_valoriFerieARitroso`, priva di un'ancora testuale sul lato
  // sinistro del blocco: il valore raccolto in posizione "residuo A.P." può
  // essere un numero incollato SENZA spazio a una riga precedente non
  // correlata (vedi doc di libreria in testa al file) — per questa SOLA
  // categoria un bilancio che non torna è un segnale utile che uno dei 4
  // numeri raccolti non è quello giusto, quindi il chiamante Ferie in
  // `parse()` passa `true`; ROL/Ex festività lasciano il default `false`.
  ({double maturato, double goduto, double residuo, bool ambiguo})?
      _interpretaBloccoRatei(
    List<double> valori, {
    bool verificaBilancio4Valori = false,
  }) {
    switch (valori.length) {
      case 0:
      case 1:
        return null;
      case 2:
        return (
          maturato: valori[0],
          goduto: 0,
          residuo: valori[1],
          ambiguo: false,
        );
      case 3:
        final n1 = valori[0], n2 = valori[1], n3 = valori[2];
        const tolleranza = 0.05;
        final mancaResiduoAP = (n3 - (n1 - n2)).abs() <= tolleranza;
        final mancaGoduto = (n3 - (n1 + n2)).abs() <= tolleranza;
        if (mancaResiduoAP && mancaGoduto) {
          return (maturato: 0, goduto: 0, residuo: 0, ambiguo: true);
        } else if (mancaResiduoAP) {
          return (maturato: n1, goduto: n2, residuo: n3, ambiguo: false);
        } else if (mancaGoduto) {
          return (maturato: n2, goduto: 0, residuo: n3, ambiguo: false);
        } else {
          return (
            maturato: double.infinity,
            goduto: 0,
            residuo: 0,
            ambiguo: false,
          );
        }
      default:
        // 4 (o più: tronca alle ultime 4, le più vicine al tag di
        // chiusura) — lettura posizionale [residuo A.P., maturato, goduto,
        // residuo] (vedi doc sopra la firma per il perché la verifica di
        // bilancio è condizionata a [verificaBilancio4Valori]).
        final ultimi4 =
            valori.length > 4 ? valori.sublist(valori.length - 4) : valori;
        final residuoAnnoPrecedente4 = ultimi4[0];
        final maturato4 = ultimi4[1];
        final goduto4 = ultimi4[2];
        final residuo4 = ultimi4[3];
        if (verificaBilancio4Valori &&
            (residuo4 - (residuoAnnoPrecedente4 + maturato4 - goduto4)).abs() >
                0.05) {
          // Bilancio non verificato: stessa sentinella del caso a 3 valori
          // sopra, mai un dato accettato in silenzio.
          return (
            maturato: double.infinity,
            goduto: 0,
            residuo: 0,
            ambiguo: false,
          );
        }
        return (
          maturato: maturato4,
          goduto: goduto4,
          residuo: residuo4,
          ambiguo: false,
        );
    }
  }

  // Valori finali (maturato/goduto/residuo) di una categoria letta per
  // coordinate: implausibilità e bilancio sono verificati anche qui (stessa
  // tolleranza/soglia del percorso testuale) — le coordinate non soffrono
  // dell'artefatto "numeri incollati" del testo linearizzato, ma un
  // controllo di coerenza costa poco ed evita di fidarsi ciecamente di una
  // lettura comunque derivata dal riconoscimento di un layout di pagina.
  // Un'incoerenza di bilancio (ma valori singolarmente plausibili) NON
  // scarta il dato: aggiunge solo un warning, gli stessi valori letti
  // restano quelli salvati (stesso principio del controllo incrociato
  // lordo/totale competenze più sotto in `parse()`).
  ({double maturato, double goduto, double residuo}) _assegnaDaCoordinate(
    RateoCategoria dati,
    List<String> warnings,
    String categoria,
  ) {
    final residuoAnnoPrecedente = dati.residuoAnnoPrecedente ?? 0;
    final maturato = dati.maturato ?? 0;
    final goduto = dati.goduto ?? 0;
    final residuo = dati.residuo ?? 0;
    if (_valoreRateoImplausibile(maturato) ||
        _valoreRateoImplausibile(goduto) ||
        _valoreRateoImplausibile(residuo)) {
      warnings.add(
        'dati $categoria scartati: valore implausibile letto dalle '
        'coordinate del PDF, verifica manualmente',
      );
      return (maturato: 0, goduto: 0, residuo: 0);
    }
    if ((residuo - (residuoAnnoPrecedente + maturato - goduto)).abs() > 0.05) {
      warnings.add(
        'dati $categoria: il bilancio residuo = residuo anno precedente + '
        'maturato - goduto non torna sui valori letti dalle coordinate '
        'del PDF (differenza oltre la tolleranza), verifica manualmente',
      );
    }
    return (maturato: maturato, goduto: goduto, residuo: residuo);
  }

  // Chiave usata nella mappa `trattenute` per modellare esplicitamente la
  // differenza di arrotondamento ARR. PRECED./ARR. ATTUALE del percorso a
  // coordinate (vedi `_trattenuteDaCoordinate`) — MAI nascosta in un residuo
  // generico "Altre trattenute" come nel percorso testuale storico.
  static const _chiaveArrotondamento =
      'Differenza di arrotondamento (mese precedente/attuale)';

  // Competenze lette per coordinate: solo le righe in colonna COMPETENZE con
  // flag N (vedi doc su [RigaVoceCoordinate.flagN]) — le righe senza flag N
  // sono puramente informative (es. "823 Addizionale Regionale Dovuta") e
  // non vanno sommate al lordo.
  List<VoceCompetenza> _competenzeDaCoordinate(VociEstratteDaCoordinate voci) {
    return [
      for (final riga in voci.righe)
        if (riga.colonna == ColonnaVoceCoordinate.competenze && riga.flagN)
          VoceCompetenza(
            descrizione: riga.descrizione,
            quantita: riga.quantita,
            importo: riga.importo,
          ),
    ];
  }

  // Trattenute lette per coordinate: quote C/DIPENDENTE dei contributi +
  // IRPEF + righe della tabella voci in colonna TRATTENUTE con flag N (es.
  // "828 Rata Addizionale Regionale") + una voce esplicita per la
  // differenza di arrotondamento ARR. PRECED./ARR. ATTUALE (vedi doc di
  // libreria in testa al file: "mai nascosta nel residuo 'Altre
  // trattenute'"), aggiunta solo quando non trascurabile. Solo chiamata
  // quando `voci.haDatiSufficienti` (quindi `voci.totali` non nullo).
  ({Map<String, double> trattenute, bool verificate}) _trattenuteDaCoordinate(
    VociEstratteDaCoordinate voci,
    List<String> warnings,
  ) {
    final trattenute = <String, double>{...voci.contributiDipendente};
    var verificate = true;

    if (voci.irpefTrattenuta != null) {
      trattenute['IRPEF'] = voci.irpefTrattenuta!;
    } else {
      warnings.add(
        'trattenuta IRPEF non trovata dalle coordinate del PDF, verifica manualmente',
      );
      verificate = false;
    }

    for (final riga in voci.righe) {
      if (riga.colonna == ColonnaVoceCoordinate.trattenute && riga.flagN) {
        trattenute[riga.descrizione] = riga.importo;
      }
    }

    final totali = voci.totali!;
    final arrotondamento = totali.arrPreced - totali.arrAttuale;
    if (arrotondamento.abs() > 0.005) {
      trattenute[_chiaveArrotondamento] = arrotondamento;
    }

    final sommaTrattenuteNominate = trattenute.entries
        .where((e) => e.key != _chiaveArrotondamento)
        .fold(0.0, (somma, e) => somma + e.value);
    if ((sommaTrattenuteNominate - totali.totaleTrattenute).abs() > 0.05) {
      warnings.add(
        'trattenute calcolate (€${sommaTrattenuteNominate.toStringAsFixed(2)}) '
        'divergono dal totale trattenute stampato sul PDF '
        '(€${totali.totaleTrattenute.toStringAsFixed(2)}): verifica manualmente',
      );
      verificate = false;
    }

    return (trattenute: trattenute, verificate: verificate);
  }

  // Ore lavorate reali ("ORE LAV.", campo del blocco "Q.T.A." del
  // cedolino, distinto da "SETT. RETR."/"GG. RETR."/"GG. LAV." sulla
  // stessa riga) — il testo estratto NON mantiene l'adiacenza fisica con
  // l'etichetta della colonna, che compare in un'intestazione lontana dal
  // valore nel documento linearizzato (vedi nota in testa al file). Il
  // valore vero è però riconoscibile, su un PDF reale, come l'unico numero
  // a 2 decimali preceduto da un bordo di parola (non un altro numero) e
  // da un blocco di 2-6 cifre concatenate senza separatore (es. "42623" =
  // settimane retribuite "4" + giorni retribuiti "26" + giorni lavorati
  // "23"): quel blocco di cifre pure, mai preceduto da virgola/punto,
  // distingue questo match dalle cifre dopo la virgola di una tariffa
  // oraria a 5 decimali altrove nel documento (es. "0,34864" letta come
  // "34864" se non si richiedesse il bordo di parola prima del blocco).
  //
  // NON usata su tutto il documento (vedi `parse()`): questo pattern da
  // solo NON è ancorato all'etichetta "ORE LAV."/al blocco Q.T.A. — è solo
  // "un numero a 2 decimali dopo un blocco di 2-6 cifre pure", una forma
  // che potrebbe ripresentarsi altrove per puro caso su un PDF reale mai
  // visto, producendo un valore sbagliato senza alcun warning. Per questo
  // la ricerca in `parse()` è ristretta al segmento di testo tra la fine
  // della riga INPS e "Firma per quietanza" — lo stesso segmento già usato
  // per `_rigaTrattenutaVerificata` — perché il valore "ORE LAV." si trova
  // SEMPRE lì sui PDF reali disponibili (il blocco Q.T.A. con i dati del
  // rateo viene stampato subito prima di "Firma per quietanza"), un
  // ancoraggio riutilizzato piuttosto che una ricerca libera su tutto il
  // documento. Se il segmento non è determinabile (INPS o "Firma per
  // quietanza" assenti) si ripiega sull'intero testo come rete di
  // sicurezza. In entrambi i casi, se il pattern matcha più di una volta
  // nello scope di ricerca, è un segnale che l'ancoraggio è debole per quel
  // documento: non si prende il primo match in silenzio, si segnala un
  // warning esplicito e si ricade sulla stima da giorni×8 (vedi `parse()`).
  static final _oreLavorateDirette = RegExp(
    r'(?:^|\s)\d{2,6}\s+(\d+,\d{2})',
  );

  // Terzo numero (formato con eventuale separatore delle migliaia ".")
  // immediatamente dopo il valore di "ORE LAV." nello stesso blocco Q.T.A.
  // (stesso segmento scoped e stesso ancoraggio già usato per
  // `_oreLavorateDirette`, applicato subito dopo la fine di quel match):
  // sul PDF di riferimento coincide con "IMPON.CONTRIBUTIVO MESE", che a sua
  // volta coincide col lordo reale del cedolino (1.543,13) — un totale
  // competenze già stampato dal software payroll, indipendente dalla somma
  // delle singole voci di competenza lette da `_rigaVoceCompetenza`. Usato
  // SOLO come controllo incrociato di plausibilità contro
  // `computeLordo(competenze)` (vedi `parse()`), mai per sovrascrivere il
  // valore calcolato: se il layout cambia e questo terzo numero non è più
  // "IMPON.CONTRIBUTIVO MESE", il controllo può produrre falsi positivi
  // (warning spurio) ma non falsi dati salvati.
  static final _totaleCompetenzeDopoOreLavorate = RegExp(
    r'^\s*[\d.]+,\d{2}\s+[\d.]+,\d{2}\s+([\d.]+,\d{2})',
  );

  static final _inps = RegExp(r'INPS([\d.]+,\d{2})\s+(\d,\d{2})(\d+,\d{2})');

  // Nome+aliquota+importo attaccati senza spazio, pattern osservato SOLO per
  // la riga immediatamente successiva a INPS nel PDF reale (es. "CONTRIBUTO
  // EBILOG0,50 3,50"). Deliberatamente ristretto a questo segmento: un
  // regex applicato a tutta la sezione trattenute rischierebbe di leggere
  // importi annui/imponibili come se fossero l'importo mensile trattenuto
  // (es. una riga "Rata Addizionale Regionale" seguita da un imponibile
  // fiscale annuo, non un importo mensile). Il segno "-" davanti
  // all'importo è opzionale, stessa motivazione di `_rigaVoceCompetenza`: un
  // conguaglio/storno a credito su questa trattenuta potrebbe comparire come
  // importo negativo, da propagare così com'è nella mappa `trattenute`
  // invece di scartarlo silenziosamente.
  static final _rigaTrattenutaVerificata =
      RegExp(r'([A-Z][A-Z ]{2,}?)(\d,\d{2})\s+(-?\d+,\d{2})');

  static final _periodo = RegExp(
    r'(gennaio|febbraio|marzo|aprile|maggio|giugno|luglio|agosto|settembre|ottobre|novembre|dicembre)\s+(\d{4})',
    caseSensitive: false,
  );

  // Periodo di competenza delle mensilità supplementari (13esima/14esima):
  // il campo "MESE DI RETRIBUZIONE" riporta "Mens.supplementare MM/YYYY"
  // invece del nome del mese per esteso — un testo affidabile solo per
  // queste buste, va provato con priorità su [_periodo] perché su una
  // mensilità supplementare quel nome di mese per esteso trovato altrove
  // nel documento può appartenere a un contesto diverso (es. data di
  // stampa) e produrre un periodo di competenza sbagliato.
  static final _mensSupplementare = RegExp(
    r'Mens\.?\s*supplementare\s*(\d{1,2})\s*/\s*(\d{4})',
    caseSensitive: false,
  );

  static final _quattordicesima =
      RegExp(r'quattordicesima', caseSensitive: false);
  static final _tredicesima = RegExp(r'tredicesima', caseSensitive: false);

  /// Riconosce "13.ma mensilita'"/"14ª mensilità"/varianti simili in una voce
  /// di competenza (tag RATEI): quando presente è un segnale ESPLICITO del
  /// tipo mensilità (13a/14a), più affidabile della deduzione dal mese in
  /// `_tipoDaMeseSupplementare` — usato con priorità su quella deduzione. Vedi
  /// `parse()`, blocco `--- tipo ---`.
  static final _numeroMensilitaSupplementare = RegExp(
    r"(\d{1,2})\s*[.,ª']?\s*ma\s+mensilit",
    caseSensitive: false,
  );

  double _toDouble(String raw) =>
      double.parse(raw.replaceAll('.', '').replaceAll(',', '.'));

  /// Deduce il tipo mensilità dal mese di "Mens.supplementare" quando il
  /// testo non nomina esplicitamente "tredicesima"/"quattordicesima" —
  /// novembre/dicembre/gennaio sono i mesi tipici di erogazione della
  /// tredicesima, giugno/luglio della quattordicesima. Mese fuori da questi
  /// pattern: nessuna deduzione (`null`), resta il fallback mensile.
  TipoBustaPaga? _tipoDaMeseSupplementare(int mese) {
    if (mese == 11 || mese == 12 || mese == 1) return TipoBustaPaga.tredicesima;
    if (mese == 6 || mese == 7) return TipoBustaPaga.quattordicesima;
    return null;
  }

  BustaPagaEstratti parse(
    String testo, [
    RateiEstrattiDaCoordinate? ratei,
    VociEstratteDaCoordinate? voci,
  ]) {
    final warnings = <String>[];

    // --- periodo ---
    String? periodo;
    final supplementareMatch = _mensSupplementare.firstMatch(testo);
    if (supplementareMatch != null) {
      final mese = supplementareMatch.group(1)!.padLeft(2, '0');
      final anno = supplementareMatch.group(2)!;
      periodo = '$anno-$mese';
    } else {
      final periodoMatch = _periodo.firstMatch(testo);
      if (periodoMatch != null) {
        final mese = _mesi[periodoMatch.group(1)!.toLowerCase()]!;
        final anno = periodoMatch.group(2)!;
        periodo = '$anno-${mese.toString().padLeft(2, '0')}';
      } else {
        warnings.add('periodo non trovato');
      }
    }

    // --- tipo: 13esima/14esima se il testo le nomina esplicitamente,
    // altrimenti mensile. "Quattordicesima" controllata per prima solo per
    // ordine, non per ambiguità: sono parole distinte, nessun rischio di
    // falsi positivi incrociati. Se nessuna delle due parole matcha, si
    // cerca poi il numero esplicito della mensilità in una voce di
    // competenza tipo "13.ma mensilita'" (`_numeroMensilitaSupplementare`):
    // è un dato LETTO, non dedotto, quindi ha priorità sulla deduzione dal
    // mese e non produce warning. Solo se anche questo pattern non matcha,
    // e il testo contiene "Mens.supplementare MM/YYYY", il tipo viene
    // dedotto dal mese (vedi `_tipoDaMeseSupplementare`) con un warning
    // esplicito, dato che è una deduzione e non una lettura diretta. Se il
    // mese è "atipico" (fuori dai periodi tipici di erogazione,
    // `_tipoDaMeseSupplementare` ritorna null), il tipo resta `mensile`
    // come fallback ma viene comunque aggiunto un warning esplicito: il
    // tipo è modificabile manualmente nel form, quindi un warning (non un
    // blocco) è sufficiente a far verificare il dato prima del
    // salvataggio. ---
    TipoBustaPaga tipo;
    if (_quattordicesima.hasMatch(testo)) {
      tipo = TipoBustaPaga.quattordicesima;
    } else if (_tredicesima.hasMatch(testo)) {
      tipo = TipoBustaPaga.tredicesima;
    } else {
      tipo = TipoBustaPaga.mensile;
      final numeroMensilitaMatch =
          _numeroMensilitaSupplementare.firstMatch(testo);
      final numeroMensilita = numeroMensilitaMatch?.group(1);
      if (numeroMensilita == '13') {
        tipo = TipoBustaPaga.tredicesima;
      } else if (numeroMensilita == '14') {
        tipo = TipoBustaPaga.quattordicesima;
      } else if (supplementareMatch != null) {
        final meseSupplementare = int.parse(supplementareMatch.group(1)!);
        final tipoDedotto = _tipoDaMeseSupplementare(meseSupplementare);
        if (tipoDedotto != null) {
          tipo = tipoDedotto;
          warnings.add(
            'tipo mensilità dedotto dal mese "Mens.supplementare", verifica',
          );
        } else {
          warnings.add(
            'tipo mensilità non determinato per "Mens.supplementare '
            '${supplementareMatch.group(1)}/${supplementareMatch.group(2)}": '
            'verifica manualmente il tipo (mensile/13a/14a) prima di salvare',
          );
        }
      }
    }

    // --- competenze: preferisce le coordinate quando disponibili e
    // sufficienti (vedi doc su [VociEstratteDaCoordinate]: il testo
    // linearizzato perde la distinzione fra le colonne TRATTENUTE e
    // COMPETENZE, oltre a non leggere affatto le righe senza tag
    // GIORNI/ORE/RATEI), altrimenti il percorso testuale storico —
    // escludendo ferie/permessi già modellati altrove, combinando il
    // pattern mensile (tag "GIORNI"/"ORE") e quello delle mensilità
    // supplementari (tag "RATEI", vedi `_rigaVoceCompetenzaSupplementare`,
    // che non si sovrappongono mai sullo stesso testo perché i tag sono
    // letteralmente diversi). `primaCompetenzaMatchStart` è calcolato
    // SEMPRE dal testo, indipendentemente da quale fonte alimenta poi
    // `competenze`: serve solo per delimitare `zonaRatei` più sotto. ---
    final matchCompetenze = [
      ..._rigaVoceCompetenza.allMatches(testo),
      ..._rigaVoceCompetenzaSupplementare.allMatches(testo),
    ]..sort((a, b) => a.start.compareTo(b.start));
    final primaCompetenzaMatchStart =
        matchCompetenze.isEmpty ? null : matchCompetenze.first.start;

    final usaVociCoordinate = voci != null && voci.haDatiSufficienti;

    final List<VoceCompetenza> competenze;
    if (usaVociCoordinate) {
      for (final riga in voci.righe) {
        if (riga.entrambeColonneValorizzate) {
          warnings.add(
            'riga "${riga.descrizione}": valori letti sia in colonna '
            'TRATTENUTE sia in colonna COMPETENZE dalle coordinate del PDF, '
            'usato solo il valore COMPETENZE — verifica manualmente',
          );
        }
      }
      competenze = _competenzeDaCoordinate(voci);
    } else {
      final testuali = <VoceCompetenza>[];
      for (final m in matchCompetenze) {
        final descrizione = m.group(1)!.trim();
        final descrizioneLower = descrizione.toLowerCase();
        final esclusa = _descrizioniEscluseDaCompetenze
            .any((prefisso) => descrizioneLower.startsWith(prefisso));
        if (esclusa) continue;
        final quantita = _toDouble(m.group(2)!);
        final importoGroup = m.group(3);
        final importo = importoGroup != null ? _toDouble(importoGroup) : 0.0;
        testuali.add(VoceCompetenza(
          descrizione: descrizione,
          quantita: quantita,
          importo: importo,
        ));
      }
      competenze = testuali;
    }

    // --- lordo / straordinari: derivati dalla lista competenze (unica
    // fonte di verità, vedi computeLordo/computeStraordinari) ---
    final lordo = computeLordo(competenze);
    final straordinari = computeStraordinari(competenze);
    // Nota: il controllo è su `competenze.isEmpty`, non su `lordo == 0` — con
    // il segno "-" reso opzionale sugli importi delle competenze, un lordo
    // pari a 0 è un risultato legittimo quando le voci si compensano (es.
    // +1000,00 e uno storno -1000,00), non un sintomo di "nessuna riga
    // riconosciuta".
    if (competenze.isEmpty) {
      warnings
          .add('lordo non trovato (nessuna riga di competenza riconosciuta)');
    }

    // --- permessi riduz. orario goduti nel mese: somma tutte le righe
    // trovate ---
    double permessiGodutiMese = 0;
    for (final m in _rigaPermessiMese.allMatches(testo)) {
      permessiGodutiMese += _toDouble(m.group(1)!);
    }

    // --- anticipati qui (usati anche più sotto per le trattenute) per
    // delimitare lo scope di ricerca di "ore lavorate" subito sotto, vedi
    // commento su _oreLavorateDirette ---
    final inpsMatch = _inps.firstMatch(testo);
    final firmaIndex = testo.indexOf('Firma per quietanza');

    // --- ore lavorate: lette direttamente dal campo "ORE LAV." del blocco
    // Q.T.A. quando riconoscibile, cercando SOLO nel segmento di testo tra
    // la fine della riga INPS e "Firma per quietanza" (vedi commento su
    // _oreLavorateDirette per il perché di questo scoping) — nessun warning
    // in questo ramo, è un dato letto non stimato. Se il pattern matcha più
    // di una volta in quello scope, l'ancoraggio è ambiguo per questo
    // documento: warning esplicito, nessun match preso in silenzio. Un
    // valore implausibile (fuori dal range plausibile di ore mensili),
    // un'ambiguità o l'assenza di un match fa scattare il fallback storico:
    // stima da giorni×8, sommando le quantità di tutte le voci di
    // competenza "Retribuzione ordinaria", con lo stesso warning esplicito
    // di sempre. ---
    double? oreLavorate;
    final segmentoQta =
        (inpsMatch != null && firmaIndex != -1 && firmaIndex > inpsMatch.end)
            ? testo.substring(inpsMatch.end, firmaIndex)
            : testo;
    final oreLavorateMatches =
        _oreLavorateDirette.allMatches(segmentoQta).toList();
    if (oreLavorateMatches.length > 1) {
      warnings.add(
        'ore lavorate: possibile ambiguità nel testo estratto, verifica manualmente',
      );
    } else if (oreLavorateMatches.length == 1) {
      final valore = _toDouble(oreLavorateMatches.first.group(1)!);
      if (valore > 0 && valore <= 300) {
        oreLavorate = valore;
      }
    }
    if (oreLavorate == null) {
      double giorniOrdinari = 0;
      for (final voce in competenze) {
        if (voce.descrizione
            .trim()
            .toLowerCase()
            .startsWith('retribuzione ordinaria')) {
          // `?? 0`: mai osservata una "Retribuzione ordinaria" priva di
          // quantità (sempre tag "GIORNI" sul PDF), rete di sicurezza
          // richiesta comunque dal tipo nullable di `quantita`.
          giorniOrdinari += voce.quantita ?? 0;
        }
      }
      if (giorniOrdinari > 0) {
        oreLavorate = giorniOrdinari * 8;
        warnings
            .add('ore lavorate stimate da giorni×8, non lette direttamente');
      } else {
        warnings.add('ore lavorate non determinabili');
      }
    }

    // --- controllo incrociato: il "totale competenze" stampato sul PDF
    // contro il lordo calcolato dalla somma delle voci di competenza. Sul
    // percorso a coordinate la fonte è la riga totali (Y≈796, vedi
    // [TotaliCoordinate]); sul percorso testuale, il numero stampato dal
    // software payroll subito dopo "ORE LAV." nel blocco Q.T.A. (vedi
    // _totaleCompetenzeDopoOreLavorate), disponibile solo quando "ore
    // lavorate" è stato letto direttamente da un match non ambiguo (stesso
    // ancoraggio, stessa garanzia di scoping) — con un match ambiguo o
    // assente non c'è una posizione affidabile da cui cercare il terzo
    // numero. In nessuno dei due casi si altera mai `lordo`, solo si
    // segnala una divergenza. ---
    var lordoVerificato = false;
    if (usaVociCoordinate) {
      final totaleStampato = voci.totali!.totaleCompetenze;
      lordoVerificato = (totaleStampato - lordo).abs() <= 0.05;
      if (!lordoVerificato) {
        warnings.add(
          'lordo calcolato (€${lordo.toStringAsFixed(2)}) diverge dal '
          'totale competenze stampato sul PDF (€${totaleStampato.toStringAsFixed(2)}): '
          'verifica manualmente',
        );
      }
    } else if (oreLavorateMatches.length == 1) {
      final dopoOreLavorate =
          segmentoQta.substring(oreLavorateMatches.first.end);
      final totaleMatch =
          _totaleCompetenzeDopoOreLavorate.firstMatch(dopoOreLavorate);
      if (totaleMatch != null) {
        final totaleStampato = _toDouble(totaleMatch.group(1)!);
        if ((totaleStampato - lordo).abs() > 0.05) {
          warnings.add(
            'lordo calcolato (€${lordo.toStringAsFixed(2)}) diverge dal '
            'totale competenze stampato sul PDF (€${totaleStampato.toStringAsFixed(2)}): '
            'verifica manualmente',
          );
        }
      }
    }

    // --- ferie / ROL / ex festività: fonte primaria [ratei] (lettura per
    // coordinate, autoritativa quando presente per una categoria, vedi doc
    // su [RateiEstrattiDaCoordinate]), altrimenti percorso testuale, cercato
    // SOLO nel testo che precede la prima riga di competenza riconosciuta
    // (vedi _rigaVoceCompetenza / _rigaVoceCompetenzaSupplementare) — senza
    // questo scoping, un tag letterale "(GIORNI)"/"(ORE)" comparso per puro
    // caso in una sezione successiva del documento (es. una nota fuori
    // tabella) potrebbe essere scambiato per il blocco ratei reale,
    // agganciandosi a numeri che non c'entrano nulla con Ferie/ROL/Ex
    // festività. Su tutti i PDF/fixture reali disponibili (mensili E
    // mensilità supplementari) il blocco ratei precede sempre la prima riga
    // di competenza, quindi questo scoping non cambia il comportamento
    // osservato. NOTA aggiornata dopo verifica su un PDF reale di una
    // 14esima ("Mens.supplementare 6/2026"): a differenza dell'ipotesi
    // precedente (non validata), il blocco ratei Ferie/ROL/Ex festività NON
    // è assente sulle mensilità supplementari — è presente con la stessa
    // struttura "(GIORNI)"/"(ORE)" del layout mensile, con i dati residui
    // aggiornati al mese di erogazione.
    final zonaRatei = primaCompetenzaMatchStart != null
        ? testo.substring(0, primaCompetenzaMatchStart)
        : testo;

    // Posizioni dei tag che delimitano i 3 blocchi, indipendenti dal
    // successo del parsing dei NUMERI di un blocco precedente (in
    // particolare, la posizione del tag di chiusura Ex festività non
    // dipende più dal match ROL — vedi doc di libreria in testa al file).
    final idxGiorni = zonaRatei.indexOf(_tagGiorni);
    final idxOre1 = idxGiorni != -1
        ? zonaRatei.indexOf(_tagOre, idxGiorni + _tagGiorni.length)
        : -1;
    final idxOre2 = idxOre1 != -1
        ? zonaRatei.indexOf(_tagOre, idxOre1 + _tagOre.length)
        : -1;

    // --- ferie (maturate, godute, residue) ---
    double ferieMaturate = 0, ferieGodute = 0, ferieResidue = 0;
    final ferieDaCoordinate = ratei?.ferie;
    if (ferieDaCoordinate != null && ferieDaCoordinate.haAlmenoUnValore) {
      final esito = _assegnaDaCoordinate(ferieDaCoordinate, warnings, 'ferie');
      ferieMaturate = esito.maturato;
      ferieGodute = esito.goduto;
      ferieResidue = esito.residuo;
    } else if (idxGiorni != -1) {
      final interpretato = _interpretaBloccoRatei(
        _valoriFerieARitroso(zonaRatei.substring(0, idxGiorni)),
        // SOLO qui fra le 3 categorie: vedi doc su `verificaBilancio4Valori`
        // sopra `_interpretaBloccoRatei` per il perché (ROL/Ex festività,
        // più sotto, restano al default `false`).
        verificaBilancio4Valori: true,
      );
      if (interpretato == null) {
        warnings.add('dati ferie non trovati');
      } else if (interpretato.ambiguo) {
        warnings.add(
          'dati ferie ambigui: impossibile stabilire quale cella sia '
          'vuota (residuo anno precedente o goduto) quando il "goduto" '
          'candidato è zero, verifica manualmente',
        );
      } else if (_valoreRateoImplausibile(interpretato.maturato) ||
          _valoreRateoImplausibile(interpretato.goduto) ||
          _valoreRateoImplausibile(interpretato.residuo)) {
        warnings.add(
          'dati ferie scartati: valore implausibile estratto (probabile '
          'numero residuo anno precedente incollato senza spazio), '
          'verifica manualmente',
        );
      } else {
        ferieMaturate = interpretato.maturato;
        ferieGodute = interpretato.goduto;
        ferieResidue = interpretato.residuo;
      }
    } else {
      warnings.add('dati ferie non trovati');
    }

    // --- ROL (maturati, goduti, residui) ---
    double rolMaturati = 0, rolGoduti = 0, rolResidui = 0;
    final rolDaCoordinate = ratei?.rol;
    if (rolDaCoordinate != null && rolDaCoordinate.haAlmenoUnValore) {
      final esito = _assegnaDaCoordinate(rolDaCoordinate, warnings, 'ROL');
      rolMaturati = esito.maturato;
      rolGoduti = esito.goduto;
      rolResidui = esito.residuo;
    } else if (idxGiorni != -1 && idxOre1 != -1) {
      final interpretato = _interpretaBloccoRatei(
        _valoriBloccoDelimitato(
          zonaRatei.substring(idxGiorni + _tagGiorni.length, idxOre1),
        ),
      );
      if (interpretato == null) {
        warnings.add('dati ROL non trovati');
      } else if (interpretato.ambiguo) {
        warnings.add(
          'dati ROL ambigui: impossibile stabilire quale cella sia vuota '
          '(residuo anno precedente o goduto) quando il "goduto" '
          'candidato è zero, verifica manualmente',
        );
      } else if (_valoreRateoImplausibile(interpretato.maturato) ||
          _valoreRateoImplausibile(interpretato.goduto) ||
          _valoreRateoImplausibile(interpretato.residuo)) {
        warnings.add(
          'dati ROL scartati: valore implausibile estratto (probabile '
          'numero residuo anno precedente incollato senza spazio), '
          'verifica manualmente',
        );
      } else {
        rolMaturati = interpretato.maturato;
        rolGoduti = interpretato.goduto;
        rolResidui = interpretato.residuo;
      }
    } else {
      warnings.add('dati ROL non trovati');
    }

    // --- ex festività (maturate, godute, residue) ---
    double exFestivitaMaturate = 0,
        exFestivitaGodute = 0,
        exFestivitaResidue = 0;
    final exFestivitaDaCoordinate = ratei?.exFestivita;
    if (exFestivitaDaCoordinate != null &&
        exFestivitaDaCoordinate.haAlmenoUnValore) {
      final esito = _assegnaDaCoordinate(
        exFestivitaDaCoordinate,
        warnings,
        'ex festività',
      );
      exFestivitaMaturate = esito.maturato;
      exFestivitaGodute = esito.goduto;
      exFestivitaResidue = esito.residuo;
    } else if (idxOre1 != -1 && idxOre2 != -1) {
      final interpretato = _interpretaBloccoRatei(
        _valoriBloccoDelimitato(
          zonaRatei.substring(idxOre1 + _tagOre.length, idxOre2),
        ),
      );
      if (interpretato == null) {
        warnings.add('dati ex festività non trovati');
      } else if (interpretato.ambiguo) {
        warnings.add(
          'dati ex festività ambigui: impossibile stabilire quale '
          'cella sia vuota (residuo anno precedente o goduto) quando '
          'il "goduto" candidato è zero, verifica manualmente',
        );
      } else if (_valoreRateoImplausibile(interpretato.maturato) ||
          _valoreRateoImplausibile(interpretato.goduto) ||
          _valoreRateoImplausibile(interpretato.residuo)) {
        warnings.add(
          'dati ex festività scartati: valore implausibile estratto, '
          'verifica manualmente',
        );
      } else {
        exFestivitaMaturate = interpretato.maturato;
        exFestivitaGodute = interpretato.goduto;
        exFestivitaResidue = interpretato.residuo;
      }
    } else {
      warnings.add('dati ex festività non trovati');
    }
    // In questo layout "Permessi (R.O.L.)" è un unico concetto: i permessi
    // goduti coincidono con i ROL goduti.
    final permessiGoduti = rolGoduti;

    // --- trattenute / netto: preferisce le coordinate quando disponibili e
    // sufficienti (stessa fonte già usata sopra per `competenze`/`lordo`,
    // vedi doc su [VociEstratteDaCoordinate] — la scelta resta
    // tutto-o-niente, non per singolo campo). ---
    final Map<String, double> trattenute;
    double? netto;
    var trattenuteVerificate = false;
    if (usaVociCoordinate) {
      final esitoTrattenute = _trattenuteDaCoordinate(voci, warnings);
      trattenute = esitoTrattenute.trattenute;
      trattenuteVerificate = esitoTrattenute.verificate;
      // Netto "grezzo" di riferimento (riga totali del PDF): usato solo per
      // il controllo di coerenza "netto superiore al lordo" più sotto e come
      // termine di paragone nella verifica aritmetica finale — il valore
      // restituito resta comunque quello derivato (`nettoDerivato`).
      netto = voci.totali!.nettoInBusta;
    } else {
      // --- percorso testuale (INVARIATO): INPS letto direttamente, il resto
      // aggregato (inpsMatch calcolato più sopra, riusato anche per lo
      // scoping di "ore lavorate") ---
      final trattenuteTestuali = <String, double>{};
      double inpsImporto = 0;
      if (inpsMatch != null) {
        inpsImporto = _toDouble(inpsMatch.group(3)!);
        trattenuteTestuali['INPS'] = inpsImporto;
      } else {
        warnings.add('trattenuta INPS non trovata');
      }

      // --- trattenute nominate verificate: SOLO nel segmento tra la fine
      // del match INPS e l'inizio di "Firma per quietanza" (vedi
      // _rigaTrattenutaVerificata) ---
      double trattenuteNominateExtra = 0;
      if (inpsMatch != null && firmaIndex != -1 && firmaIndex > inpsMatch.end) {
        final segmento = testo.substring(inpsMatch.end, firmaIndex);
        for (final m in _rigaTrattenutaVerificata.allMatches(segmento)) {
          final nome = m.group(1)!.trim();
          final importo = _toDouble(m.group(3)!);
          trattenuteTestuali[nome] = importo;
          trattenuteNominateExtra += importo;
        }
      }

      // --- netto: ultimo numero della riga dopo "Firma per quietanza"
      // (firmaIndex calcolato più sopra) ---
      if (firmaIndex != -1) {
        final dopoFirma =
            testo.substring(firmaIndex + 'Firma per quietanza'.length);
        final righeDopoFirma =
            dopoFirma.split('\n').where((r) => r.trim().isNotEmpty);
        if (righeDopoFirma.isNotEmpty) {
          final rigaNetto = righeDopoFirma.first.trim();
          final numeri =
              RegExp(r'-?[\d.]+,\d{2}').allMatches(rigaNetto).toList();
          if (numeri.isNotEmpty) {
            final ultimo = numeri.last.group(0)!;
            // Il "-" davanti all'ultimo numero è quasi sempre un artefatto
            // di estrazione (due celle concatenate), non un netto negativo.
            if (ultimo.startsWith('-')) {
              netto = _toDouble(ultimo.substring(1));
              warnings.add(
                  'netto: segno "-" iniziale scartato come probabile artefatto di estrazione, verificare');
            } else {
              netto = _toDouble(ultimo);
            }
          }
        }
      }
      if (netto == null) warnings.add('netto non trovato');

      if (netto != null && lordo > 0 && inpsImporto > 0) {
        final resto = lordo - netto - inpsImporto - trattenuteNominateExtra;
        if (resto > 0.01) {
          trattenuteTestuali['Altre trattenute (IRPEF + varie)'] =
              double.parse(resto.toStringAsFixed(2));
        }
      }
      trattenute = trattenuteTestuali;
    }

    if (netto != null && lordo > 0 && netto > lordo) {
      warnings.add('netto superiore al lordo, verifica i dati estratti');
    }

    // Il valore finale di `netto` è sempre quello derivato (lordo -
    // trattenute, incluso l'eventuale residuo "Altre trattenute"/la voce di
    // arrotondamento calcolati sopra) — non il valore grezzo letto dal PDF,
    // che resta usato solo come input intermedio e per il controllo di
    // coerenza "netto superiore al lordo" appena sopra.
    final nettoDerivato =
        netto != null ? computeNetto(lordo, trattenute) : null;

    // Verifica aritmetica aggiuntiva (solo percorso a coordinate, dove è
    // attesa una riconciliazione esatta col netto stampato — vedi doc su
    // [TotaliCoordinate]): se il netto derivato diverge comunque dal netto
    // in busta stampato, segnala un warning invece di restituire un dato
    // silenziosamente inconsistente (può succedere se una riga della
    // tabella voci non è stata riconosciuta correttamente su un layout non
    // ancora osservato).
    var nettoVerificato = false;
    if (usaVociCoordinate && nettoDerivato != null) {
      final nettoCoerente =
          (nettoDerivato - voci.totali!.nettoInBusta).abs() <= 0.05;
      if (!nettoCoerente) {
        warnings.add(
          'netto calcolato (€${nettoDerivato.toStringAsFixed(2)}) diverge dal '
          'netto in busta stampato sul PDF (€${voci.totali!.nettoInBusta.toStringAsFixed(2)}): '
          'verifica manualmente',
        );
      }
      nettoVerificato =
          lordoVerificato && trattenuteVerificate && nettoCoerente;
    }

    return BustaPagaEstratti(
      periodo: periodo,
      lordo: competenze.isNotEmpty ? lordo : null,
      netto: nettoDerivato,
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
      tipo: tipo,
      warnings: warnings,
      lordoVerificato: lordoVerificato,
      trattenuteVerificate: trattenuteVerificate,
      nettoVerificato: nettoVerificato,
    );
  }
}
