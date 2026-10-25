// Trova i bordi della pagina in una foto e la raddrizza.
//
// Pensato per la foto di un libro o di un foglio: la carta è chiara e poco colorata, il tavolo no.
// Se nella foto entra un pezzo della pagina accanto, la piega del libro (una striscia più scura)
// fa da confine e il pezzo in più viene lasciato fuori.
//
// La prospettiva è quella vera (omografia): copyRectify del pacchetto image interpola in modo
// lineare e con la foto presa di sbieco le righe del testo uscirebbero storte.
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

typedef Punto = math.Point<double>;

/// Angoli in quest'ordine: alto sinistra, alto destra, basso destra, basso sinistra.
/// Coordinate da 0 a 1 rispetto alla foto già girata dritta (EXIF).
const angoliTuttaFoto = <Punto>[Punto(0, 0), Punto(1, 0), Punto(1, 1), Punto(0, 1)];

/// Lato lungo della copia su cui si cercano i bordi: basta e avanza, e fa presto.
const _latoRicerca = 400;

/// Lato lungo massimo della pagina raddrizzata (oltre, il PDF pesa senza guadagnare in lettura).
const _latoMassimo = 3200;

/// Foto pronta per la schermata di ritaglio.
class FotoPronta {
  const FotoPronta(this.anteprima, this.bordi, this.larghezza, this.altezza);

  /// JPEG piccolo da mostrare a schermo, già girato dritto.
  final Uint8List anteprima;

  /// Bordi trovati, o null se non c'era niente da togliere (o la pagina non si distingue).
  final List<Punto>? bordi;

  final int larghezza, altezza;
}

/// Legge la foto, cerca i bordi e prepara l'anteprima. Gira in un isolate: la decodifica
/// di una foto da 12 megapixel bloccherebbe lo schermo per un paio di secondi.
Future<FotoPronta> preparaFoto(String percorso) => Isolate.run(() {
      final foto = _leggi(percorso);
      final lato = foto.width >= foto.height;
      final piccola = img.copyResize(foto,
          width: lato ? math.min(1400, foto.width) : null,
          height: lato ? null : math.min(1400, foto.height),
          interpolation: img.Interpolation.average);
      return FotoPronta(img.encodeJpg(piccola, quality: 85), trovaBordi(foto), foto.width, foto.height);
    });

/// Ritaglia e raddrizza la foto e la salva in [cartella]. Con [angoli] null cerca i bordi da sé.
/// Se non c'è niente da togliere restituisce la foto originale, senza ricomprimerla.
Future<String> applicaRitaglio(String percorso, List<Punto>? angoli, String cartella, int numero) =>
    Isolate.run(() {
      final foto = _leggi(percorso);
      final scelti = angoli ?? trovaBordi(foto) ?? angoliTuttaFoto;
      if (tuttaLaFoto(scelti)) return percorso;
      final pagina = raddrizza(foto, scelti);
      final uscita = '$cartella/pagina-${DateTime.now().microsecondsSinceEpoch}-$numero.jpg';
      File(uscita).writeAsBytesSync(img.encodeJpg(pagina, quality: 90));
      return uscita;
    });

img.Image _leggi(String percorso) {
  final foto = img.decodeImage(File(percorso).readAsBytesSync());
  if (foto == null) throw const FormatException('formato della foto non riconosciuto');
  return img.bakeOrientation(foto);
}

/// Vero se gli angoli coincidono (quasi) con quelli della foto: non c'è niente da ritagliare.
bool tuttaLaFoto(List<Punto> angoli) {
  for (var i = 0; i < 4; i++) {
    if (angoli[i].distanceTo(angoliTuttaFoto[i]) > 0.004) return false;
  }
  return true;
}

