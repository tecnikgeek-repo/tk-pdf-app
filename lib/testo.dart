// Riconoscimento del testo (OCR) sulle pagine scansionate: le scritte diventano testo PDF vero.
// Le pagine che hanno già testo vengono lasciate come sono.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Offset, Rect;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart' as rx;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'documenti.dart' as doc;

/// Una riga riconosciuta, con il riquadro in frazione di pagina (0..1).
class RigaTesto {
  RigaTesto(this.testo, this.riquadro, this.sfondo, this.inchiostro);
  final String testo;
  final Rect riquadro;
  final PdfColor sfondo;
  final PdfColor inchiostro;
}

/// Trasforma le scritte delle pagine scansionate in testo modificabile.
/// Ritorna il percorso del nuovo file, oppure null se non c'era niente da riconoscere.
Future<String?> rendiTestoModificabile(
  String percorso, {
  void Function(int pagina, int totale)? avanzamento,
}) async {
  final originale = PdfDocument(inputBytes: await File(percorso).readAsBytes());
  final estrattore = PdfTextExtractor(originale);
  final documento = await rx.PdfDocument.openFile(percorso);
  final riconoscitore = TextRecognizer(script: TextRecognitionScript.latin);
  final uscita = PdfDocument();
  uscita.pageSettings.margins.all = 0;
  var riconosciute = 0;
  try {
    for (var i = 0; i < documento.pages.length; i++) {
      avanzamento?.call(i + 1, documento.pages.length);
      final paginaOrigine = originale.pages[i];
      final haTesto = estrattore.extractText(startPageIndex: i, endPageIndex: i).trim().length > 20;
      if (haTesto) {
        // pagina già testuale: si copia com'è
        uscita.pageSettings.size = paginaOrigine.size;
        final nuova = uscita.pages.add();
        nuova.graphics.drawPdfTemplate(paginaOrigine.createTemplate(), Offset.zero, paginaOrigine.size);
        continue;
      }
      final risultato = await _leggiPagina(documento.pages[i], riconoscitore);
      if (risultato == null) {
        uscita.pageSettings.size = paginaOrigine.size;
        final nuova = uscita.pages.add();
        nuova.graphics.drawPdfTemplate(paginaOrigine.createTemplate(), Offset.zero, paginaOrigine.size);
        continue;
      }
      final (png, righe) = risultato;
      riconosciute += righe.length;
      uscita.pageSettings.size = paginaOrigine.size;
      final nuova = uscita.pages.add();
      final area = nuova.getClientSize();
      nuova.graphics.drawImage(PdfBitmap(png), Rect.fromLTWH(0, 0, area.width, area.height));
      for (final riga in righe) {
        final x = riga.riquadro.left * area.width;
        final y = riga.riquadro.top * area.height;
        final larghezza = riga.riquadro.width * area.width;
        final altezza = riga.riquadro.height * area.height;
        // si cancella la scritta dalla foto e si riscrive come testo vero
        nuova.graphics.drawRectangle(
          brush: PdfSolidBrush(riga.sfondo),
          bounds: Rect.fromLTWH(x - 1, y - 1, larghezza + 2, altezza + 2),
        );
        final corpo = _corpoCheEntra(riga.testo, larghezza, altezza);
        nuova.graphics.drawString(
          riga.testo,
          PdfStandardFont(PdfFontFamily.helvetica, corpo),
          brush: PdfSolidBrush(riga.inchiostro),
          bounds: Rect.fromLTWH(x, y + (altezza - corpo * 1.18) / 2, larghezza + 4, altezza + 4),
        );
      }
    }
    if (riconosciute == 0) return null;
    final nome = doc.nomeSenzaEstensione(percorso);
    final destinazione = await doc.percorsoLibero('$nome testo');
    await File(destinazione).writeAsBytes(await uscita.save(), flush: true);
    return destinazione;
  } finally {
    uscita.dispose();
    originale.dispose();
    await riconoscitore.close();
    await documento.dispose();
  }
}

/// Corpo del carattere che fa stare la riga nel suo riquadro.
double _corpoCheEntra(String testo, double larghezza, double altezza) {
  var corpo = altezza * 0.78;
  final font = PdfStandardFont(PdfFontFamily.helvetica, corpo);
  final misura = font.measureString(testo).width;
  if (misura > larghezza && misura > 0) corpo = corpo * larghezza / misura;
  return math.max(4, math.min(corpo, altezza * 1.1));
}

