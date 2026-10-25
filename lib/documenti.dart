// Operazioni sui PDF: creazione da foto, unisci, ruota, elimina pagine, password, compressione.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Cartella dei documenti dell'app (quella visibile al sistema per la condivisione).
Future<Directory> cartellaDocumenti() async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/tkPDF');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// Riscrive un PDF al posto di quello vecchio.
///
/// Prima scrive un file accanto e poi lo sposta sopra: il visualizzatore tiene aperto il file
/// mentre lavoriamo e riscriverlo di colpo glielo farebbe leggere a metà (pagine nere o app chiusa).
/// Spostandolo, il documento già aperto resta intatto finché non viene ricaricato.
Future<void> scriviSopra(String percorso, List<int> byte) async {
  final temporaneo = File('$percorso.nuovo');
  await temporaneo.writeAsBytes(byte, flush: true);
  await temporaneo.rename(percorso);
}

/// Percorso libero: «nome.pdf», poi «nome (1).pdf»… come fa tk-pdf sul computer.
Future<String> percorsoLibero(String nomeSenzaEstensione, {String estensione = '.pdf'}) async {
  final dir = await cartellaDocumenti();
  var tentativo = '${dir.path}/$nomeSenzaEstensione$estensione';
  var n = 1;
  while (await File(tentativo).exists()) {
    tentativo = '${dir.path}/$nomeSenzaEstensione ($n)$estensione';
    n++;
  }
  return tentativo;
}

/// PDF da una lista di immagini: una pagina per foto, adattata al foglio.
Future<String> pdfDaImmagini(List<String> immagini, {String nome = 'Scansione'}) async {
  final doc = PdfDocument();
  doc.pageSettings.margins.all = 0;
  try {
    for (final percorso in immagini) {
      final byte = await File(percorso).readAsBytes();
      final immagine = PdfBitmap(byte);
      final orizzontale = immagine.width > immagine.height;
      doc.pageSettings.orientation =
          orizzontale ? PdfPageOrientation.landscape : PdfPageOrientation.portrait;
      final pagina = doc.pages.add();
      final area = pagina.getClientSize();
      final scala = (area.width / immagine.width) < (area.height / immagine.height)
          ? area.width / immagine.width
          : area.height / immagine.height;
      final larghezza = immagine.width * scala;
      final altezza = immagine.height * scala;
      pagina.graphics.drawImage(
        immagine,
        Rect.fromLTWH((area.width - larghezza) / 2, (area.height - altezza) / 2, larghezza, altezza),
      );
    }
    return await _salva(doc, nome);
  } finally {
    doc.dispose();
  }
}

/// Unisce più PDF in uno solo.
Future<String> unisci(List<String> pdf, {String nome = 'Uniti'}) async {
  final out = PdfDocument();
  out.pageSettings.margins.all = 0;
  try {
    for (final percorso in pdf) {
      final src = PdfDocument(inputBytes: await File(percorso).readAsBytes());
      _copiaPagine(src, out);
      src.dispose();
    }
    return await _salva(out, nome);
  } finally {
    out.dispose();
  }
}

/// Copia le pagine di un documento in un altro (questa versione di Syncfusion non unisce da sola).
void _copiaPagine(PdfDocument da, PdfDocument a, {List<int>? soloIndici}) {
  for (var i = 0; i < da.pages.count; i++) {
    if (soloIndici != null && !soloIndici.contains(i)) continue;
    final origine = da.pages[i];
    final modello = origine.createTemplate();
    a.pageSettings.size = origine.size;
    final pagina = a.pages.add();
    pagina.graphics.drawPdfTemplate(modello, Offset.zero, origine.size);
  }
}

/// Ruota, elimina o estrae pagine. `tenere` sono gli indici (da 0) da conservare.
Future<void> modificaPagine(String percorso, {List<int>? tenere, Map<int, int>? rotazioni}) async {
  final doc = PdfDocument(inputBytes: await File(percorso).readAsBytes());
  try {
    rotazioni?.forEach((indice, gradi) {
      if (indice < doc.pages.count) {
        doc.pages[indice].rotation = _rotazione(gradi);
      }
    });
    if (tenere != null) {
      for (var i = doc.pages.count - 1; i >= 0; i--) {
        if (!tenere.contains(i)) doc.pages.removeAt(i);
      }
    }
    await scriviSopra(percorso, await doc.save());
  } finally {
    doc.dispose();
  }
}