/// Cerca la pagina nella foto. Null se non si distingue o se occupa già tutta la foto.
/// [diario] serve alle prove: riceve le maschere intermedie (nome, 0/1 per punto, larghezza, altezza).
List<Punto>? trovaBordi(img.Image foto, {void Function(String, Uint8List, int, int)? diario}) {
  final orizzontale = foto.width >= foto.height;
  final piccola = img.copyResize(foto,
      width: orizzontale ? _latoRicerca : null,
      height: orizzontale ? null : _latoRicerca,
      interpolation: img.Interpolation.average);
  final w = piccola.width, h = piccola.height;

  // «quanto sembra carta»: chiaro e poco colorato (il legno del tavolo è chiaro ma colorato)
  final luce = Float64List(w * h);
  final carta = Float64List(w * h);
  for (final p in piccola) {
    final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
    final l = 0.299 * r + 0.587 * g + 0.114 * b;
    final colore = math.max(r, math.max(g, b)) - math.min(r, math.min(g, b));
    luce[p.y * w + p.x] = l;
    carta[p.y * w + p.x] = l - colore;
  }
  final liscia = _sfoca(carta, w, h, 2);

  var maschera = _soglia(liscia);
  // apertura: stacca i ponticelli sottili (bordi dei fogli, ombre leggere) tra pagina e resto
  maschera = _allarga(_restringi(maschera, w, h, 2), w, h, 2);

  diario?.call('maschera', maschera, w, h);
  final pezzo = _pezzoCentrale(maschera, w, h);
  if (pezzo == null) return null;
  diario?.call('pezzo', Uint8List.fromList(pezzo), w, h);

  _tagliaPiega(pezzo, _sfoca(luce, w, h, 1), w, h);
  diario?.call('senza-piega', pezzo, w, h);

  final involucro = _involucro(pezzo, w, h);
  if (involucro.length < 4) return null;
  final quattro = _quadrilatero(involucro);
  final area = _area(quattro);
  if (area < 0.12 * w * h) return null;
  if (area > 0.96 * w * h) return null; // la pagina riempie già la foto

  return [
    for (final p in quattro)
      Punto(((p.x + 0.5) / w).clamp(0.0, 1.0), ((p.y + 0.5) / h).clamp(0.0, 1.0)),
  ];
}

/// Sfocatura a scatola, separabile.
Float64List _sfoca(Float64List v, int w, int h, int raggio) {
  final tmp = Float64List(w * h), out = Float64List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var s = 0.0, n = 0;
      for (var k = -raggio; k <= raggio; k++) {
        final xx = x + k;
        if (xx >= 0 && xx < w) {
          s += v[y * w + xx];
          n++;
        }
      }
      tmp[y * w + x] = s / n;
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var s = 0.0, n = 0;
      for (var k = -raggio; k <= raggio; k++) {
        final yy = y + k;
        if (yy >= 0 && yy < h) {
          s += tmp[yy * w + x];
          n++;
        }
      }
      out[y * w + x] = s / n;
    }
  }
  return out;
}

/// Soglia di Otsu: divide i punti in «carta» e «resto».
Uint8List _soglia(Float64List v) {
  final istogramma = List<int>.filled(256, 0);
  for (final x in v) {
    istogramma[x.clamp(0, 255).toInt()]++;
  }
  final totale = v.length;
  var somma = 0.0;
  for (var i = 0; i < 256; i++) {
    somma += i * istogramma[i];
  }
  var sommaSotto = 0.0, pesoSotto = 0, migliore = 0.0, soglia = 128;
  for (var i = 0; i < 256; i++) {
    pesoSotto += istogramma[i];
    if (pesoSotto == 0) continue;
    final pesoSopra = totale - pesoSotto;
    if (pesoSopra == 0) break;
    sommaSotto += i * istogramma[i];
    final mediaSotto = sommaSotto / pesoSotto;
    final mediaSopra = (somma - sommaSotto) / pesoSopra;
    final varianza = pesoSotto * pesoSopra * (mediaSotto - mediaSopra) * (mediaSotto - mediaSopra);
    if (varianza > migliore) {
      migliore = varianza;
      soglia = i;
    }
  }
  final out = Uint8List(v.length);
  for (var i = 0; i < v.length; i++) {
    out[i] = v[i] > soglia ? 1 : 0;
  }
  return out;
}

