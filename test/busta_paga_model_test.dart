import 'package:buts/models/busta_paga.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('layout: default job e copyWith', () {
    final b = BustaPaga(
      id: 'x',
      periodo: DateTime(2026, 7),
      lordo: 0,
      netto: 0,
      trattenute: const {},
      straordinari: 0,
      ferieMaturate: 0,
      ferieGodute: 0,
      ferieResidue: 0,
      rolMaturati: 0,
      rolGoduti: 0,
      rolResidui: 0,
      permessiGoduti: 0,
      oreLavorate: 0,
    );
    expect(b.layout, 'job');
    expect(b.copyWith(layout: 'altro').layout, 'altro');
  });

  group('computeLordo', () {
    test('somma gli importi di tutte le voci', () {
      const competenze = [
        VoceCompetenza(
            descrizione: 'Retribuzione ordinaria',
            quantita: 20.0,
            importo: 1000.0),
        VoceCompetenza(
            descrizione: 'Edr contrattuale', quantita: 20.0, importo: 20.0),
        VoceCompetenza(
            descrizione: 'Straordinario diurno (30%)',
            quantita: 3.0,
            importo: 30.0),
      ];

      expect(computeLordo(competenze), closeTo(1050.0, 0.001));
    });

    test(
        'ignora correttamente le voci con importo 0 (es. righe senza '
        'importo associato)', () {
      const competenze = [
        VoceCompetenza(
            descrizione: 'Permessi riduz. orario goduti',
            quantita: 4.030,
            importo: 0),
        VoceCompetenza(
            descrizione: 'Retribuzione ordinaria',
            quantita: 20.0,
            importo: 1000.0),
      ];

      expect(computeLordo(competenze), closeTo(1000.0, 0.001));
    });

    test('lista vuota produce 0', () {
      expect(computeLordo(const []), 0);
    });
  });

  group('computeStraordinari', () {
    test('somma le quantità delle sole voci "straordinario"', () {
      const competenze = [
        VoceCompetenza(
            descrizione: 'Retribuzione ordinaria',
            quantita: 20.0,
            importo: 1000.0),
        VoceCompetenza(
            descrizione: 'Straordinario diurno (30%)',
            quantita: 3.0,
            importo: 30.0),
        VoceCompetenza(
            descrizione: 'Straordinario notturno (50%)',
            quantita: 2.0,
            importo: 20.0),
      ];

      expect(computeStraordinari(competenze), closeTo(5.0, 0.001));
    });

    test('è case-insensitive sul prefisso "straordinario"', () {
      const competenze = [
        VoceCompetenza(
            descrizione: 'STRAORDINARIO FESTIVO', quantita: 4.0, importo: 40.0),
      ];

      expect(computeStraordinari(competenze), closeTo(4.0, 0.001));
    });

    test('lista vuota produce 0', () {
      expect(computeStraordinari(const []), 0);
    });

    // Regressione bug "quantità 0 su voci che non hanno quantità":
    // `VoceCompetenza.quantita` è nullable (righe senza tag GIORNI/ORE/RATEI
    // sul PDF, es. "930 Trattamento integrativo", non hanno alcuna
    // quantità) — mai osservato per una voce di straordinario reale (sempre
    // tag "ORE"), ma `computeStraordinari` deve comunque gestire il caso
    // senza eccezioni, trattando l'assenza come 0 nella somma.
    test(
        'una quantità ASSENTE (null) in una voce di straordinario conta '
        'come 0 nella somma, nessuna eccezione', () {
      const competenze = [
        VoceCompetenza(
            descrizione: 'Straordinario diurno (30%)',
            quantita: 3.0,
            importo: 30.0),
        VoceCompetenza(
            descrizione: 'Straordinario festivo', quantita: null, importo: 0),
      ];

      expect(computeStraordinari(competenze), closeTo(3.0, 0.001));
    });
  });

  group('computeNetto', () {
    test('sottrae la somma delle trattenute dal lordo', () {
      const trattenute = {'INPS': 61.32, 'IRPEF': 150.0};

      expect(computeNetto(1050.0, trattenute), closeTo(838.68, 0.001));
    });

    test('mappa trattenute vuota produce netto = lordo', () {
      expect(computeNetto(1050.0, const {}), closeTo(1050.0, 0.001));
    });

    test(
        'trattenute che superano il lordo producono un netto negativo, '
        'senza clamp', () {
      const trattenute = {'INPS': 600.0, 'IRPEF': 600.0};

      expect(computeNetto(1000.0, trattenute), closeTo(-200.0, 0.001));
    });
  });
}
