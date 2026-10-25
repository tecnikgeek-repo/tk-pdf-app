// Banco di prova: apre il ritaglio su una foto finta (libro su un tavolo, con la pagina accanto).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'bordi.dart';
import 'ritaglio.dart';
import 'tema.dart';

Future<FotoPronta> _fotoFinta(String _) async {
  const w = 900, h = 1200;
  final foto = img.Image(width: w, height: h);
  img.fill(foto, color: img.ColorRgb8(138, 98, 62));
  final caso = math.Random(2);
  for (var i = 0; i < 50; i++) {
    final y = caso.nextInt(h);
    img.drawLine(foto, x1: 0, y1: y, x2: w, y2: y + caso.nextInt(30) - 15, color: img.ColorRgb8(118, 82, 50), thickness: 3);
  }
  final pagina = [img.Point(190, 140), img.Point(790, 175), img.Point(750, 1090), img.Point(150, 1050)];
  img.fillPolygon(foto,
      vertices: [img.Point(0, 130), pagina[0], pagina[3], img.Point(0, 1060)], color: img.ColorRgb8(236, 232, 222));
  img.fillPolygon(foto, vertices: pagina, color: img.ColorRgb8(240, 236, 226));
  for (var k = 0; k < 4; k++) {
    final c = 150 + k * 18;
    img.drawLine(foto, x1: 190 + k * 3, y1: 140, x2: 150 + k * 3, y2: 1050, color: img.ColorRgb8(c, c - 4, c - 12), thickness: 4);
  }
  for (var y = 230; y < 980; y += 26) {
    var x = 260;
    while (x < 690) {
      final parola = 15 + caso.nextInt(50);
      img.fillRect(foto, x1: x, y1: y, x2: math.min(x + parola, 690), y2: y + 9, color: img.ColorRgb8(40, 40, 45));
      x += parola + 12;
    }
  }
  return FotoPronta(img.encodeJpg(foto, quality: 85), trovaBordi(foto), w, h);
}

void main() {
  configTk = configPdf;
  runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: temaKit(),
      home: SchermataRitaglio(foto: const ['a', 'b', 'c'], prepara: _fotoFinta)));
}