Uint8List _restringi(Uint8List m, int w, int h, int r) => _morfologia(m, w, h, r, true);
Uint8List _allarga(Uint8List m, int w, int h, int r) => _morfologia(m, w, h, r, false);

Uint8List _morfologia(Uint8List m, int w, int h, int r, bool restringi) {
  final tmp = Uint8List(w * h), out = Uint8List(w * h);
  final cerco = restringi ? 0 : 1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var trovato = false;
      for (var k = -r; k <= r && !trovato; k++) {
        final xx = (x + k).clamp(0, w - 1);
        trovato = m[y * w + xx] == cerco;
      }
      tmp[y * w + x] = trovato == restringi ? 0 : 1;
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var trovato = false;
      for (var k = -r; k <= r && !trovato; k++) {
        final yy = (y + k).clamp(0, h - 1);
        trovato = tmp[yy * w + x] == cerco;
      }
      out[y * w + x] = trovato == restringi ? 0 : 1;
    }
  }
  return out;
}

/// La zona di carta che sta al centro della foto (chi fotografa una pagina la mette in mezzo).
Uint8List? _pezzoCentrale(Uint8List m, int w, int h) {
  final etichette = Int32List(w * h);
  var prossima = 0;
  int? scelta;
  var migliorPunteggio = 0;
  final coda = Int32List(w * h);
  for (var inizio = 0; inizio < w * h; inizio++) {
    if (m[inizio] == 0 || etichette[inizio] != 0) continue;
    prossima++;
    var testa = 0, fine = 0, area = 0, alCentro = 0;
    coda[fine++] = inizio;
    etichette[inizio] = prossima;
    while (testa < fine) {
      final i = coda[testa++];
      final x = i % w, y = i ~/ w;
      area++;
      if (x > w * 0.3 && x < w * 0.7 && y > h * 0.3 && y < h * 0.7) alCentro++;
      void prova(int j) {
        if (m[j] == 1 && etichette[j] == 0) {
          etichette[j] = prossima;
          coda[fine++] = j;
        }
      }

      if (x > 0) prova(i - 1);
      if (x < w - 1) prova(i + 1);
      if (y > 0) prova(i - w);
      if (y < h - 1) prova(i + w);
    }
    if (area < w * h * 0.05) continue;
    final punteggio = alCentro * 4 + area;
    if (punteggio > migliorPunteggio) {
      migliorPunteggio = punteggio;
      scelta = prossima;
    }
  }
  if (scelta == null) return null;
  final out = Uint8List(w * h);
  for (var i = 0; i < w * h; i++) {
    if (etichette[i] == scelta) out[i] = 1;
  }
  return out;
}

/// Se dentro la pagina c'è la piega del libro (una valle di luce stretta verso un lato),
/// toglie quello che sta oltre: è la pagina accanto.
void _tagliaPiega(Uint8List pezzo, Float64List luce, int w, int h) {
  var x0 = w, x1 = -1, y0 = h, y1 = -1;
  for (var i = 0; i < w * h; i++) {
    if (pezzo[i] == 0) continue;
    final x = i % w, y = i ~/ w;
    x0 = math.min(x0, x);
    x1 = math.max(x1, x);
    y0 = math.min(y0, y);
    y1 = math.max(y1, y);
  }
  if (x1 < 0) return;

  _taglia(pezzo, luce, w, h, x0, x1, y0, y1, verticale: true);
  // piega orizzontale (libro fotografato di traverso)
  _taglia(pezzo, luce, w, h, x0, x1, y0, y1, verticale: false);
}