/// Riscrive il documento con le pagine nell'ordine dato e con le rotazioni scelte.
/// `ordine` contiene gli indici di partenza; `rotazioni` è indicizzata sul nuovo ordine.
Future<void> riordina(String percorso, List<int> ordine, Map<int, int> rotazioni) async {
  final src = PdfDocument(inputBytes: await File(percorso).readAsBytes());
  final out = PdfDocument();
  out.pageSettings.margins.all = 0;
  try {
    for (var nuovo = 0; nuovo < ordine.length; nuovo++) {
      final origine = src.pages[ordine[nuovo]];
      final modello = origine.createTemplate();
      out.pageSettings.size = origine.size;
      final pagina = out.pages.add();
      pagina.graphics.drawPdfTemplate(modello, Offset.zero, origine.size);
      final gradi = rotazioni[nuovo] ?? 0;
      if (gradi % 360 != 0) pagina.rotation = _rotazione(gradi);
    }
    await scriviSopra(percorso, await out.save());
  } finally {
    out.dispose();
    src.dispose();
  }
}

PdfPageRotateAngle _rotazione(int gradi) {
  switch (((gradi % 360) + 360) % 360) {
    case 90:
      return PdfPageRotateAngle.rotateAngle90;
    case 180:
      return PdfPageRotateAngle.rotateAngle180;
    case 270:
      return PdfPageRotateAngle.rotateAngle270;
    default:
      return PdfPageRotateAngle.rotateAngle0;
  }
}

/// Copia protetta da password (chi apre il file deve inserirla).
Future<String> conPassword(String percorso, String password) async {
  final doc = PdfDocument(inputBytes: await File(percorso).readAsBytes());
  try {
    doc.security.algorithm = PdfEncryptionAlgorithm.aesx256Bit;
    doc.security.userPassword = password;
    doc.security.ownerPassword = password;
    final nome = nomeSenzaEstensione(percorso);
    return await _salva(doc, '$nome protetto');
  } finally {
    doc.dispose();
  }
}

/// Copia più leggera (immagini e struttura compresse).
Future<String> comprimi(String percorso) async {
  final doc = PdfDocument(inputBytes: await File(percorso).readAsBytes());
  try {
    doc.compressionLevel = PdfCompressionLevel.best;
    final nome = nomeSenzaEstensione(percorso);
    return await _salva(doc, '$nome compresso');
  } finally {
    doc.dispose();
  }
}

/// Divide: un file per ogni gruppo di pagine indicato.
Future<List<String>> dividi(String percorso, List<List<int>> gruppi) async {
  final byte = await File(percorso).readAsBytes();
  final nome = nomeSenzaEstensione(percorso);
  final creati = <String>[];
  for (var g = 0; g < gruppi.length; g++) {
    final src = PdfDocument(inputBytes: byte);
    final out = PdfDocument();
    out.pageSettings.margins.all = 0;
    try {
      _copiaPagine(src, out, soloIndici: gruppi[g]);
      creati.add(await _salva(out, '$nome parte ${g + 1}'));
    } finally {
      out.dispose();
      src.dispose();
    }
  }
  return creati;
}

/// Numero di pagine, senza aprire il visualizzatore.
Future<int> numeroPagine(String percorso) async {
  final doc = PdfDocument(inputBytes: await File(percorso).readAsBytes());
  final n = doc.pages.count;
  doc.dispose();
  return n;
}

/// Nome del file senza «.pdf».
String nomeSenzaEstensione(String percorso) {
  final file = percorso.split(Platform.pathSeparator).last.split('/').last;
  return file.toLowerCase().endsWith('.pdf') ? file.substring(0, file.length - 4) : file;
}

Future<String> _salva(PdfDocument doc, String nome) async {
  final byte = Uint8List.fromList(await doc.save());
  final percorso = await percorsoLibero(nome);
  await File(percorso).writeAsBytes(byte, flush: true);
  return percorso;
}
