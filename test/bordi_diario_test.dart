// Salva le maschere intermedie della ricerca dei bordi in build/ (per guardarle quando una prova fallisce).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tkpdf/bordi.dart';

import 'bordi_test.dart' show fotoFinta;

void main() {
  test('diario', () {
    Directory('build/diario').createSync(recursive: true);
    final casi = {
      'libro': fotoFinta([img.Point(250, 180), img.Point(1050, 230), img.Point(1000, 1450), img.Point(200, 1400)]),
      'dritto': fotoFinta([img.Point(150, 200), img.Point(1050, 200), img.Point(1050, 1400), img.Point(150, 1400)],
          paginaAccanto: false, seme: 7),
    };
    casi.forEach((nome, foto) {
      File('build/diario/$nome-foto.jpg').writeAsBytesSync(img.encodeJpg(img.copyResize(foto, width: 400)));
      final r = trovaBordi(foto, diario: (fase, m, w, h) {
        final out = img.Image(width: w, height: h);
        for (var i = 0; i < w * h; i++) {
          final v = m[i] == 1 ? 255 : 0;
          out.setPixelRgb(i % w, i ~/ w, v, v, v);
        }
        File('build/diario/$nome-$fase.png').writeAsBytesSync(img.encodePng(out));
      });
      // ignore: avoid_print
      print('$nome: $r');
    });
  });
}