/// Cerca la piega anche un po' inclinata (fino a ±10°: nelle foto vere non è mai dritta)
/// e toglie quello che sta oltre la linea.
void _taglia(Uint8List pezzo, Float64List luce, int w, int h, int x0, int x1, int y0, int y1,
    {required bool verticale}) {
  // «a» è l'asse lungo cui si cerca la piega, «b» quello lungo cui la piega corre
  final a0 = verticale ? x0 : y0, a1 = verticale ? x1 : y1, limiteA = verticale ? w : h;
  final b0 = verticale ? y0 : x0, b1 = verticale ? y1 : x1;
  final f0 = b0 + (b1 - b0) ~/ 4, f1 = b1 - (b1 - b0) ~/ 4;
  final bm = (b0 + b1) / 2;
  double valore(int a, int b) => verticale ? luce[b * w + a] : luce[a * w + b];

  (double, bool, double)? migliore;
  var piuProfonda = 0.0;
  for (var gradi = -10; gradi <= 10; gradi++) {
    final t = math.tan(gradi * math.pi / 180);
    final profilo = <double>[];
    for (var c = a0; c <= a1; c++) {
      final valori = <double>[];
      for (var b = f0; b <= f1; b++) {
        final a = (c + (b - bm) * t).round();
        if (a >= 0 && a < limiteA) valori.add(valore(a, b));
      }
      profilo.add(_carta(valori));
    }
    final valle = _valle(profilo);
    if (valle != null && valle.$3 > piuProfonda) {
      piuProfonda = valle.$3;
      migliore = ((a0 + valle.$1).toDouble(), valle.$2, t);
    }
  }
  if (migliore == null) return;
  final (c, togliPrima, t) = migliore;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final a = verticale ? x : y, b = verticale ? y : x;
      // due punti in più verso la pagina: l'ombra della piega resta fuori anche lei
      final linea = c + (b - bm) * t;
      if (togliPrima ? a <= linea + 2 : a >= linea - 2) pezzo[y * w + x] = 0;
    }
  }
}

/// Luce della carta lungo una linea: il 95° percentile, così le parole stampate
/// (che con la media sembrerebbero tante piccole pieghe) non contano, la piega sì perché è scura dappertutto.
double _carta(List<double> valori) {
  if (valori.isEmpty) return 0;
  valori.sort();
  return valori[(valori.length * 0.95).floor().clamp(0, valori.length - 1)];
}

/// Posizione della piega nel profilo di luce, se va tolto il lato prima (true) o dopo (false)
/// e quanto è scura.
/// Cerca solo nelle fasce esterne: la pagina accanto è un pezzetto, non metà foto.
(int, bool, double)? _valle(List<double> profilo) {
  final n = profilo.length;
  if (n < 30) return null;
  final ordinati = [...profilo]..sort();
  final mediana = ordinati[n ~/ 2];
  final passo = math.max(2, (n * 0.025).round());
  (int, bool, double)? migliore;
  var piuProfonda = 0.0;
  for (var i = passo; i < n - passo; i++) {
    final versoInizio = i < n * 0.38;
    final versoFine = i > n * 0.62;
    if (!versoInizio && !versoFine) continue;
    final v = profilo[i];
    if (v > mediana * 0.82) continue;
    // valle, non gradino: dopo la piega torna la carta da entrambi i lati
    final prima = profilo[i - passo], dopo = profilo[i + passo];
    if (prima < v + mediana * 0.1 || dopo < v + mediana * 0.1) continue;
    final profondita = mediana - v;
    if (profondita > piuProfonda) {
      piuProfonda = profondita;
      migliore = (i, versoInizio, profondita);
    }
  }
  return migliore;
}

