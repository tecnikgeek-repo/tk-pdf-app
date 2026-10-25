// Disegno a dito sopra le pagine: penna, evidenziatore e firma.
// I segni si disegnano a schermo mentre si traccia e, al salvataggio, entrano nella pagina del PDF.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'documenti.dart';
import 'tema.dart';

enum Strumento { nessuno, penna, evidenziatore, firma, testo }

/// Un tratto: punti in frazione di pagina (0..1), così vale a qualsiasi zoom.
class Tratto {
  Tratto({required this.pagina, required this.punti, required this.colore, required this.spessore,
      required this.evidenziatore});

  final int pagina; // numero di pagina, da 1
  final List<Offset> punti;
  final Color colore;
  final double spessore; // in frazione di larghezza pagina
  final bool evidenziatore;
}

/// Pennello scelto nella barra degli strumenti.
class Pennello {
  const Pennello(this.colore, this.spessore);
  final Color colore;
  final double spessore; // punti PDF
}

/// Livello trasparente su una pagina: raccoglie i tratti disegnati col dito.
class LivelloDisegno extends StatefulWidget {
  const LivelloDisegno({
    super.key,
    required this.pagina,
    required this.dimensione,
    required this.strumento,
    required this.pennello,
    required this.tratti,
    required this.onNuovoTratto,
    this.firme = const [],
  });

  final int pagina;
  final Size dimensione; // dimensione della pagina a schermo
  final Strumento strumento;
  final Pennello pennello;
  final List<Tratto> tratti;
  final void Function(Tratto) onNuovoTratto;
  final List<FirmaDaMettere> firme;

  @override
  State<LivelloDisegno> createState() => _LivelloDisegnoState();
}

class _LivelloDisegnoState extends State<LivelloDisegno> {
  List<Offset>? _corrente;

  bool get _attivo => widget.strumento == Strumento.penna || widget.strumento == Strumento.evidenziatore;

  @override
  Widget build(BuildContext context) {
    final miei = widget.tratti.where((t) => t.pagina == widget.pagina).toList();
    final mieFirme = widget.firme.where((f) => f.pagina == widget.pagina).toList();
    return IgnorePointer(
      ignoring: !_attivo,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => setState(() => _corrente = [_frazione(d.localPosition)]),
        onPanUpdate: (d) => setState(() => _corrente?.add(_frazione(d.localPosition))),
        onPanEnd: (_) {
          final punti = _corrente;
          setState(() => _corrente = null);
          if (punti == null || punti.length < 2) return;
          widget.onNuovoTratto(Tratto(
            pagina: widget.pagina,
            punti: punti,
            colore: widget.pennello.colore,
            spessore: widget.pennello.spessore / 595.0, // riferito alla larghezza di un A4
            evidenziatore: widget.strumento == Strumento.evidenziatore,
          ));
        },
        child: CustomPaint(
          size: widget.dimensione,
          painter: _PittoreTratti(
            tratti: miei,
            firme: mieFirme,
            corrente: _corrente,
            colore: widget.pennello.colore,
            spessore: widget.pennello.spessore / 595.0,
            evidenziatore: widget.strumento == Strumento.evidenziatore,
          ),
        ),
      ),
    );
  }

  Offset _frazione(Offset posizione) => Offset(
        (posizione.dx / widget.dimensione.width).clamp(0.0, 1.0),
        (posizione.dy / widget.dimensione.height).clamp(0.0, 1.0),
      );
}

class _PittoreTratti extends CustomPainter {
  _PittoreTratti({
    required this.tratti,
    required this.firme,
    required this.corrente,
    required this.colore,
    required this.spessore,
    required this.evidenziatore,
  });

  final List<Tratto> tratti;
  final List<FirmaDaMettere> firme;
  final List<Offset>? corrente;
  final Color colore;
  final double spessore;
  final bool evidenziatore;

  @override
  void paint(Canvas canvas, Size size) {
    for (final t in tratti) {
      _disegna(canvas, size, t.punti, t.colore, t.spessore, t.evidenziatore);
    }
    if (corrente != null) {
      _disegna(canvas, size, corrente!, colore, spessore, evidenziatore);
    }
    for (final f in firme) {
      final img = f.anteprima;
      if (img == null) continue;
      final larga = f.larghezza * size.width;
      final alta = larga * img.height / img.width;
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(f.posizione.dx * size.width, f.posizione.dy * size.height, larga, alta),
        Paint(),
      );
    }
  }

  void _disegna(Canvas canvas, Size size, List<Offset> punti, Color colore, double spessore, bool evidenziatore) {
    if (punti.length < 2) return;
    final pennello = Paint()
      ..color = evidenziatore ? colore.withValues(alpha: 0.35) : colore
      ..strokeWidth = spessore * size.width * (evidenziatore ? 6 : 1)
      ..strokeCap = evidenziatore ? StrokeCap.square : StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final percorso = Path()..moveTo(punti.first.dx * size.width, punti.first.dy * size.height);
    for (final p in punti.skip(1)) {
      percorso.lineTo(p.dx * size.width, p.dy * size.height);
    }
    canvas.drawPath(percorso, pennello);
  }

  @override
  bool shouldRepaint(covariant _PittoreTratti vecchio) => true;
}

