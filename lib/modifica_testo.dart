// Modifica del testo di una pagina: si tocca una riga, si cambia e viene riscritta al suo posto.
// La riga vecchia viene coperta con il colore dello sfondo e riscritta in Helvetica.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Offset, Rect;

import 'package:pdfrx/pdfrx.dart' as rx;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'documenti.dart';

/// Riga di testo trovata nella pagina, con il suo riquadro in punti PDF.
class RigaPagina {
  RigaPagina(this.testo, this.riquadro, this.corpo);
  final String testo;
  final Rect riquadro;
  final double corpo;
}

/// Righe di testo di una pagina (pagina da 1). Vuoto se la pagina è una scansione senza testo.
Future<List<RigaPagina>> righeDellaPagina(String percorso, int pagina) async {
  final doc = PdfDocument(inputBytes: await File(percorso).readAsBytes());
  try {
    final righe = PdfTextExtractor(doc).extractTextLines(startPageIndex: pagina - 1, endPageIndex: pagina - 1);
    return righe
        .where((r) => r.text.trim().isNotEmpty && r.bounds.width > 1 && r.bounds.height > 1)
        .map((r) => RigaPagina(r.text, r.bounds, r.fontSize))
        .toList();
  } finally {
    doc.dispose();
  }
}

/// Sostituisce il testo di una riga.
///
/// La libreria PDF per Flutter non sa cancellare il testo esistente: coprirlo basterebbe a vederlo
/// sparire, ma resterebbe cercabile e copiabile. Allora la pagina viene ridisegnata come immagine
/// (con la riga vecchia cancellata col colore dello sfondo), sopra si scrive il testo nuovo e le
/// altre righe si riscrivono invisibili, così la pagina resta cercabile.
/// `disegnaPagina` serve ai test: di norma la pagina la disegna pdfium.
/// Restituisce `true` se la pagina è stata rifatta davvero; `false` se è stato usato il ripiego
/// (riga coperta e riscritta: si vede giusto, ma il testo vecchio resta cercabile sotto).
Future<bool> cambiaRiga(String percorso, int pagina, RigaPagina riga, String nuovoTesto,
    {Future<(Uint8List, int, int)?> Function(String percorso, int pagina)? disegnaPagina}) async {
  final altre = (await righeDellaPagina(percorso, pagina))
      .where((r) => r.riquadro != riga.riquadro || r.testo != riga.testo)
      .toList();
  final preparata = await _paginaSenzaRiga(percorso, pagina, riga, disegnaPagina);
  final sorgente = PdfDocument(inputBytes: await File(percorso).readAsBytes());
  final uscita = PdfDocument();
  uscita.pageSettings.margins.all = 0;
  var rifatta = false;
  try {
    for (var i = 0; i < sorgente.pages.count; i++) {
      final origine = sorgente.pages[i];
      uscita.pageSettings.size = origine.size;
      final p = uscita.pages.add();
      if (i != pagina - 1) {
        // pagina invariata: si ricopia com'è
        p.graphics.drawPdfTemplate(origine.createTemplate(), Offset.zero, origine.size);
        continue;
      }
      if (preparata == null) {
        // ripiego: non siamo riusciti a rifare la pagina, allora la copiamo, copriamo la riga
        // vecchia e scriviamo sopra quella nuova. Si vede giusto, ma sotto resta cercabile.
        p.graphics.drawPdfTemplate(origine.createTemplate(), Offset.zero, origine.size);
        final r = riga.riquadro;
        final margine = math.max(1.0, r.height * 0.15);
        p.graphics.drawRectangle(
          brush: PdfSolidBrush(PdfColor(255, 255, 255)),
          bounds: Rect.fromLTWH(r.left - margine, r.top - margine, r.width + margine * 3, r.height + margine * 2),
        );
        if (nuovoTesto.trim().isNotEmpty) {
          _scrivi(p, nuovoTesto, r, riga.corpo, PdfColor(0, 0, 0));
        }
        continue;
      }
      // pagina modificata: si ricostruisce da zero, così il testo vecchio sparisce davvero
      rifatta = true;
      final (png, sfondo, inchiostro) = preparata;
      final area = p.getClientSize();
      p.graphics.drawRectangle(
          brush: PdfSolidBrush(sfondo), bounds: Rect.fromLTWH(0, 0, area.width, area.height));
      p.graphics.drawImage(PdfBitmap(png), Rect.fromLTWH(0, 0, area.width, area.height));
      for (final a in altre) {
        _scrivi(p, a.testo, a.riquadro, a.corpo, PdfColor(0, 0, 0), invisibile: true);
      }
      if (nuovoTesto.trim().isNotEmpty) {
        _scrivi(p, nuovoTesto, riga.riquadro, riga.corpo, inchiostro);
      }
    }
    await scriviSopra(percorso, await uscita.save());
    return rifatta;
  } finally {
    uscita.dispose();
    sorgente.dispose();
  }
}

/// Scrive il testo dentro il riquadro, rimpicciolendolo se non ci sta.
void _scrivi(PdfPage p, String testo, Rect r, double corpoRiga, PdfColor colore, {bool invisibile = false}) {
  var corpo = corpoRiga > 0 ? corpoRiga : r.height * 0.8;
  final misura = PdfStandardFont(PdfFontFamily.helvetica, corpo).measureString(testo).width;
  if (misura > r.width && misura > 0) corpo = math.max(4, corpo * r.width / misura);
  if (invisibile) {
    p.graphics.save();
    p.graphics.setTransparency(0);
  }
  p.graphics.drawString(
    testo,
    PdfStandardFont(PdfFontFamily.helvetica, corpo),
    brush: PdfSolidBrush(colore),
    bounds: Rect.fromLTWH(r.left, r.top, r.width + 6, r.height + 4),
  );
  if (invisibile) p.graphics.restore();
}

