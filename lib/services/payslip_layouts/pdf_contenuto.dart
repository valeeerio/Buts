/// Una singola parola della pagina PDF ridotta ai soli dati che servono a
/// `classificaVociDaCoordinate`: il testo grezzo e le coordinate usate come
/// ancora per riga/colonna (bordo superiore Y, bordo sinistro X, bordo
/// destro X) — a differenza di `ParolaRateo` serve anche il bordo sinistro,
/// necessario per ricostruire testo libero allineato a sinistra (descrizioni
/// di voci/contributi), non solo colonne numeriche allineate a destra.
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
