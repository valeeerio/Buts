import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/busta_paga.dart';
import 'busta_paga_regex_parser.dart';
import 'payslip_layouts/pdf_contenuto.dart';
import 'pdf_path_resolver.dart';

export 'payslip_layouts/pdf_contenuto.dart' show ParolaVoce;

enum PdfImportStatus { success, cancelled, noExtractableText, error }

/// Esito della selezione/import di un PDF. In v1 sono supportati solo PDF
/// testuali (con testo selezionabile) — i PDF scansionati/immagine sono
/// esplicitamente fuori scope (nessun OCR), segnalati con
/// [PdfImportStatus.noExtractableText] invece di fallire silenziosamente.
class PdfImportResult {
  final PdfImportStatus status;
  final String? filePath;
  final String? extractedText;
  final String? errorMessage;

  /// Ratei (Ferie, Permessi R.O.L., Ex festività) letti per COORDINATE
  /// dalla tabella "RATEI" della prima pagina del PDF — vedi
  /// [PdfImportService.estraiDaBytes] e la doc di libreria in
  /// `busta_paga_regex_parser.dart`. `null` quando l'estrazione per
  /// coordinate non ha riconosciuto la tabella (mai un errore bloccante:
  /// resta comunque disponibile [extractedText] per il percorso testuale
  /// di fallback in [BustaPagaRegexParser.parse]).
  final RateiEstrattiDaCoordinate? ratei;

  /// Voci (tabella "VOCE/DESCRIZIONE/.../TRATTENUTE/COMPETENZE", contributi
  /// C/DIPENDENTE, IRPEF trattenuta, riga totali) lette per COORDINATE dalla
  /// prima pagina del PDF — vedi [PdfImportService.estraiDaBytes] e
  /// [classificaVociDaCoordinate]. Stessa natura "mai bloccante" di [ratei]:
  /// `null` quando l'estrazione per coordinate non ha riconosciuto la
  /// tabella, con [extractedText] sempre disponibile come fallback.
  final VociEstratteDaCoordinate? voci;

  const PdfImportResult._(
    this.status, {
    this.filePath,
    this.extractedText,
    this.errorMessage,
    this.ratei,
    this.voci,
  });

  const PdfImportResult.success(
    String filePath, {
    String? extractedText,
    RateiEstrattiDaCoordinate? ratei,
    VociEstratteDaCoordinate? voci,
  }) : this._(
          PdfImportStatus.success,
          filePath: filePath,
          extractedText: extractedText,
          ratei: ratei,
          voci: voci,
        );

  const PdfImportResult.cancelled() : this._(PdfImportStatus.cancelled);

  const PdfImportResult.noExtractableText()
      : this._(PdfImportStatus.noExtractableText);

  const PdfImportResult.error(String message)
      : this._(PdfImportStatus.error, errorMessage: message);
}

/// Import di un PDF busta paga: selezione tramite file picker di sistema,
/// validazione che il testo sia estraibile (niente OCR in v1, vedi
/// CLAUDE.md), copia nella cartella documenti locale dell'app
/// (`buste_paga_pdf/`, sotto-cartella dedicata dell'Application Documents
/// Directory) così il file resta disponibile anche se l'originale scelto
/// dall'utente viene spostato o cancellato altrove.
class PdfImportService {
  const PdfImportService();

  static const _pdfTypeGroup = XTypeGroup(
    label: 'PDF',
    extensions: ['pdf'],
    uniformTypeIdentifiers: ['com.adobe.pdf'],
  );

  Future<PdfImportResult> pickAndImport() async {
    final XFile? picked = await openFile(
      acceptedTypeGroups: const [_pdfTypeGroup],
    );
    if (picked == null) return const PdfImportResult.cancelled();

    try {
      final bytes = await picked.readAsBytes();

      final estratti = estraiDaBytes(bytes);
      final text = estratti.testo;
      // Soglia minima per distinguere un PDF testuale da uno scansionato
      // (che a volte espone comunque qualche carattere spurio di metadata).
      if (text == null || text.trim().length <= 20) {
        return const PdfImportResult.noExtractableText();
      }

      final targetPath = await _copyToAppDocuments(picked.name, bytes);
      return PdfImportResult.success(
        targetPath,
        extractedText: text,
        ratei: estratti.ratei,
        voci: estratti.voci,
      );
    } catch (e) {
      return PdfImportResult.error(e.toString());
    }
  }

