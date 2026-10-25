// Prova che la modifica di una riga sostituisca davvero il testo nel PDF.
// Il disegno della pagina (che nell'app fa pdfium) qui viene fornito dal test.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:tkpdf/modifica_testo.dart';

/// Finto disegno della pagina: un foglio bianco con una riga grigia al posto del testo.
Future<(Uint8List, int, int)?> fintoDisegno(String percorso, int pagina) async {
  const larghezza = 1200, altezza = 1700;
  final registratore = ui.PictureRecorder();
  final tela = ui.Canvas(registratore);
  tela.drawRect(ui.Rect.fromLTWH(0, 0, larghezza.toDouble(), altezza.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  tela.drawRect(const ui.Rect.fromLTWH(100, 400, 900, 40), ui.Paint()..color = const ui.Color(0xFF333333));
  final immagine = await registratore.endRecording().toImage(larghezza, altezza);
  final dati = await immagine.toByteData(format: ui.ImageByteFormat.rawRgba);
  immagine.dispose();
  return (dati!.buffer.asUint8List(), larghezza, altezza);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cambiare una riga: il nuovo testo c\'è, il vecchio sparisce, il resto resta cercabile', () async {
    final sorgente = File('test/dati/prova.pdf');
    final lavoro = File('build/prove/prova-testo.pdf');
    await lavoro.parent.create(recursive: true);
    await lavoro.writeAsBytes(await sorgente.readAsBytes());

    final righe = await righeDellaPagina(lavoro.path, 1);
    expect(righe, isNotEmpty, reason: 'la pagina deve avere testo');
    final bersaglio = righe.firstWhere((r) => r.testo.contains('Importo'));

    await cambiaRiga(lavoro.path, 1, bersaglio, 'Importo totale: 990,00 euro - Scadenza: 15/10/2026',
        disegnaPagina: fintoDisegno);

    final doc = PdfDocument(inputBytes: await lavoro.readAsBytes());
    final testo = PdfTextExtractor(doc).extractText(startPageIndex: 0, endPageIndex: 0);
    doc.dispose();
    expect(testo.contains('990,00'), isTrue, reason: 'deve comparire il testo nuovo');
    expect(testo.contains('1.250,00'), isFalse, reason: 'il testo vecchio deve sparire');
    expect(testo.contains('Mario Rossi'), isTrue, reason: 'le altre righe restano cercabili');
    // ignore: avoid_print
    print('PDF con testo cambiato: ${lavoro.path}');
  });
}
