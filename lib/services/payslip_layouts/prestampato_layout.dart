import '../busta_paga_regex_parser.dart';
import 'payslip_layout.dart';
import 'pdf_contenuto.dart';
import 'prestampato_classifier.dart';

/// Secondo layout di cedolino PDF: modulo prestampato con etichette e valori in
/// colonne separate (l'estrazione testuale non le associa: si legge per
/// COORDINATE). Il nome del software paghe non è deducibile dal PDF; `id` è
/// provvisorio ma persistito in `BustaPaga.layout`.
class PrestampatoLayout implements PayslipLayout {
  const PrestampatoLayout();

  static final _elementi = RegExp(r'ELEMENTI\s+DELLA\s+RETRIBUZIONE');
  static final _periodo = RegExp(r'Periodo\s+di\s+retribuzione');

  @override
  String get id => 'prestampato';

  @override
  bool riconosce(PdfContenuto contenuto) {
    final testo = contenuto.testo ?? '';
    return _elementi.hasMatch(testo) && _periodo.hasMatch(testo);
  }

  @override
  BustaPagaEstratti estrai(PdfContenuto contenuto) =>
      classificaPrestampato(contenuto.paroleAPagina);
}
