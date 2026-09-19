import '../../models/busta_paga.dart';
import '../busta_paga_regex_parser.dart';
import '../pdf_import_service.dart';
import 'payslip_layout.dart';
import 'pdf_contenuto.dart';

/// Layout del software paghe "JOB". Adattatore sottile: la logica vive ancora
/// in [BustaPagaRegexParser] e nelle funzioni `classifica*DaCoordinate`.
class JobLayout implements PayslipLayout {
  const JobLayout();

  static final _firma = RegExp(r'JOB\s*-\s*Copyright', caseSensitive: false);

  @override
  String get id => kLayoutPredefinito;

  @override
  bool riconosce(PdfContenuto contenuto) =>
      _firma.hasMatch(contenuto.testo ?? '');

  @override
  BustaPagaEstratti estrai(PdfContenuto contenuto) {
    final parole = contenuto.primaPagina;
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
    return const BustaPagaRegexParser().parse(contenuto.testo ?? '', ratei, voci);
  }
}