/// Rende la pagina in immagine, la passa al riconoscitore e ne ricava righe e colori.
Future<(Uint8List, List<RigaTesto>)?> _leggiPagina(rx.PdfPage pagina, TextRecognizer riconoscitore) async {
  final scala = 1700 / pagina.width;
  final resa = await pagina.render(
    width: (pagina.width * scala).round(),
    height: (pagina.height * scala).round(),
  );
  if (resa == null) return null;
  final immagine = await resa.createImage();
  final pngDati = await immagine.toByteData(format: ui.ImageByteFormat.png);
  final rgbaDati = await immagine.toByteData(format: ui.ImageByteFormat.rawRgba);
  final larghezza = immagine.width;
  final altezza = immagine.height;
  immagine.dispose();
  if (pngDati == null || rgbaDati == null) return null;
  final png = pngDati.buffer.asUint8List();

  final temporanea = File('${(await getTemporaryDirectory()).path}/tkpdf-ocr.png');
  await temporanea.writeAsBytes(png, flush: true);
  final lettura = await riconoscitore.processImage(InputImage.fromFilePath(temporanea.path));

  final rgba = rgbaDati.buffer.asUint8List();
  final righe = <RigaTesto>[];
  for (final blocco in lettura.blocks) {
    for (final riga in blocco.lines) {
      final r = riga.boundingBox;
      if (riga.text.trim().isEmpty || r.width <= 2 || r.height <= 2) continue;
      final (sfondo, inchiostro) = _colori(rgba, larghezza, altezza, r);
      righe.add(RigaTesto(
        riga.text,
        Rect.fromLTWH(r.left / larghezza, r.top / altezza, r.width / larghezza, r.height / altezza),
        sfondo,
        inchiostro,
      ));
    }
  }
  try {
    await temporanea.delete();
  } catch (_) {}
  return (png, righe);
}

/// Colore dello sfondo attorno alla riga e colore medio delle lettere.
(PdfColor, PdfColor) _colori(Uint8List rgba, int larghezza, int altezza, Rect riquadro) {
  int pixel(int x, int y) {
    x = x.clamp(0, larghezza - 1);
    y = y.clamp(0, altezza - 1);
    return (y * larghezza + x) * 4;
  }

  final bordo = <List<int>>[];
  final margine = math.max(2, (riquadro.height * 0.2).round());
  for (var x = riquadro.left.round(); x < riquadro.right; x += math.max(1, (riquadro.width / 24).round())) {
    for (final y in [riquadro.top.round() - margine, riquadro.bottom.round() + margine]) {
      final i = pixel(x, y);
      bordo.add([rgba[i], rgba[i + 1], rgba[i + 2]]);
    }
  }
  if (bordo.isEmpty) return (PdfColor(255, 255, 255), PdfColor(0, 0, 0));
  int mediana(int canale) {
    final valori = bordo.map((c) => c[canale]).toList()..sort();
    return valori[valori.length ~/ 2];
  }

  final sfondo = [mediana(0), mediana(1), mediana(2)];
  // inchiostro = i pixel interni più lontani dallo sfondo
  var sommaR = 0, sommaG = 0, sommaB = 0, quanti = 0, distanzaMax = 0;
  final campioni = <List<int>>[];
  for (var y = riquadro.top.round(); y < riquadro.bottom; y += math.max(1, (riquadro.height / 12).round())) {
    for (var x = riquadro.left.round(); x < riquadro.right; x += math.max(1, (riquadro.width / 60).round())) {
      final i = pixel(x, y);
      final c = [rgba[i], rgba[i + 1], rgba[i + 2]];
      final d = (c[0] - sfondo[0]) * (c[0] - sfondo[0]) +
          (c[1] - sfondo[1]) * (c[1] - sfondo[1]) +
          (c[2] - sfondo[2]) * (c[2] - sfondo[2]);
      campioni.add([d, c[0], c[1], c[2]]);
      distanzaMax = math.max(distanzaMax, d);
    }
  }
  for (final c in campioni) {
    if (c[0] > distanzaMax * 0.5) {
      sommaR += c[1];
      sommaG += c[2];
      sommaB += c[3];
      quanti++;
    }
  }
  final inchiostro = quanti > 0
      ? PdfColor(sommaR ~/ quanti, sommaG ~/ quanti, sommaB ~/ quanti)
      : PdfColor(0, 0, 0);
  return (PdfColor(sfondo[0], sfondo[1], sfondo[2]), inchiostro);
}
