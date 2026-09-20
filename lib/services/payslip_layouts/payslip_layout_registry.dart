import '../busta_paga_regex_parser.dart';
import 'job_layout.dart';
import 'payslip_layout.dart';
import 'pdf_contenuto.dart';
import 'prestampato_layout.dart';

class PayslipLayoutRegistry {
  final List<PayslipLayout> layouts;

  const PayslipLayoutRegistry(this.layouts);

  /// Layout supportati, in ordine di prova. I nuovi layout si aggiungono qui.
  static const standard =
      PayslipLayoutRegistry([JobLayout(), PrestampatoLayout()]);

  /// Primo layout che riconosce il PDF, o `null` se nessuno lo riconosce.
  PayslipLayout? rileva(PdfContenuto contenuto) {
    for (final layout in layouts) {
      if (layout.riconosce(contenuto)) return layout;
    }
    return null;
  }

  /// Rileva il layout e ne estrae i dati, stampando `layout.id` su
  /// `layoutId`: così nessun layout può dimenticare di dichiararsi.
  /// `null` se nessun layout riconosce il PDF.
  BustaPagaEstratti? estrai(PdfContenuto contenuto) {
    final layout = rileva(contenuto);
    return layout?.estrai(contenuto).conLayoutId(layout.id);
  }
}
