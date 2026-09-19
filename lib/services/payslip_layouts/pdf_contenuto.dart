/// Parola di una pagina con le sue coordinate (origine in alto a sinistra).
typedef ParolaVoce = ({
  String testo,
  double bordoSuperiore,
  double bordoSinistro,
  double bordoDestro,
});

/// Tutto ciò che un layout vede di un PDF: testo linearizzato e parole con
/// coordinate per ogni pagina. Una pagina illeggibile è `null` (mai
/// un'eccezione): l'estrazione per coordinate è best-effort.
class PdfContenuto {
  final String? testo;
  final List<List<ParolaVoce>?> paroleAPagina;

  const PdfContenuto({this.testo, this.paroleAPagina = const []});

  List<ParolaVoce>? get primaPagina =>
      paroleAPagina.isEmpty ? null : paroleAPagina.first;
}
