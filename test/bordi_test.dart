// Prova la ricerca dei bordi su foto finte: pagina di libro su un tavolo di legno, con un pezzo
// della pagina accanto separato dalla piega, e la raddrizzatura con la prospettiva.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tkpdf/bordi.dart';

const larghezza = 1200, altezza = 1600;

img.Point _p(num x, num y) => img.Point(x, y);

/// Foto finta: tavolo, pagina [pagina] (pixel) con righe di testo, ed eventualmente la pagina
/// accanto a sinistra, attaccata, con l'ombra della piega in mezzo.
img.Image fotoFinta(List<img.Point> pagina, {bool paginaAccanto = true, int? seme}) {
  final foto = img.Image(width: larghezza, height: altezza);
  img.fill(foto, color: img.ColorRgb8(138, 98, 62)); // legno
  final caso = math.Random(seme ?? 1);
  // venature del legno
  for (var i = 0; i < 60; i++) {
    final y = caso.nextInt(altezza);
    img.drawLine(foto, x1: 0, y1: y, x2: larghezza, y2: y + caso.nextInt(40) - 20,
        color: img.ColorRgb8(118, 82, 50), thickness: 3);
  }
  if (paginaAccanto) {
    img.fillPolygon(foto,
        vertices: [_p(0, pagina[0].y - 8), pagina[0], pagina[3], _p(0, pagina[3].y + 10)],
        color: img.ColorRgb8(236, 232, 222));
  }
  img.fillPolygon(foto, vertices: pagina, color: img.ColorRgb8(240, 236, 226));
  if (paginaAccanto) {
    // ombra della piega lungo il lato sinistro della pagina
    for (var k = 0; k < 4; k++) {
      final c = 150 + k * 18;
      img.drawLine(foto,
          x1: pagina[0].xi + k * 4, y1: pagina[0].yi, x2: pagina[3].xi + k * 4, y2: pagina[3].yi,
          color: img.ColorRgb8(c, c - 4, c - 12), thickness: 5);
    }
  }
  // righe di testo dentro la pagina
  final x0 = math.max(pagina[0].xi, pagina[3].xi) + 70, x1 = math.min(pagina[1].xi, pagina[2].xi) - 70;
  final y0 = math.max(pagina[0].yi, pagina[1].yi) + 90, y1 = math.min(pagina[2].yi, pagina[3].yi) - 90;
  for (var y = y0; y < y1; y += 34) {
    var x = x0;
    while (x < x1) {
      final parola = 20 + caso.nextInt(70);
      img.fillRect(foto, x1: x, y1: y, x2: math.min(x + parola, x1), y2: y + 12, color: img.ColorRgb8(40, 40, 45));
      x += parola + 14;
    }
  }
  return foto;
}

void controllaAngoli(List<Punto>? trovati, List<img.Point> attesi, {double tolleranza = 0.02}) {
  expect(trovati, isNotNull, reason: 'pagina non trovata');
  for (var i = 0; i < 4; i++) {
    final atteso = Punto(attesi[i].x / larghezza, attesi[i].y / altezza);
    final distanza = trovati![i].distanceTo(atteso);
    expect(distanza, lessThan(tolleranza),
        reason: 'angolo $i: trovato ${trovati[i]}, atteso $atteso');
  }
}

void main() {
  test('pagina di libro storta con la pagina accanto: la piega resta fuori', () {
    final pagina = [_p(250, 180), _p(1050, 230), _p(1000, 1450), _p(200, 1400)];
    final foto = fotoFinta(pagina);
    final trovati = trovaBordi(foto);
    controllaAngoli(trovati, pagina);

    final dritta = raddrizza(foto, trovati!);
    Directory('build').createSync(recursive: true);
    File('build/prova-bordi-foto.jpg').writeAsBytesSync(img.encodeJpg(foto));
    File('build/prova-bordi-pagina.jpg').writeAsBytesSync(img.encodeJpg(dritta));
    // la pagina è circa 800×1220: proporzioni conservate
    expect(dritta.height / dritta.width, closeTo(1220 / 800, 0.06));
    // niente legno né pagina accanto ai bordi della pagina raddrizzata
    for (final p in [img.Point(4, dritta.height ~/ 2), img.Point(dritta.width - 5, dritta.height ~/ 2)]) {
      final c = dritta.getPixel(p.xi, p.yi);
      expect(c.r - c.b, lessThan(40), reason: 'al bordo ($p) c\'è ancora il tavolo: $c');
    }
  });

  test('foglio dritto senza pagina accanto', () {
    final pagina = [_p(150, 200), _p(1050, 200), _p(1050, 1400), _p(150, 1400)];
    controllaAngoli(trovaBordi(fotoFinta(pagina, paginaAccanto: false, seme: 7)), pagina);
  });

  test('foto presa di sbieco (prospettiva)', () {
    final pagina = [_p(330, 260), _p(900, 240), _p(1110, 1480), _p(110, 1500)];
    controllaAngoli(trovaBordi(fotoFinta(pagina, paginaAccanto: false, seme: 3)), pagina);
  });

  test('pagina che riempie già la foto: niente da ritagliare', () {
    final foto = img.Image(width: larghezza, height: altezza);
    img.fill(foto, color: img.ColorRgb8(240, 238, 230));
    for (var y = 100; y < altezza - 100; y += 40) {
      img.fillRect(foto, x1: 80, y1: y, x2: larghezza - 80, y2: y + 12, color: img.ColorRgb8(30, 30, 30));
    }
    expect(trovaBordi(foto), isNull);
  });

  test('omografia: gli angoli finiscono dove devono', () {
    final da = [const Punto(0, 0), const Punto(99, 0), const Punto(99, 199), const Punto(0, 199)];
    final a = [const Punto(10, 20), const Punto(300, 5), const Punto(280, 400), const Punto(30, 390)];
    final m = omografia(da, a);
    for (var i = 0; i < 4; i++) {
      final d = m[6] * da[i].x + m[7] * da[i].y + 1;
      expect((m[0] * da[i].x + m[1] * da[i].y + m[2]) / d, closeTo(a[i].x, 1e-6));
      expect((m[3] * da[i].x + m[4] * da[i].y + m[5]) / d, closeTo(a[i].y, 1e-6));
    }
  });

  test('tutta la foto si riconosce', () {
    expect(tuttaLaFoto(angoliTuttaFoto), isTrue);
    expect(tuttaLaFoto(const [Punto(0.1, 0), Punto(1, 0), Punto(1, 1), Punto(0, 1)]), isFalse);
  });

  test('dal file foto al file pagina: ritaglio automatico, e foto intera lasciata intatta', () async {
    final cartella = Directory.systemTemp.createTempSync('tkpdf-ritaglio');
    final pagina = [_p(250, 180), _p(1050, 230), _p(1000, 1450), _p(200, 1400)];
    final foto = '${cartella.path}/foto.jpg';
    File(foto).writeAsBytesSync(img.encodeJpg(fotoFinta(pagina)));

    final pronta = await preparaFoto(foto);
    expect(pronta.bordi, isNotNull);
    expect(pronta.larghezza, larghezza);

    final ritagliata = await applicaRitaglio(foto, null, cartella.path, 0);
    expect(ritagliata, isNot(foto));
    final letta = img.decodeJpg(File(ritagliata).readAsBytesSync())!;
    expect(letta.height / letta.width, closeTo(1220 / 800, 0.06));

    expect(await applicaRitaglio(foto, angoliTuttaFoto, cartella.path, 1), foto);
    cartella.deleteSync(recursive: true);
  });
}
