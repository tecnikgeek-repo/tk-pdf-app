// Prova che penna, evidenziatore e firma finiscano davvero dentro il PDF.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:tkpdf/annota.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('i segni vengono scritti nel PDF', () async {
    final sorgente = File('test/dati/prova.pdf');
    expect(await sorgente.exists(), isTrue, reason: 'serve un PDF di prova');

    final lavoro = File('build/prove/prova-annotata.pdf');
    await lavoro.parent.create(recursive: true);
    await lavoro.writeAsBytes(await sorgente.readAsBytes());

    final prima = PdfDocument(inputBytes: await lavoro.readAsBytes());
    final pagine = prima.pages.count;
    final dimensionePrima = (await lavoro.readAsBytes()).length;
    prima.dispose();

    // firma finta: un quadratino blu
    final registratore = PictureRecorder();
    final tela = Canvas(registratore);
    tela.drawRect(const Rect.fromLTWH(0, 0, 120, 60), Paint()..color = const Color(0xFF1D4ED8));
    final immagine = await registratore.endRecording().toImage(120, 60);
    final png = (await immagine.toByteData(format: ImageByteFormat.png))!.buffer.asUint8List();

    await applicaTratti(
      lavoro.path,
      [
        Tratto(
          pagina: 1,
          punti: const [Offset(0.1, 0.2), Offset(0.4, 0.25), Offset(0.7, 0.2)],
          colore: Colors.red,
          spessore: 2.5 / 595.0,
          evidenziatore: false,
        ),
        Tratto(
          pagina: 1,
          punti: const [Offset(0.1, 0.4), Offset(0.8, 0.4)],
          colore: const Color(0xFFFDE047),
          spessore: 2.5 / 595.0,
          evidenziatore: true,
        ),
      ],
      firme: [
        FirmaDaMettere(pagina: 1, posizione: const Offset(0.55, 0.7), png: Uint8List.fromList(png)),
      ],
    );

    final dopo = PdfDocument(inputBytes: await lavoro.readAsBytes());
    expect(dopo.pages.count, pagine, reason: 'le pagine non devono cambiare');
    dopo.dispose();
    expect((await lavoro.readAsBytes()).length, greaterThan(dimensionePrima),
        reason: 'il file deve contenere i segni aggiunti');
    // ignore: avoid_print
    print('PDF annotato: ${lavoro.path}');
  });
}
