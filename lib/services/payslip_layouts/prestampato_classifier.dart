import '../../models/busta_paga.dart';
import '../busta_paga_regex_parser.dart';
import 'pdf_contenuto.dart';

// Ancore X (bordo destro) delle colonne, da
// docs/superpowers/specs/2026-09-19-payslip-layout-nuovo-coordinate.md.
const _xCompetenzeDestro = 561.4;
const _tolleranzaX = 4.0;

// Bordi destri delle 4 colonne dei ratei (a.p., spett., godute, residue), da
// findings sez. 3. Ferie godute (~189) NON osservato: dedotto dall'etichetta.
// Le colonne Ex festività sono IPOTIZZATE uguali a quelle Ferie (celle vuote
// nell'unico PDF di esempio).
const _colonneFerie = [109.8, 150.3, 189.0, 231.4];
const _colonneRol = [271.9, 312.6, 353.0, 393.8];

const _mesiAbbreviati = {
  'GEN': 1, 'FEB': 2, 'MAR': 3, 'APR': 4, 'MAG': 5, 'GIU': 6,
  'LUG': 7, 'AGO': 8, 'SET': 9, 'OTT': 10, 'NOV': 11, 'DIC': 12,
};

final _numero = RegExp(r'^-?(?:\d{1,3}(?:\.\d{3})+|\d+),\d+$');
final _periodo = RegExp(r'^([A-Z]{3})\.(\d{4})$');

double? _num(String testo) {
  final t = testo.trim();
  if (!_numero.hasMatch(t)) return null;
  return double.parse(t.replaceAll('.', '').replaceAll(',', '.'));
}

List<ParolaVoce> _pulite(List<ParolaVoce> parole) =>
    [for (final p in parole) if (p.testo.trim().isNotEmpty) p];

/// Prima occorrenza della sequenza di [token] sulla stessa riga (Y ±1,0), ogni
/// token a destra del precedente a meno di 6 pt. Restituisce Y e gli estremi X.
({double top, double sinistra, double destra})? _etichetta(
  List<ParolaVoce> parole,
  List<String> token,
) {
  for (final prima in parole) {
    if (prima.testo != token.first) continue;
    var ultima = prima;
    var trovata = true;
    for (final t in token.skip(1)) {
      final candidate = [
        for (final p in parole)
          if (p.testo == t &&
              (p.bordoSuperiore - prima.bordoSuperiore).abs() <= 1.0 &&
              p.bordoSinistro >= ultima.bordoDestro - 0.5 &&
              p.bordoSinistro - ultima.bordoDestro <= 6.0)
            p,
      ]..sort((a, b) => a.bordoSinistro.compareTo(b.bordoSinistro));
      if (candidate.isEmpty) {
        trovata = false;
        break;
      }
      ultima = candidate.first;
    }
    if (trovata) {
      return (
        top: prima.bordoSuperiore,
        sinistra: prima.bordoSinistro,
        destra: ultima.bordoDestro,
      );
    }
  }
  return null;
}

/// Primo valore numerico con Y in [dalTop, alTop] e bordo destro entro
/// [tolleranza] da [bordoDestro].
double? _valore(
  List<ParolaVoce> parole, {
  required double dalTop,
  required double alTop,
  required double bordoDestro,
  double tolleranza = _tolleranzaX,
}) {
  for (final p in parole) {
    if (p.bordoSuperiore < dalTop || p.bordoSuperiore > alTop) continue;
    if ((p.bordoDestro - bordoDestro).abs() > tolleranza) continue;
    final v = _num(p.testo);
    if (v != null) return v;
  }
  return null;
}

/// Legge una riga di ratei ancorata alla sua etichetta "a.p." ([etichettaAp]).
/// I valori stanno a +12,8 pt (finestra +10..+16) e si assegnano per bordo
/// destro di colonna. Cella assente = 0 (una cella vuota non produce parole).
/// `null` se l'etichetta della riga non esiste sulla pagina.
RateoCategoria? _rateo(
  List<ParolaVoce> parole,
  List<String> etichettaAp,
  List<double> colonne,
) {
  final et = _etichetta(parole, etichettaAp);
  if (et == null) return null;
  double cella(double destro) =>
      _valore(
        parole,
        dalTop: et.top + 10,
        alTop: et.top + 16,
        bordoDestro: destro,
      ) ??
      0.0;
  return RateoCategoria(
    residuoAnnoPrecedente: cella(colonne[0]),
    maturato: cella(colonne[1]),
    goduto: cella(colonne[2]),
    residuo: cella(colonne[3]),
  );
}