/// Immagine della pagina con la riga cancellata, più i colori usati.
Future<(Uint8List, PdfColor, PdfColor)?> _paginaSenzaRiga(String percorso, int pagina, RigaPagina riga,
    Future<(Uint8List, int, int)?> Function(String, int)? disegnaPagina) async {
  try {
    final disegnata = await (disegnaPagina ?? _disegnaConPdfium)(percorso, pagina);
    if (disegnata == null) return null;
    final (rgba, larghezza, altezza) = disegnata;
    final doc = PdfDocument(inputBytes: await File(percorso).readAsBytes());
    final misura = doc.pages[pagina - 1].size;
    doc.dispose();
    final scala = larghezza / misura.width;
    final r = riga.riquadro;
    final box = Rect.fromLTWH(r.left * scala, r.top * scala, r.width * scala, r.height * scala);
    final (sfondo, inchiostro) = _colori(rgba, larghezza, altezza, box);
    // cancella la riga vecchia dall'immagine
    final margine = math.max(2, (box.height * 0.18).round());
    for (var y = (box.top - margine).round(); y <= box.bottom + margine; y++) {
      if (y < 0 || y >= altezza) continue;
      for (var x = (box.left - margine).round(); x <= box.right + margine; x++) {
        if (x < 0 || x >= larghezza) continue;
        final i = (y * larghezza + x) * 4;
        rgba[i] = sfondo.r;
        rgba[i + 1] = sfondo.g;
        rgba[i + 2] = sfondo.b;
        rgba[i + 3] = 255;
      }
    }
    final pulita = await _pngDaRgba(rgba, larghezza, altezza);
    return (pulita, sfondo, inchiostro);
  } catch (_) {
    return null;
  }
}

/// Disegno della pagina con pdfium (quello usato dall'app).
Future<(Uint8List, int, int)?> _disegnaConPdfium(String percorso, int pagina) async {
  final documento = await rx.PdfDocument.openFile(percorso);
  try {
    final p = documento.pages[pagina - 1];
    final scala = math.min(2000 / p.width, 2.8);
    final resa = await p.render(width: (p.width * scala).round(), height: (p.height * scala).round());
    if (resa == null) return null;
    final immagine = await resa.createImage();
    final dati = await immagine.toByteData(format: ui.ImageByteFormat.rawRgba);
    final larghezza = immagine.width, altezza = immagine.height;
    immagine.dispose();
    if (dati == null) return null;
    return (dati.buffer.asUint8List(), larghezza, altezza);
  } finally {
    await documento.dispose();
  }
}

Future<Uint8List> _pngDaRgba(Uint8List rgba, int larghezza, int altezza) async {
  final completatore = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, larghezza, altezza, ui.PixelFormat.rgba8888, completatore.complete);
  final immagine = await completatore.future;
  final dati = await immagine.toByteData(format: ui.ImageByteFormat.png);
  immagine.dispose();
  return dati!.buffer.asUint8List();
}

(PdfColor, PdfColor) _colori(Uint8List rgba, int larghezza, int altezza, Rect riquadro) {
  int indice(int x, int y) => (y.clamp(0, altezza - 1) * larghezza + x.clamp(0, larghezza - 1)) * 4;

  final bordo = <List<int>>[];
  final margine = math.max(2, (riquadro.height * 0.25).round());
  for (var x = riquadro.left.round(); x < riquadro.right; x += math.max(1, (riquadro.width / 24).round())) {
    for (final y in [riquadro.top.round() - margine, riquadro.bottom.round() + margine]) {
      final i = indice(x, y);
      bordo.add([rgba[i], rgba[i + 1], rgba[i + 2]]);
    }
  }
  if (bordo.isEmpty) return (PdfColor(255, 255, 255), PdfColor(0, 0, 0));
  int mediana(int canale) {
    final valori = bordo.map((c) => c[canale]).toList()..sort();
    return valori[valori.length ~/ 2];
  }

  final sfondo = [mediana(0), mediana(1), mediana(2)];
  var sommaR = 0, sommaG = 0, sommaB = 0, quanti = 0, massimo = 0;
  final campioni = <List<int>>[];
  for (var y = riquadro.top.round(); y < riquadro.bottom; y += math.max(1, (riquadro.height / 10).round())) {
    for (var x = riquadro.left.round(); x < riquadro.right; x += math.max(1, (riquadro.width / 50).round())) {
      final i = indice(x, y);
      final c = [rgba[i], rgba[i + 1], rgba[i + 2]];
      final d = (c[0] - sfondo[0]) * (c[0] - sfondo[0]) +
          (c[1] - sfondo[1]) * (c[1] - sfondo[1]) +
          (c[2] - sfondo[2]) * (c[2] - sfondo[2]);
      campioni.add([d, c[0], c[1], c[2]]);
      massimo = math.max(massimo, d);
    }
  }
  for (final c in campioni) {
    if (c[0] > massimo * 0.5) {
      sommaR += c[1];
      sommaG += c[2];
      sommaB += c[3];
      quanti++;
    }
  }
  final inchiostro =
      quanti > 0 ? PdfColor(sommaR ~/ quanti, sommaG ~/ quanti, sommaB ~/ quanti) : PdfColor(0, 0, 0);
  return (PdfColor(sfondo[0], sfondo[1], sfondo[2]), inchiostro);
}