/// Involucro convesso dei punti della pagina (bastano il primo e l'ultimo di ogni riga).
List<math.Point<int>> _involucro(Uint8List pezzo, int w, int h) {
  final punti = <math.Point<int>>[];
  for (var y = 0; y < h; y++) {
    var primo = -1, ultimo = -1;
    for (var x = 0; x < w; x++) {
      if (pezzo[y * w + x] == 1) {
        if (primo < 0) primo = x;
        ultimo = x;
      }
    }
    if (primo >= 0) {
      punti.add(math.Point(primo, y));
      if (ultimo != primo) punti.add(math.Point(ultimo, y));
    }
  }
  punti.sort((a, b) => a.x != b.x ? a.x - b.x : a.y - b.y);
  if (punti.length < 3) return punti;
  int giro(math.Point<int> o, math.Point<int> a, math.Point<int> b) =>
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  final sotto = <math.Point<int>>[], sopra = <math.Point<int>>[];
  for (final p in punti) {
    while (sotto.length >= 2 && giro(sotto[sotto.length - 2], sotto.last, p) <= 0) {
      sotto.removeLast();
    }
    sotto.add(p);
  }
  for (final p in punti.reversed) {
    while (sopra.length >= 2 && giro(sopra[sopra.length - 2], sopra.last, p) <= 0) {
      sopra.removeLast();
    }
    sopra.add(p);
  }
  return [...sotto.sublist(0, sotto.length - 1), ...sopra.sublist(0, sopra.length - 1)];
}

/// Il quadrilatero più grande con i vertici sull'involucro, ordinato alto-sx, alto-dx, basso-dx, basso-sx.
List<Punto> _quadrilatero(List<math.Point<int>> involucro) {
  final n = involucro.length;
  final p = [for (final q in involucro) Punto(q.x.toDouble(), q.y.toDouble())];
  int estremo(double Function(Punto) f) {
    var m = 0;
    for (var i = 1; i < n; i++) {
      if (f(p[i]) > f(p[m])) m = i;
    }
    return m;
  }

  // partenza: i quattro punti più in fuori in diagonale, poi si migliora un angolo alla volta
  var scelti = [
    estremo((q) => -q.x - q.y),
    estremo((q) => q.x - q.y),
    estremo((q) => q.x + q.y),
    estremo((q) => -q.x + q.y),
  ]..sort();
  if (scelti.toSet().length < 4) {
    scelti = [0, n ~/ 4, n ~/ 2, 3 * n ~/ 4];
  }
  for (var giro = 0; giro < 8; giro++) {
    var cambiato = false;
    for (var k = 0; k < 4; k++) {
      final prec = scelti[(k + 3) % 4], succ = scelti[(k + 1) % 4];
      var migliore = scelti[k];
      var areaMigliore = _area([for (final s in scelti) p[s]]);
      for (var i = (prec + 1) % n; i != succ; i = (i + 1) % n) {
        final prova = [...scelti]..[k] = i;
        final a = _area([for (final s in prova) p[s]]);
        if (a > areaMigliore) {
          areaMigliore = a;
          migliore = i;
        }
      }
      if (migliore != scelti[k]) {
        scelti[k] = migliore;
        cambiato = true;
      }
    }
    if (!cambiato) break;
  }
  final quattro = [for (final s in scelti) p[s]];

  // ordine in senso orario a schermo, partendo dall'angolo in alto a sinistra
  final cx = quattro.fold(0.0, (s, q) => s + q.x) / 4;
  final cy = quattro.fold(0.0, (s, q) => s + q.y) / 4;
  quattro.sort((a, b) => math.atan2(a.y - cy, a.x - cx).compareTo(math.atan2(b.y - cy, b.x - cx)));
  var primo = 0;
  for (var i = 1; i < 4; i++) {
    if (quattro[i].x + quattro[i].y < quattro[primo].x + quattro[primo].y) primo = i;
  }
  return [for (var i = 0; i < 4; i++) quattro[(primo + i) % 4]];
}

double _area(List<Punto> q) {
  var s = 0.0;
  for (var i = 0; i < q.length; i++) {
    final a = q[i], b = q[(i + 1) % q.length];
    s += a.x * b.y - b.x * a.y;
  }
  return s.abs() / 2;
}

