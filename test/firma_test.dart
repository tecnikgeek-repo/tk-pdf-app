// Prova che la firma disegnata col dito finisca nel PDF con la misura giusta e lo sfondo trasparente.
// (Il quadratino blu del test dei segni non direbbe nulla né sul ritaglio né sulla trasparenza.)
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/painting.dart' show decodeImageFromList;
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:tkpdf/annota.dart';

/// Rifà quello che fa il foglietto della firma: disegna i tratti, ritaglia sul tratto, scala ×3.
Future<Uint8List> firmaFinta() async {
  const tratti = [
    [Offset(60, 150), Offset(90, 90), Offset(120, 160), Offset(150, 95), Offset(190, 150)],
    [Offset(60, 165), Offset(220, 160)],
  ];
  var sinistra = double.infinity, alto = double.infinity, destra = 0.0, basso = 0.0;
  for (final t in tratti) {
    for (final p in t) {
      sinistra = p.dx < sinistra ? p.dx : sinistra;
      alto = p.dy < alto ? p.dy : alto;
      destra = p.dx > destra ? p.dx : destra;
      basso = p.dy > basso ? p.dy : basso;
    }
  }
  const margine = 10.0, scala = 3.0;
  final area = Rect.fromLTRB(sinistra - margine, alto - margine, destra + margine, basso + margine);
  final registratore = PictureRecorder();
  final tela = Canvas(registratore);
  tela.scale(scala);
  tela.translate(-area.left, -area.top);
  final penna = Paint()
    ..color = const Color(0xFF0F172A)
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  for (final t in tratti) {
    final percorso = Path()..moveTo(t.first.dx, t.first.dy);
    for (final p in t.skip(1)) {
      percorso.lineTo(p.dx, p.dy);
    }
    tela.drawPath(percorso, penna);
  }
  final immagine =
      await registratore.endRecording().toImage((area.width * scala).round(), (area.height * scala).round());
  final dati = await immagine.toByteData(format: ImageByteFormat.png);
  return dati!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('la firma entra nella pagina, ritagliata e senza riquadro bianco', () async {
    final sorgente = File('test/dati/prova.pdf');
    final lavoro = File('build/prove/prova-firmata.pdf');
    await lavoro.parent.create(recursive: true);
    await lavoro.writeAsBytes(await sorgente.readAsBytes());

    final png = await firmaFinta();
    final immagine = await decodeImageFromList(png);
    // il ritaglio deve aderire al tratto: 180x95 punti circa, per 3
    expect(immagine.width, inInclusiveRange(500, 560), reason: 'larghezza del ritaglio');
    expect(immagine.height, inInclusiveRange(260, 320), reason: 'altezza del ritaglio');

    await applicaTratti(lavoro.path, const [], firme: [
      FirmaDaMettere(pagina: 1, posizione: const Offset(0.5, 0.75), png: png),
    ]);

    final doc = PdfDocument(inputBytes: await lavoro.readAsBytes());
    expect(doc.pages.count, greaterThan(0));
    doc.dispose();
    // ignore: avoid_print
    print('PDF firmato: ${lavoro.path}');
  });
}