/// Indice dell'ULTIMA pagina che ha un valore sotto "Totale Competenze": le
/// pagine intermedie ("SEGUE ..") hanno le etichette ma nessun valore.
int? _indicePaginaTotali(List<List<ParolaVoce>?> pagine) {
  int? scelto;
  for (var i = 0; i < pagine.length; i++) {
    final grezza = pagine[i];
    if (grezza == null) continue;
    final parole = _pulite(grezza);
    final et = _etichetta(parole, ['Totale', 'Competenze']);
    if (et == null) continue;
    final v = _valore(
      parole,
      dalTop: et.top + 5,
      alTop: et.top + 14,
      bordoDestro: _xCompetenzeDestro,
    );
    if (v != null) scelto = i;
  }
  return scelto;
}

String? _periodoDa(List<List<ParolaVoce>?> pagine) {
  for (final grezza in pagine) {
    if (grezza == null) continue;
    final parole = _pulite(grezza);
    final et = _etichetta(parole, ['Periodo', 'di', 'retribuzione']);
    if (et == null) continue;
    for (final p in parole) {
      if (p.bordoSinistro < 450) continue;
      if (p.bordoSuperiore < et.top + 2 || p.bordoSuperiore > et.top + 16) {
        continue;
      }
      final m = _periodo.firstMatch(p.testo);
      final mese = m == null ? null : _mesiAbbreviati[m.group(1)!];
      if (m != null && mese != null) {
        return '${m.group(2)}-${mese.toString().padLeft(2, '0')}';
      }
    }
  }
  return null;
}

/// Converte le parole con coordinate di un cedolino del layout "prestampato"
/// in [BustaPagaEstratti]. Puro: nessuna dipendenza da Syncfusion. Tutte le
/// ancore sono relative all'etichetta della stessa pagina.
BustaPagaEstratti classificaPrestampato(List<List<ParolaVoce>?> pagine) {
  final warnings = <String>[];

  final periodo = _periodoDa(pagine);
  if (periodo == null) warnings.add('periodo non trovato');

  final indice = _indicePaginaTotali(pagine);
  List<ParolaVoce> parole = const [];
  if (indice == null) {
    warnings.add('pagina dei totali non trovata');
  } else {
    parole = _pulite(pagine[indice]!);
  }

  double? oreLavorate;
  if (parole.isNotEmpty) {
    final et = _etichetta(parole, ['Ore', 'lavorate']);
    if (et != null) {
      final candidati = [
        for (final p in parole)
          if (p.bordoSuperiore >= et.top + 5 &&
              p.bordoSuperiore <= et.top + 14 &&
              p.bordoSinistro < 150 &&
              _num(p.testo) != null)
            p,
      ]..sort((a, b) => a.bordoSinistro.compareTo(b.bordoSinistro));
      if (candidati.isNotEmpty) oreLavorate = _num(candidati.first.testo);
    }
    if (oreLavorate == null) warnings.add('ore lavorate non determinabili');
  }

  double? nettoStampato;
  if (parole.isNotEmpty) {
    final basso = _etichetta(parole, ['NETTO', 'DA', 'PAGARE']);
    if (basso != null) {
      nettoStampato = _valore(
        parole,
        dalTop: basso.top + 14,
        alTop: basso.top + 25,
        bordoDestro: _xCompetenzeDestro,
      );
    }
    if (nettoStampato == null) {
      final alto = _etichetta(parole, ['Netto', 'da', 'pagare']);
      if (alto != null) {
        nettoStampato = _valore(
          parole,
          dalTop: alto.top + 5,
          alTop: alto.top + 14,
          bordoDestro: _xCompetenzeDestro,
        );
      }
    }
    if (nettoStampato == null) warnings.add('netto non trovato');
  }

  final ferie = parole.isEmpty
      ? null
      : _rateo(parole, ['Ferie', 'a.p.'], _colonneFerie);
  final rol =
      parole.isEmpty ? null : _rateo(parole, ['ROL', 'a.p.'], _colonneRol);
  final ex = parole.isEmpty
      ? null
      : _rateo(parole, ['Ex', 'fes.', 'a.p.'], _colonneFerie);
  if (parole.isNotEmpty) {
    if (ferie == null) warnings.add('dati ferie non trovati');
    if (rol == null) warnings.add('dati ROL non trovati');
    if (ex == null) warnings.add('dati ex festività non trovati');
  }

  return BustaPagaEstratti(
    periodo: periodo,
    netto: nettoStampato,
    trattenute: const {},
    straordinari: 0,
    ferieMaturate: ferie?.maturato ?? 0,
    ferieGodute: ferie?.goduto ?? 0,
    ferieResidue: ferie?.residuo ?? 0,
    rolMaturati: rol?.maturato ?? 0,
    rolGoduti: rol?.goduto ?? 0,
    rolResidui: rol?.residuo ?? 0,
    permessiGoduti: rol?.goduto ?? 0,
    exFestivitaMaturate: ex?.maturato ?? 0,
    exFestivitaGodute: ex?.goduto ?? 0,
    exFestivitaResidue: ex?.residuo ?? 0,
    oreLavorate: oreLavorate,
    tipo: TipoBustaPaga.mensile,
    warnings: warnings,
  );
}