/// Scrive i tratti dentro il PDF (diventano parte della pagina) e salva.
Future<void> applicaTratti(String percorso, List<Tratto> tratti, {List<FirmaDaMettere> firme = const []}) async {
  if (tratti.isEmpty && firme.isEmpty) return;
  final doc = PdfDocument(inputBytes: await File(percorso).readAsBytes());
  try {
    for (final t in tratti) {
      if (t.pagina - 1 >= doc.pages.count) continue;
      final pagina = doc.pages[t.pagina - 1];
      final size = pagina.getClientSize();
      final colore = PdfColor(
        (t.colore.r * 255).round(),
        (t.colore.g * 255).round(),
        (t.colore.b * 255).round(),
      );
      final penna = PdfPen(colore, width: t.spessore * size.width * (t.evidenziatore ? 6 : 1))
        ..lineCap = t.evidenziatore ? PdfLineCap.square : PdfLineCap.round
        ..lineJoin = PdfLineJoin.round;
      if (t.evidenziatore) {
        pagina.graphics.save();
        pagina.graphics.setTransparency(0.35);
      }
      for (var i = 1; i < t.punti.length; i++) {
        final a = t.punti[i - 1];
        final b = t.punti[i];
        pagina.graphics.drawLine(
          penna,
          Offset(a.dx * size.width, a.dy * size.height),
          Offset(b.dx * size.width, b.dy * size.height),
        );
      }
      if (t.evidenziatore) pagina.graphics.restore();
    }
    for (final f in firme) {
      if (f.pagina - 1 >= doc.pages.count) continue;
      final pagina = doc.pages[f.pagina - 1];
      final size = pagina.getClientSize();
      final immagine = PdfBitmap(f.png);
      final larghezza = f.larghezza * size.width;
      final altezza = larghezza * immagine.height / immagine.width;
      pagina.graphics.drawImage(
        immagine,
        Rect.fromLTWH(f.posizione.dx * size.width, f.posizione.dy * size.height, larghezza, altezza),
      );
    }
    await scriviSopra(percorso, await doc.save());
  } finally {
    doc.dispose();
  }
}

/// Firma pronta da appoggiare su una pagina.
class FirmaDaMettere {
  FirmaDaMettere(
      {required this.pagina,
      required this.posizione,
      required this.png,
      this.larghezza = 0.35,
      this.anteprima});

  final int pagina;
  final Offset posizione; // frazione di pagina, angolo in alto a sinistra
  final Uint8List png;
  final double larghezza; // frazione della larghezza pagina
  final ui.Image? anteprima; // serve solo per mostrarla a schermo prima di salvare
}

/// Foglietto per disegnare la firma col dito.
class FoglioFirma extends StatefulWidget {
  const FoglioFirma({super.key});

  @override
  State<FoglioFirma> createState() => _FoglioFirmaState();
}

class _FoglioFirmaState extends State<FoglioFirma> {
  final List<List<Offset>> _tratti = [];
  final GlobalKey _area = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('Firma con il dito', style: TextStyle(fontWeight: FontWeight.w700, color: navy)),
            ),
            Container(
              key: _area,
              height: 220,
              margin: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: grigio300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) => setState(() => _tratti.add([d.localPosition])),
                onPanUpdate: (d) => setState(() => _tratti.last.add(d.localPosition)),
                child: CustomPaint(painter: _PittoreFirma(_tratti), size: Size.infinite),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(_tratti.clear),
                      child: const Text('Cancella'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _tratti.isEmpty ? null : _conferma,
                      child: const Text('Usa firma'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _conferma() async {
    final riquadro = _area.currentContext!.findRenderObject() as RenderBox;
    // Si tiene solo la parte davvero firmata: così sulla pagina la firma ha la misura giusta
    // e non è un francobollo in mezzo a un riquadro vuoto.
    var sinistra = double.infinity, alto = double.infinity, destra = 0.0, basso = 0.0;
    for (final t in _tratti) {
      for (final p in t) {
        sinistra = p.dx < sinistra ? p.dx : sinistra;
        alto = p.dy < alto ? p.dy : alto;
        destra = p.dx > destra ? p.dx : destra;
        basso = p.dy > basso ? p.dy : basso;
      }
    }
    if (sinistra > destra || alto > basso) return;
    const margine = 10.0;
    final area = Rect.fromLTRB(sinistra - margine, alto - margine, destra + margine, basso + margine)
        .intersect(Offset.zero & riquadro.size);
    const scala = 3.0; // la firma entra nel PDF come immagine: serve densità
    final registratore = ui.PictureRecorder();
    final canvas = Canvas(registratore);
    canvas.scale(scala);
    canvas.translate(-area.left, -area.top);
    _PittoreFirma(_tratti).paint(canvas, riquadro.size);
    final immagine = await registratore
        .endRecording()
        .toImage((area.width * scala).round(), (area.height * scala).round());
    final dati = await immagine.toByteData(format: ui.ImageByteFormat.png);
    immagine.dispose();
    if (!mounted) return;
    Navigator.of(context).pop(dati!.buffer.asUint8List());
  }
}

class _PittoreFirma extends CustomPainter {
  _PittoreFirma(this.tratti);
  final List<List<Offset>> tratti;

  @override
  void paint(Canvas canvas, Size size) {
    final scala = size.width > 0 ? 1.0 : 1.0;
    final penna = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeWidth = 3 * scala
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final t in tratti) {
      if (t.length < 2) continue;
      final percorso = Path()..moveTo(t.first.dx, t.first.dy);
      for (final p in t.skip(1)) {
        percorso.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(percorso, penna);
    }
  }

  @override
  bool shouldRepaint(covariant _PittoreFirma vecchio) => true;
}
