import 'package:buts/models/busta_paga.dart';
import 'package:buts/services/busta_paga_regex_parser.dart';
import 'package:buts/services/payslip_layouts/payslip_layout.dart';
import 'package:buts/services/payslip_layouts/payslip_layout_registry.dart';
import 'package:buts/services/payslip_layouts/pdf_contenuto.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLayout implements PayslipLayout {
  _FakeLayout(this.id, this.firma);

  @override
  final String id;
  final String firma;

  @override
  bool riconosce(PdfContenuto contenuto) =>
      (contenuto.testo ?? '').contains(firma);

  // Volutamente NON imposta `layoutId`: deve pensarci il registro.

  @override
  BustaPagaEstratti estrai(PdfContenuto contenuto) => const BustaPagaEstratti(
        trattenute: {},
        straordinari: 0,
        ferieMaturate: 0,
        ferieGodute: 0,
        ferieResidue: 0,
        rolMaturati: 0,
        rolGoduti: 0,
        rolResidui: 0,
        permessiGoduti: 0,
        warnings: [],
      );
}

void main() {
  group('PayslipLayoutRegistry.rileva', () {
    test('restituisce il layout che riconosce il PDF', () {
      final registro = PayslipLayoutRegistry([
        _FakeLayout('a', 'FIRMA-A'),
        _FakeLayout('b', 'FIRMA-B'),
      ]);
      final trovato = registro.rileva(const PdfContenuto(testo: 'x FIRMA-B y'));
      expect(trovato?.id, 'b');
    });

    test('con più layout compatibili vince il primo in ordine', () {
      final registro = PayslipLayoutRegistry([
        _FakeLayout('a', 'COMUNE'),
        _FakeLayout('b', 'COMUNE'),
      ]);
      expect(registro.rileva(const PdfContenuto(testo: 'COMUNE'))?.id, 'a');
    });

    test('nessun layout compatibile -> null', () {
      final registro = PayslipLayoutRegistry([_FakeLayout('a', 'FIRMA-A')]);
      expect(registro.rileva(const PdfContenuto(testo: 'altro')), isNull);
    });

    test('testo assente -> null', () {
      final registro = PayslipLayoutRegistry([_FakeLayout('a', 'FIRMA-A')]);
      expect(registro.rileva(const PdfContenuto()), isNull);
    });
  });

  group('PayslipLayoutRegistry.estrai', () {
    test('stampa layout.id sul risultato anche se il layout lo dimentica', () {
      final registro = PayslipLayoutRegistry([_FakeLayout('x', 'FIRMA-X')]);
      final risultato = registro.estrai(const PdfContenuto(testo: 'FIRMA-X'));
      expect(risultato, isNotNull);
      expect(risultato!.layoutId, 'x');
      expect(risultato.layoutId, isNot(kLayoutPredefinito));
    });

    test('nessun layout riconosce -> null', () {
      final registro = PayslipLayoutRegistry([_FakeLayout('x', 'FIRMA-X')]);
      expect(registro.estrai(const PdfContenuto(testo: 'altro')), isNull);
    });
  });
}