/// Raddrizza il quadrilatero [angoli] (da 0 a 1) in un rettangolo.
img.Image raddrizza(img.Image foto, List<Punto> angoli) {
  final W = foto.width, H = foto.height;
  final s = [for (final a in angoli) Punto(a.x * (W - 1), a.y * (H - 1))];
  var larghezza = math.max(s[0].distanceTo(s[1]), s[3].distanceTo(s[2]));
  var altezza = math.max(s[0].distanceTo(s[3]), s[1].distanceTo(s[2]));
  final riduzione = math.min(1.0, _latoMassimo / math.max(larghezza, altezza));
  final ow = math.max(2, (larghezza * riduzione).round());
  final oh = math.max(2, (altezza * riduzione).round());

  final m = omografia(
    [Punto(0, 0), Punto(ow - 1.0, 0), Punto(ow - 1.0, oh - 1.0), Punto(0, oh - 1.0)],
    s,
  );

  final sorgente = foto.getBytes(order: img.ChannelOrder.rgb);
  final uscita = Uint8List(ow * oh * 3);
  for (var y = 0; y < oh; y++) {
    for (var x = 0; x < ow; x++) {
      final d = m[6] * x + m[7] * y + 1;
      final sx = ((m[0] * x + m[1] * y + m[2]) / d).clamp(0.0, W - 1.0);
      final sy = ((m[3] * x + m[4] * y + m[5]) / d).clamp(0.0, H - 1.0);
      // bilineare
      final x0 = sx.floor(), y0 = sy.floor();
      final x1 = math.min(x0 + 1, W - 1), y1 = math.min(y0 + 1, H - 1);
      final fx = sx - x0, fy = sy - y0;
      final a = (y0 * W + x0) * 3, b = (y0 * W + x1) * 3, c = (y1 * W + x0) * 3, e = (y1 * W + x1) * 3;
      final o = (y * ow + x) * 3;
      for (var k = 0; k < 3; k++) {
        final alto = sorgente[a + k] + (sorgente[b + k] - sorgente[a + k]) * fx;
        final basso = sorgente[c + k] + (sorgente[e + k] - sorgente[c + k]) * fx;
        uscita[o + k] = (alto + (basso - alto) * fy).round();
      }
    }
  }
  return img.Image.fromBytes(width: ow, height: oh, bytes: uscita.buffer, numChannels: 3);
}

/// Coefficienti h0..h7 della trasformazione che porta i 4 punti [da] nei 4 punti [a]
/// (h8 = 1): x' = (h0 x + h1 y + h2) / (h6 x + h7 y + 1), y' = (h3 x + h4 y + h5) / (…).
List<double> omografia(List<Punto> da, List<Punto> a) {
  final righe = <List<double>>[];
  for (var i = 0; i < 4; i++) {
    final x = da[i].x, y = da[i].y, u = a[i].x, v = a[i].y;
    righe.add([x, y, 1, 0, 0, 0, -u * x, -u * y, u]);
    righe.add([0, 0, 0, x, y, 1, -v * x, -v * y, v]);
  }
  // eliminazione di Gauss con pivot parziale
  for (var c = 0; c < 8; c++) {
    var pivot = c;
    for (var r = c + 1; r < 8; r++) {
      if (righe[r][c].abs() > righe[pivot][c].abs()) pivot = r;
    }
    final t = righe[c];
    righe[c] = righe[pivot];
    righe[pivot] = t;
    final p = righe[c][c];
    if (p.abs() < 1e-12) throw StateError('angoli allineati: impossibile raddrizzare');
    for (var r = 0; r < 8; r++) {
      if (r == c) continue;
      final f = righe[r][c] / p;
      if (f == 0) continue;
      for (var k = c; k < 9; k++) {
        righe[r][k] -= f * righe[c][k];
      }
    }
  }
  return [for (var r = 0; r < 8; r++) righe[r][8] / righe[r][r]];
}