  /// Elimina un PDF copiato in `buste_paga_pdf/` durante un import poi
  /// scartato — ad es. quando il controllo anti-duplicati blocca il flusso
  /// subito dopo la copia del file, prima ancora di aprire il form di
  /// revisione, oppure quando una busta paga viene rimossa dall'archivio.
  /// Silenzioso se il file è già assente (best-effort, non propaga errori:
  /// è solo pulizia di un file orfano, non deve mai bloccare il chiamante).
  Future<void> deleteFile(String relativePath) async {
    try {
      final absolutePath = await resolvePdfAbsolutePath(relativePath);
      final file = File(absolutePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // File già assente/non eliminabile: nessun errore da propagare.
    }
  }

  /// Testo linearizzato (percorso storico, usato da
  /// [BustaPagaRegexParser.parse] per tutti i campi tranne, quando
  /// disponibili, ratei/voci) più ratei e voci letti per COORDINATE
  /// (percorso più affidabile quando disponibile, vedi [_paroleprimaPagina]
  /// /[classificaRateiDaCoordinate]/[classificaVociDaCoordinate]), estratti
  /// dallo stesso [PdfDocument] in un solo passaggio (un solo parsing del
  /// file, un solo dispose, un'unica lettura delle parole della prima
  /// pagina condivisa da entrambe le classificazioni).
  ///
  /// PUBBLICO (non solo uso interno di [pickAndImport]) apposta per essere
  /// testabile direttamente su bytes di PDF reali, senza passare dal file
  /// picker di sistema — vedi il test di accettazione sui PDF reali in
  /// `test/pdf_voci_coordinate_test.dart`.
  ({
    String? testo,
    RateiEstrattiDaCoordinate? ratei,
    VociEstratteDaCoordinate? voci,
  }) estraiDaBytes(List<int> bytes) {
    final document = PdfDocument(inputBytes: bytes);
    try {
      final testo = PdfTextExtractor(document).extractText();
      final parole = _paroleprimaPagina(document);
      final ratei = parole == null
          ? null
          : classificaRateiDaCoordinate([
              for (final p in parole)
                (
                  testo: p.testo,
                  bordoSuperiore: p.bordoSuperiore,
                  bordoDestro: p.bordoDestro,
                ),
            ]);
      final voci = parole == null ? null : classificaVociDaCoordinate(parole);
      return (testo: testo, ratei: ratei, voci: voci);
    } finally {
      document.dispose();
    }
  }

  /// Adattamento SYNCFUSION-specifico: legge le parole (con le rispettive
  /// coordinate) della PRIMA pagina del PDF — dove il layout del software
  /// payroll "JOB" stampa sia la tabella "RATEI" (Ferie, Permessi R.O.L., Ex
  /// festività) sia la tabella voci/contributi/riga totali, vedi doc di
  /// libreria in `busta_paga_regex_parser.dart` — pronte per
  /// [classificaRateiDaCoordinate] e [classificaVociDaCoordinate], le parti
  /// PURE (nessuna dipendenza da Syncfusion/da un PDF reale, testabili con
  /// dati semplici — vedi `test/pdf_ratei_coordinate_test.dart` e
  /// `test/pdf_voci_coordinate_test.dart`) che fanno la classificazione vera
  /// e propria in righe/colonne.
  ///
  /// Percorso più affidabile del testo linearizzato (`extractText()`), che
  /// perde l'allineamento a colonna delle tabelle: qui la posizione di ogni
  /// parola sulla pagina resta univoca, quindi si distingue correttamente
  /// una cella vuota (nessun dato) da una cella con "0,00" effettivamente
  /// stampato, e due colonne concatenate senza separatore nel testo
  /// linearizzato (es. TRATTENUTE/COMPETENZE, C/DIPENDENTE/C/DITTA) restano
  /// distinguibili.
  ///
  /// Ritorna `null` (mai un'eccezione, che farebbe fallire l'intero import
  /// anche quando il testo semplice è comunque stato estratto correttamente)
  /// se la PAGINA non è nemmeno leggibile — es. PDF senza pagine, o
  /// `extractTextLines` che solleva un'eccezione su un layout radicalmente
  /// diverso: è un arricchimento best-effort, [BustaPagaRegexParser.parse]
  /// ricade comunque sul percorso testuale quando questo manca.
  List<ParolaVoce>? _paroleprimaPagina(PdfDocument document) {
    try {
      if (document.pages.count == 0) return null;
      final lines = PdfTextExtractor(document).extractTextLines(
        startPageIndex: 0,
        endPageIndex: 0,
      );

      return [
        for (final line in lines)
          for (final word in line.wordCollection)
            (
              testo: word.text,
              bordoSuperiore: word.bounds.top,
              bordoSinistro: word.bounds.left,
              bordoDestro: word.bounds.right,
            ),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<String> _copyToAppDocuments(
    String sourceFileName,
    List<int> bytes,
  ) async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final targetDir = Directory(p.join(documentsDir.path, pdfBusteDirName));
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${p.basename(sourceFileName)}';
    final targetFile = File(p.join(targetDir.path, fileName));
    try {
      await targetFile.writeAsBytes(bytes);
    } catch (e) {
      // Scrittura fallita a metà: ripulisce l'eventuale file parziale
      // rimasto su disco prima di ripropagare l'errore, stesso pattern di
      // cleanup usato altrove in questo file per gli altri percorsi di
      // errore (duplicato, formato non riconosciuto, rinomina fallita).
      if (await targetFile.exists()) {
        try {
          await targetFile.delete();
        } catch (_) {
          // Best-effort: non deve mascherare l'errore originale.
        }
      }
      rethrow;
    }
    // Path RELATIVO alla Application Documents Directory (mai il prefisso
    // assoluto: su iOS include l'UUID del container sandbox, che cambia ad
    // ogni reinstallazione — vedi `pdf_path_resolver.dart`).
    return p.join(pdfBusteDirName, fileName);
  }

  /// Rinomina (stessa cartella) il PDF di una mensilità supplementare col
  /// testo letterale della busta ("Mens.supplementare MM/YYYY"), "/" → "-"
  /// perché non valido in un nome file — al posto del nome scelto dal
  /// picker di sistema, spesso poco significativo (screenshot, export
  /// generico). Il nome include anche [tipo] (13a/14a): il controllo
  /// anti-duplicati confronta tipo+anno, non solo mese+anno, quindi due
  /// buste paga di tipo diverso possono legittimamente avere lo stesso
  /// mese/anno letto dal PDF — senza il tipo nel nome, la seconda
  /// `File.rename()` sovrascriverebbe silenziosamente il file della prima.
  Future<String> rinominaPerSupplementare(
    String currentPath, {
    required int mese,
    required int anno,
    required TipoBustaPaga tipo,
  }) async {
    final absolutePath = await resolvePdfAbsolutePath(currentPath);
    final suffissoTipo = switch (tipo) {
      TipoBustaPaga.tredicesima => '13a',
      TipoBustaPaga.quattordicesima => '14a',
      TipoBustaPaga.mensile => 'mensile',
    };
    final nuovoNomeFile = 'Mens.supplementare $mese-$anno ($suffissoTipo).pdf';
    final nuovoPercorso = p.join(p.dirname(absolutePath), nuovoNomeFile);
    await File(absolutePath).rename(nuovoPercorso);
    // Ritorna il nuovo path RELATIVO, coerente con `_copyToAppDocuments`.
    return p.join(pdfBusteDirName, nuovoNomeFile);
  }
}

// =============================================================================
// Classificazione dei ratei per coordinate — PARTE PURA
//
// Tutto quanto segue non dipende da Syncfusion né da un PDF reale: prende in
// input solo (testo, coordinate) di ciascuna parola della pagina e produce un
// [RateiEstrattiDaCoordinate]. Isolata qui apposta per essere testabile con
// dati semplici costruiti a mano — vedi `test/pdf_ratei_coordinate_test.dart`
// — invece che solo indirettamente tramite un `TextWord` di Syncfusion (che
// richiederebbe un PDF reale per essere costruito). Il solo punto di contatto
// con Syncfusion è [PdfImportService._paroleprimaPagina] sopra, che adatta
// `TextWord` a [ParolaRateo].
// =============================================================================

/// Una singola parola della pagina PDF ridotta ai soli dati che servono a
/// [classificaRateiDaCoordinate]: il testo grezzo e le due coordinate usate
/// come ancora per riga/colonna (bordo superiore Y, bordo destro X) — non
/// l'intero `Rect`/`TextWord` di Syncfusion, per restare un dato semplice,
/// costruibile a mano nei test senza un PDF reale.
typedef ParolaRateo = ({
  String testo,
  double bordoSuperiore,
  double bordoDestro,
});

/// Classifica le parole della prima pagina del PDF (ridotte a [ParolaRateo])
/// nella tabella "RATEI" (Ferie, Permessi R.O.L., Ex festività) del layout
/// del software payroll "JOB", e le combina in [RateiEstrattiDaCoordinate].
///
/// Per ogni parola: se il testo non è un numero di rateo valido (vedi
/// [_numeroRateoDaCoordinate]) la parola è ignorata; altrimenti il bordo
/// superiore ne determina la riga/categoria (vedi
/// [_rigaPerBordoSuperiore]: Ferie/ROL/Ex festività) e il bordo destro la
/// colonna (vedi [_colonnaPerBordoDestro]: una delle 5 colonne della
/// tabella) — se riga o colonna non sono riconosciute (coordinate fuori da
/// ogni banda/tolleranza nota) la parola è ignorata anziché assegnata a una
/// riga/colonna sbagliata. I valori raccolti per ciascuna riga sono infine
/// combinati in un [RateoCategoria] da [_categoriaDaValoriColonna].
///
/// Mai un'eccezione e mai un dato inventato: una tabella non riconoscibile
/// (nessuna parola classificata) produce un [RateiEstrattiDaCoordinate] con
/// le 3 categorie tutte [RateoCategoria.vuoto], non un errore.
RateiEstrattiDaCoordinate classificaRateiDaCoordinate(
  Iterable<ParolaRateo> parole,
) {
  final valori = <_RigaRateo, Map<_ColonnaRateo, double>>{
    for (final riga in _RigaRateo.values) riga: <_ColonnaRateo, double>{},
  };

  for (final parola in parole) {
    final valore = _numeroRateoDaCoordinate(parola.testo);
    if (valore == null) continue;
    final riga = _rigaPerBordoSuperiore(parola.bordoSuperiore);
    if (riga == null) continue;
    final colonna = _colonnaPerBordoDestro(parola.bordoDestro);
    if (colonna == null) continue;
    valori[riga]![colonna] = valore;
  }

  return RateiEstrattiDaCoordinate(
    ferie: _categoriaDaValoriColonna(valori[_RigaRateo.ferie]!),
    rol: _categoriaDaValoriColonna(valori[_RigaRateo.rol]!),
    exFestivita: _categoriaDaValoriColonna(valori[_RigaRateo.exFestivita]!),
  );
}

/// Combina le 5 colonne lette per una categoria in [RateoCategoria]. Le due
/// sotto-colonne "GODUTI A.P."/"GODUTI A.C." si sommano in un unico
/// `goduto`: `null` solo se NESSUNA delle due è stata letta (vedi doc su
/// [RateoCategoria.goduto]), non se una delle due manca — in quel caso la
/// mancante conta 0 nella somma, non annulla l'altra.
RateoCategoria _categoriaDaValoriColonna(Map<_ColonnaRateo, double> valori) {
  final godutoAP = valori[_ColonnaRateo.godutoAnnoPrecedente];
  final godutoAC = valori[_ColonnaRateo.godutoAnnoCorrente];
  final goduto = (godutoAP == null && godutoAC == null)
      ? null
      : (godutoAP ?? 0) + (godutoAC ?? 0);
  return RateoCategoria(
    residuoAnnoPrecedente: valori[_ColonnaRateo.residuoAnnoPrecedente],
    maturato: valori[_ColonnaRateo.maturato],
    goduto: goduto,
    residuo: valori[_ColonnaRateo.residuoTotali],
  );
}

/// Riga (categoria) di appartenenza in base al bordo superiore (Y) della
/// parola — bande empiriche verificate su 4 PDF reali (mesi/anni diversi):
/// Ferie/ROL/Ex festività osservate rispettivamente a Y≈205/224/244, separate
/// da margini puliti di ~10pt fra una riga e la successiva (scostamento fra
/// documenti sotto il punto, jitter di rendering); le soglie sotto tagliano
/// a metà di quei margini, con ampio margine per assorbire eventuale
/// ulteriore variazione mai osservata sul campione disponibile.
_RigaRateo? _rigaPerBordoSuperiore(double top) {
  if (top >= 200 && top < 217) return _RigaRateo.ferie;
  if (top >= 217 && top < 237) return _RigaRateo.rol;
  if (top >= 237 && top < 258) return _RigaRateo.exFestivita;
  return null;
}

/// Colonna di appartenenza in base al bordo destro (X) della parola, scelta
/// come l'ancora più vicina fra le 5 di [_colonneBordoDestroX] (le colonne
/// sono allineate a destra: il bordo destro di un numero resta fisso
/// indipendentemente da quante cifre ha, a differenza del bordo sinistro) —
/// `null` se anche l'ancora più vicina è oltre [_tolleranzaColonnaMax], cioè
/// la parola non appartiene a nessuna colonna nota. Implementata in termini
/// di [_anchorMatch] (sezione "Helper condivisi" più sotto in questo file):
/// stessa regola di matching riusata anche dalla classificazione delle voci
/// (totali/flag), un'unica implementazione per non farle divergere.
_ColonnaRateo? _colonnaPerBordoDestro(double right) =>
    _anchorMatch(right, _colonneBordoDestroX, _tolleranzaColonnaMax);

/// Bordo destro (X) di riferimento delle 5 colonne della tabella "RATEI",
/// nell'ordine "RESIDUI A.P." / "MATURATI" / "GODUTI A.P." / "GODUTI A.C." /
/// "RESIDUI TOTALI" — valori empirici (punto medio delle osservazioni sui 4
/// PDF di riferimento, scostamento reciproco fra documenti sotto il punto).
/// Colonne equidistanti di circa 38-41pt.
const Map<_ColonnaRateo, double> _colonneBordoDestroX = {
  _ColonnaRateo.residuoAnnoPrecedente: 113.6,
  _ColonnaRateo.maturato: 151.8,
  _ColonnaRateo.godutoAnnoPrecedente: 190.1,
  _ColonnaRateo.godutoAnnoCorrente: 229.7,
  _ColonnaRateo.residuoTotali: 270.6,
};

// Le colonne sono equidistanti di circa 38-41pt (vedi ancore sopra): una
// tolleranza di metà di quel passo lascia margine sufficiente da entrambi i
// lati del punto medio fra due colonne adiacenti, senza mai poter confondere
// due colonne contigue anche con più jitter di rendering di quanto osservato
// sul campione disponibile.
const double _tolleranzaColonnaMax = 16;

// Un numero di rateo così come stampato nella tabella (2 decimali, eventuale
// separatore delle migliaia ".", segno "-" opzionale pur non essendo mai
// stato osservato su questa tabella) — stessa forma di
// `_numeroRateo`/`_totaleCompetenzeDopoOreLavorate` in
// `busta_paga_regex_parser.dart`. Match sull'intera parola (non una ricerca
// `allMatches`): a differenza del percorso testuale, qui ogni [ParolaRateo]
// è già un token isolato dal layout della pagina, non serve separarlo da
// testo adiacente.
final RegExp _numeroCoordinataPattern = RegExp(r'^-?[\d.]+,\d{2}$');

double? _numeroRateoDaCoordinate(String testo) {
  final t = testo.trim();
  if (!_numeroCoordinataPattern.hasMatch(t)) return null;
  return double.parse(t.replaceAll('.', '').replaceAll(',', '.'));
}

/// Le 3 categorie (righe) della tabella "RATEI" del PDF, individuate dal
/// bordo superiore (Y) delle parole sulla riga — vedi
/// [_rigaPerBordoSuperiore].
enum _RigaRateo { ferie, rol, exFestivita }

/// Le 5 colonne (allineate a destra) della tabella "RATEI" del PDF,
/// individuate dal bordo destro (X) della parola — vedi
/// [_colonnaPerBordoDestro].
enum _ColonnaRateo {
  residuoAnnoPrecedente,
  maturato,
  godutoAnnoPrecedente,
  godutoAnnoCorrente,
  residuoTotali,
}

// =============================================================================
// Classificazione delle voci (tabella VOCE/DESCRIZIONE/TRATTENUTE/COMPETENZE,
// contributi C/DIPENDENTE, IRPEF trattenuta, riga totali) per coordinate —
// PARTE PURA
//
// Stessa architettura della sezione ratei sopra: nessuna dipendenza da
// Syncfusion né da un PDF reale, prende in input solo (testo, coordinate) di
// ciascuna parola della pagina e produce un [VociEstratteDaCoordinate].
// Isolata apposta per essere testabile con dati semplici costruiti a mano —
// vedi `test/pdf_voci_coordinate_test.dart` — invece che solo indirettamente
// tramite un `TextWord` di Syncfusion. Il solo punto di contatto con
// Syncfusion è [PdfImportService._paroleprimaPagina] sopra.
//
// Motivazione (vedi anche doc di libreria in testa a
// `busta_paga_regex_parser.dart`): `PdfTextExtractor.extractText()`
// linearizza il testo e perde la distinzione fra le colonne TRATTENUTE e
// COMPETENZE della tabella voci, e fra C/DIPENDENTE e C/DITTA della tabella
// contributi — la posizione X/Y di ogni parola sulla pagina resta invece
// univoca.
// =============================================================================

/// Una singola parola della pagina PDF ridotta ai soli dati che servono a
/// [classificaVociDaCoordinate]: il testo grezzo e le coordinate usate come
/// ancora per riga/colonna (bordo superiore Y, bordo sinistro X, bordo
/// destro X) — a differenza di [ParolaRateo] serve anche il bordo sinistro,
/// necessario per ricostruire testo libero allineato a sinistra (descrizioni
/// di voci/contributi), non solo colonne numeriche allineate a destra.
/// Classifica le parole della prima pagina del PDF (ridotte a [ParolaVoce])
/// nella tabella voci, nella tabella contributi, nella trattenuta IRPEF e
/// nella riga totali del layout del software payroll "JOB", combinandole in
/// un [VociEstratteDaCoordinate].
///
/// Mai un'eccezione e mai un dato inventato: un input che non contiene
/// nessuna di queste strutture (lista vuota, o parole che non cadono in
/// nessuna banda/colonna nota) produce un [VociEstratteDaCoordinate] "vuoto"
/// ([VociEstratteDaCoordinate.haDatiSufficienti] `false`), non un errore —
/// [BustaPagaRegexParser.parse] ricade in quel caso sul percorso testuale.
VociEstratteDaCoordinate classificaVociDaCoordinate(
  Iterable<ParolaVoce> parole,
) {
  final elenco = parole.toList();

  final righeVoce = _clusterizzaRighe(
    elenco,
    yMin: _yVoceMin,
    yMax: _yVoceMax,
  ).map(_classificaRigaVoce).whereType<RigaVoceCoordinate>().toList();

  final contributiDipendente = <String, double>{};
  for (final riga in _clusterizzaRighe(
    elenco,
    yMin: _yContributiMin,
    yMax: _yContributiMax,
  )) {
    final classificata = _classificaRigaContributo(riga);
    if (classificata != null) {
      contributiDipendente[classificata.descrizione] = classificata.importo;
    }
  }

  return VociEstratteDaCoordinate(
    righe: righeVoce,
    contributiDipendente: contributiDipendente,
    irpefTrattenuta: _estraiIrpefTrattenuta(elenco),
    totali: _estraiTotali(elenco),
  );
}

// --- Raggruppamento in righe -------------------------------------------

/// Raggruppa le parole (filtrate alla banda verticale [yMin, yMax)) in
/// righe visive: parole ordinate per bordo superiore (Y) crescente, poi
/// incatenate nella stessa riga finché la distanza dal bordo superiore
/// della parola precedente resta entro [_tolleranzaRiga] — le parole di una
/// stessa riga della tabella condividono lo stesso Y (a meno di un jitter
/// di rendering sotto il punto, osservato fino a ~0.4pt fra l'etichetta e i
/// valori di una stessa riga contributi), mentre righe distinte sono
/// separate da almeno ~9pt: un'unica tolleranza piccola (1.5pt) incatena
/// correttamente le parole di una riga senza mai fondere due righe
/// contigue. Testo estraneo che casualmente cade nella stessa banda
/// verticale (es. la legenda verticale "* = C - Imponibile..." a destra
/// della tabella voci) può finire nella stessa riga di un dato reale, ma
/// viene comunque scartato più avanti dalla classificazione per colonna
/// (nessuna ancora nota alla sua posizione X) — vedi [_classificaRigaVoce].
List<List<ParolaVoce>> _clusterizzaRighe(
  Iterable<ParolaVoce> parole, {
  required double yMin,
  required double yMax,
  double tolleranza = _tolleranzaRiga,
}) {
  final filtrate = parole
      .where((p) => p.bordoSuperiore >= yMin && p.bordoSuperiore < yMax)
      .toList()
    ..sort((a, b) => a.bordoSuperiore.compareTo(b.bordoSuperiore));

  final righe = <List<ParolaVoce>>[];
  for (final p in filtrate) {
    if (righe.isEmpty ||
        (p.bordoSuperiore - righe.last.last.bordoSuperiore) > tolleranza) {
      righe.add([p]);
    } else {
      righe.last.add(p);
    }
  }
  return righe;
}

const double _tolleranzaRiga = 1.5;

// --- Tabella voci (VOCE/DESCRIZIONE/Quantita'/Base/TRATTENUTE/COMPETENZE) --

// Banda verticale della tabella voci: dalla riga subito sotto l'intestazione
// di colonna (Y≈282.9) alla riga subito sopra l'intestazione della tabella
// contributi (Y≈588.9) — margine ampio, il numero di righe varia da un
// minimo di 1 (mensilità supplementari) a diverse decine su un cedolino
// affollato.
const double _yVoceMin = 284.0;
const double _yVoceMax = 585.0;

// Ancore X (bordo destro, colonne allineate a destra) verificate su più PDF
// reali dello stesso layout — vedi ground truth nella sessione di fix.
const double _xCodiceDestro = 45.6;
const double _tolleranzaCodice = 5.0;

// Zona (bordo sinistro, non un'ancora singola: testo libero di larghezza
// variabile) della descrizione — fra la colonna codice (right max ~45.7) e
// la colonna anno/tag (left min ~254.0/~273.6).
const double _xDescrizioneSinistroMin = 48.0;
const double _xDescrizioneSinistroMax = 250.0;

const double _xTagSinistro = 273.6;
const double _tolleranzaTag = 5.0;
const _tagVociNoti = {'GIORNI', 'ORE', 'RATEI'};

const double _xQuantitaDestro = 352.4;
const double _tolleranzaQuantita = 8.0;

const double _xTrattenuteDestro = 461.7;
const double _xCompetenzeDestro = 517.6;
const double _tolleranzaImportoVoce = 20.0;

// Le 4 colonne flag (C/I/T/N, allineate a destra) in fondo alla tabella
// voci — solo [_FlagVoce.n] è usato da [RigaVoceCoordinate.flagN] (unico
// flag rilevante per la classificazione, vedi doc su
// `RigaVoceCoordinate.flagN` in `busta_paga_regex_parser.dart`), le altre 3
// servono solo a disambiguare la colonna più vicina quando si legge un "*".
enum _FlagVoce { c, i, t, n }

const Map<_FlagVoce, double> _ancoreFlag = {
  _FlagVoce.c: 528.9,
  _FlagVoce.i: 538.5,
  _FlagVoce.t: 549.5,
  _FlagVoce.n: 559.1,
};
const double _tolleranzaFlag = 5.0;

/// Classifica le parole di UNA riga (già raggruppate da [_clusterizzaRighe])
/// della tabella voci. Richiede un codice voce (colonna più a sinistra,
/// numero puro) E almeno un importo (colonna TRATTENUTE o COMPETENZE): le
/// righe senza importo (es. "210 Permessi riduz. orario goduti", solo
/// quantità) non sono di interesse qui — restano gestite altrove
/// (`permessiGodutiMese`) — e un cluster senza nemmeno un codice voce non è
/// una riga della tabella (es. rumore della legenda verticale che cade
/// nella stessa banda Y). Ritorna `null` in questi casi.
RigaVoceCoordinate? _classificaRigaVoce(List<ParolaVoce> parole) {
  String? codice;
  final descrizioneParole = <ParolaVoce>[];
  String? tag;
  // `null` (non 0): resta `null` se la riga non stampa alcuna quantità (es.
  // "930 Trattamento integrativo DL 3/2020", nessun tag GIORNI/ORE/RATEI) —
  // distinto da 0 stampato esplicitamente, vedi `RigaVoceCoordinate.quantita`
  // /`VoceCompetenza.quantita`.
  double? quantita;
  double? importoTrattenute;
  double? importoCompetenze;
  var flagN = false;

  for (final p in parole) {
    final t = p.testo.trim();
    if (t.isEmpty) continue;

    if (t == '*') {
      if (_anchorMatch(p.bordoDestro, _ancoreFlag, _tolleranzaFlag) ==
          _FlagVoce.n) {
        flagN = true;
      }
      continue;
    }

    if (_soloCifre.hasMatch(t) &&
        (p.bordoDestro - _xCodiceDestro).abs() <= _tolleranzaCodice) {
      codice = t;
      continue;
    }

    if (_tagVociNoti.contains(t) &&
        (p.bordoSinistro - _xTagSinistro).abs() <= _tolleranzaTag) {
      tag = t;
      continue;
    }

    final quantitaValore = _numeroQuantita(t);
    if (quantitaValore != null &&
        (p.bordoDestro - _xQuantitaDestro).abs() <= _tolleranzaQuantita) {
      quantita = quantitaValore;
      continue;
    }

    final importoValore = _numeroMoneta(t);
    if (importoValore != null) {
      if ((p.bordoDestro - _xTrattenuteDestro).abs() <=
          _tolleranzaImportoVoce) {
        importoTrattenute = importoValore;
        continue;
      }
      if ((p.bordoDestro - _xCompetenzeDestro).abs() <=
          _tolleranzaImportoVoce) {
        importoCompetenze = importoValore;
        continue;
      }
      // Numero riconosciuto ma fuori da entrambe le colonne note (es. la
      // "Base"/tariffa oraria, a 2-5 decimali ma con un bordo destro
      // proprio): ignorato, non entra comunque nella descrizione.
      continue;
    }

    if (p.bordoSinistro >= _xDescrizioneSinistroMin &&
        p.bordoSinistro < _xDescrizioneSinistroMax) {
      descrizioneParole.add(p);
    }
  }

  if (codice == null) return null;
  final importo = importoCompetenze ?? importoTrattenute;
  if (importo == null) return null;

  descrizioneParole.sort((a, b) => a.bordoSinistro.compareTo(b.bordoSinistro));
  final descrizione = _unisciParoleDescrizione(descrizioneParole);

  return RigaVoceCoordinate(
    codice: codice,
    descrizione: descrizione,
    tag: tag,
    quantita: quantita,
    importo: importo,
    colonna: importoCompetenze != null
        ? ColonnaVoceCoordinate.competenze
        : ColonnaVoceCoordinate.trattenute,
    flagN: flagN,
    // Caso anomalo: entrambe le colonne valorizzate sulla stessa riga.
    // `importoTrattenute` viene scartato in silenzio dalla riga sopra (solo
    // `importoCompetenze` è usato quando presente) — segnalato qui perché
    // `BustaPagaRegexParser.parse` possa aggiungere un warning esplicito.
    entrambeColonneValorizzate:
        importoCompetenze != null && importoTrattenute != null,
  );
}

// --- Tabella contributi (DESCRIZIONE CONTRIBUTO/IMPONIBILE/%C/DIP/
// C/DIPENDENTE/C/DITTA) --------------------------------------------------

// Banda verticale: dalla riga subito sotto l'intestazione (Y≈588.9) alla
// riga subito sopra l'intestazione del blocco Q.T.A. successivo (Y≈637.1).
const double _yContributiMin = 590.0;
const double _yContributiMax = 636.0;

// Zona (bordo sinistro) della descrizione del contributo — il nome del
// contributo (es. "INPS", "CONTRIBUTO EBILOG", "FONDO INTEGR. SALARIALE -
// FIS") può occupare sia la colonna di intestazione "DESCRIZIONE" sia
// "CONTRIBUTO" (il nome è più largo di una singola colonna su questo
// layout): soglia a metà strada fra il bordo destro più a destra osservato
// per questi nomi (~119.0) e il bordo sinistro della prima colonna
// numerica, IMPONIBILE (~122.4).
const double _xContributiDescrizioneMax = 121.0;

const double _xContributoDipendenteDestro = 213.2;
const double _tolleranzaContributoDipendente = 6.0;

/// Classifica le parole di UNA riga della tabella contributi: descrizione
/// (testo libero a sinistra) + importo della quota C/DIPENDENTE. `null` se
/// manca l'uno o l'altro (es. un cluster di rumore che cade nella stessa
/// banda Y senza contenere una riga di contributo reale).
({String descrizione, double importo})? _classificaRigaContributo(
  List<ParolaVoce> parole,
) {
  final descrizioneParole = <ParolaVoce>[];
  double? importoDipendente;

  for (final p in parole) {
    final t = p.testo.trim();
    if (t.isEmpty) continue;

    final valore = _numeroMoneta(t);
    if (valore != null) {
      if ((p.bordoDestro - _xContributoDipendenteDestro).abs() <=
          _tolleranzaContributoDipendente) {
        importoDipendente = valore;
      }
      // Altri numeri della riga (imponibile, %, quota C/DITTA): ignorati,
      // mai una trattenuta del dipendente — vedi doc su
      // [VociEstratteDaCoordinate.contributiDipendente].
      continue;
    }

    if (p.bordoSinistro < _xContributiDescrizioneMax) {
      descrizioneParole.add(p);
    }
  }

  if (importoDipendente == null || descrizioneParole.isEmpty) return null;
  descrizioneParole.sort((a, b) => a.bordoSinistro.compareTo(b.bordoSinistro));
  final descrizione = _unisciParoleDescrizione(descrizioneParole);
  return (descrizione: descrizione, importo: importoDipendente);
}

// --- IRPEF trattenuta ("IRPEF + IMP. SOST.") -----------------------------

// Banda verticale ampia apposta: su un cedolino con conguaglio di dicembre
// il blocco IRPEF viene stampato più in basso del solito (Y≈735.7 invece di
// Y≈688.8) — questa banda copre comodamente entrambi i casi restando ben
// sopra la riga totali (Y≈796) e ben sotto il blocco Q.T.A. (Y≈637-657), che
// stampano entrambi altri numeri sulla stessa porzione orizzontale della
// pagina.
const double _yIrpefMin = 660.0;
const double _yIrpefMax = 750.0;
const double _xIrpefTrattenutaDestro = 556.1;
const double _tolleranzaIrpef = 3.0;

/// Trattenuta IRPEF, cercata SOLO nella banda [_yIrpefMin, _yIrpefMax) e
/// sull'ancora X [_xIrpefTrattenutaDestro] — se emergono PIÙ valori diversi
/// in quella banda/colonna (ancoraggio ambiguo per questo documento, mai
/// osservato sui PDF di riferimento ma non impossibile su un layout
/// leggermente diverso) ritorna `null` invece di sceglierne uno a caso:
/// meglio ricadere sul percorso testuale che restituire un dato incerto.
double? _estraiIrpefTrattenuta(Iterable<ParolaVoce> parole) {
  final trovati = <double>{};
  for (final p in parole) {
    if (p.bordoSuperiore < _yIrpefMin || p.bordoSuperiore >= _yIrpefMax) {
      continue;
    }
    if ((p.bordoDestro - _xIrpefTrattenutaDestro).abs() > _tolleranzaIrpef) {
      continue;
    }
    final valore = _numeroMoneta(p.testo.trim());
    if (valore != null) trovati.add(valore);
  }
  return trovati.length == 1 ? trovati.first : null;
}

// --- Riga totali (TOTALE COMPETENZE/TOTALE TRATTENUTE/ARR. PRECED./
// ARR. ATTUALE/NETTO IN BUSTA) --------------------------------------------

const double _yTotaliMin = 790.0;
const double _yTotaliMax = 802.0;

enum _ColonnaTotali { competenze, trattenute, arrPreced, arrAttuale, netto }

const Map<_ColonnaTotali, double> _ancoreTotali = {
  _ColonnaTotali.competenze: 293.9,
  _ColonnaTotali.trattenute: 358.1,
  _ColonnaTotali.arrPreced: 414.0,
  _ColonnaTotali.arrAttuale: 464.5,
  _ColonnaTotali.netto: 558.5,
};
const double _tolleranzaTotali = 20.0;

/// Riga totali del cedolino — `null` quando anche solo una delle 3 colonne
/// non opzionali (competenze/trattenute/netto: ARR. PRECED./ARR. ATTUALE
/// sono legittimamente assenti la maggior parte dei mesi, vedi
/// [TotaliCoordinate]) non è stata trovata nella banda verticale attesa.
TotaliCoordinate? _estraiTotali(Iterable<ParolaVoce> parole) {
  final valori = <_ColonnaTotali, double>{};
  for (final p in parole) {
    if (p.bordoSuperiore < _yTotaliMin || p.bordoSuperiore >= _yTotaliMax) {
      continue;
    }
    final valore = _numeroMoneta(p.testo.trim());
    if (valore == null) continue;
    final colonna =
        _anchorMatch(p.bordoDestro, _ancoreTotali, _tolleranzaTotali);
    if (colonna == null) continue;
    valori[colonna] = valore;
  }

  final competenze = valori[_ColonnaTotali.competenze];
  final trattenute = valori[_ColonnaTotali.trattenute];
  final netto = valori[_ColonnaTotali.netto];
  if (competenze == null || trattenute == null || netto == null) return null;

  return TotaliCoordinate(
    totaleCompetenze: competenze,
    totaleTrattenute: trattenute,
    arrPreced: valori[_ColonnaTotali.arrPreced] ?? 0,
    arrAttuale: valori[_ColonnaTotali.arrAttuale] ?? 0,
    nettoInBusta: netto,
  );
}

// --- Helper condivisi -----------------------------------------------------

/// Ancora più vicina fra quelle di [ancore], `null` se anche la più vicina
/// è oltre [tolleranza] — generalizza a un `Map<T, double>` di ancore
/// qualsiasi la regola di matching già usata da [_colonnaPerBordoDestro]
/// sopra (sezione ratei, unica altra implementazione prima di questo
/// helper), riusata qui anche per i 5 totali e i 4 flag.
T? _anchorMatch<T>(double valore, Map<T, double> ancore, double tolleranza) {
  T? migliore;
  var distanzaMinima = double.infinity;
  for (final entry in ancore.entries) {
    final distanza = (entry.value - valore).abs();
    if (distanza < distanzaMinima) {
      distanzaMinima = distanza;
      migliore = entry.key;
    }
  }
  return distanzaMinima <= tolleranza ? migliore : null;
}

/// Soglia (in pt) sul gap orizzontale fra due parole ADIACENTI di una
/// descrizione (già ordinate per bordo sinistro crescente) sopra la quale
/// [_unisciParoleDescrizione] le unisce CON uno spazio — sotto la soglia
/// restano concatenate SENZA spazio. Necessaria perché
/// `syncfusion_flutter_pdf` a volte spezza una singola parola stampata per
/// intero sul PDF in più `TextWord` adiacenti (bug di dati reale, non
/// un'ipotesi: osservato su cedolini reali, "Fe"/"stivita'" invece di
/// "Festivita'", "Tr"/"attamento" invece di "Trattamento") — l'assemblaggio
/// precedente (un `.join(' ')` incondizionato su tutte le parole) inseriva
/// sempre uno spazio anche in questo caso, corrompendo la descrizione a metà
/// parola.
///
/// Valori empirici misurati su PDF reali (stessa riga Y, gap fra il bordo
/// destro della parola precedente e il bordo sinistro della successiva):
/// - parole spezzate della STESSA parola dall'artefatto di Syncfusion: gap
///   0,0-0,1pt ("Fe"->"stivita'" 0,1; "Tr"->"attamento" 0,0);
/// - parole DISTINTE separate da uno spazio realmente stampato sul PDF: gap
///   1,8-1,9pt ("Retribuzione"->"ordinaria" 1,9; "Edr"->"contrattuale" 1,8;
///   "Somma"->"integrativa" 1,9).
///
/// 1,0pt cade esattamente a metà fra i due gruppi osservati (0,1 e 1,8, i
/// margini più vicini su entrambi i lati), con ampio margine da entrambi i
/// lati per assorbire eventuale ulteriore jitter di rendering mai osservato
/// sul campione disponibile.
const double _sogliaSpazioParoleDescrizione = 1.0;

/// Unisce le parole di una descrizione (già ordinate per bordo sinistro
/// crescente — vedi i due usi in [_classificaRigaVoce]/
/// [_classificaRigaContributo]) in un'unica stringa, inserendo uno spazio fra
/// due parole adiacenti solo quando il gap fra il bordo destro della prima e
/// il bordo sinistro della seconda SUPERA [_sogliaSpazioParoleDescrizione] —
/// vedi la sua doc per la motivazione e i valori misurati. Al gap
/// ESATTAMENTE uguale alla soglia (limite) le parole restano concatenate
/// SENZA spazio: la regola è "supera la soglia", non "raggiunge o supera".
String _unisciParoleDescrizione(List<ParolaVoce> parole) {
  final buffer = StringBuffer();
  ParolaVoce? precedente;
  for (final p in parole) {
    final testo = p.testo.trim();
    if (precedente != null &&
        (p.bordoSinistro - precedente.bordoDestro) >
            _sogliaSpazioParoleDescrizione) {
      buffer.write(' ');
    }
    buffer.write(testo);
    precedente = p;
  }
  return buffer.toString();
}

// Un codice voce così come stampato nella colonna più a sinistra della
// tabella voci ("0", "10", "210", "930"...): sempre cifre pure.
final RegExp _soloCifre = RegExp(r'^\d+$');

// Una quantità così come stampata nella tabella voci (3 decimali, es.
// "21,000", "0,620") — stessa forma della quantità nel percorso testuale
// (`_rigaVoceCompetenza` in `busta_paga_regex_parser.dart`).
final RegExp _quantitaPattern = RegExp(r'^[\d.]+,\d{3}$');

double? _numeroQuantita(String testo) {
  final t = testo.trim();
  if (!_quantitaPattern.hasMatch(t)) return null;
  return double.parse(t.replaceAll('.', '').replaceAll(',', '.'));
}

// Un importo così come stampato in queste tabelle (2 decimali, eventuale
// separatore delle migliaia "."): il segno "-" è stato osservato SIA in
// testa (convenzione già nota dal percorso testuale, es. uno storno) SIA in
// coda (convenzione della riga totali, es. "0,03-" per ARR. ATTUALE) — mai
// entrambi insieme, ma questo pattern riconosce entrambe le posizioni senza
// bisogno di sapere a priori quale colonna le usa.
final RegExp _monetaPattern = RegExp(r'^-?[\d.]+,\d{2}-?$');

double? _numeroMoneta(String testo) {
  final t = testo.trim();
  if (!_monetaPattern.hasMatch(t)) return null;
  final negativo = t.startsWith('-') || t.endsWith('-');
  final pulito = t.replaceAll('-', '').replaceAll('.', '').replaceAll(',', '.');
  final valore = double.parse(pulito);
  return negativo ? -valore.abs() : valore;
}
