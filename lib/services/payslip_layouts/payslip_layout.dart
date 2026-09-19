import '../busta_paga_regex_parser.dart';
import 'pdf_contenuto.dart';

/// Un layout di cedolino PDF (software paghe): sa riconoscere il proprio PDF
/// e trasformarlo in [BustaPagaEstratti]. Aggiungere un layout = nuova classe
/// + una riga in `PayslipLayoutRegistry.standard`.
abstract interface class PayslipLayout {
  /// Identificatore stabile, persistito in `BustaPaga.layout`.
  String get id;

  bool riconosce(PdfContenuto contenuto);

  BustaPagaEstratti estrai(PdfContenuto contenuto);
}
