// Ritaglio delle foto prima del PDF: per ogni foto propone i bordi della pagina trovati da soli
// (bordi.dart) e si correggono trascinando i quattro angoli, con la lente sotto il dito.
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'bordi.dart';
import 'tema.dart';

/// Apre il ritaglio sulle foto. Restituisce gli angoli scelti per ogni foto (null = cercali da sé)
/// oppure null se si esce senza confermare.
Future<List<List<Punto>?>?> ritagliaFoto(BuildContext context, List<String> foto) =>
    Navigator.of(context).push<List<List<Punto>?>>(
      MaterialPageRoute(builder: (_) => SchermataRitaglio(foto: foto)),
    );

/// Ritaglia e raddrizza le foto con gli angoli scelti. Una foto che non si riesce a leggere
/// (formato strano) entra nel PDF così com'è, invece di far fallire tutto.
Future<List<String>> applicaRitagli(List<String> foto, List<List<Punto>?> angoli) async {
  final cartella = (await getTemporaryDirectory()).path;
  final pronte = <String>[];
  for (var i = 0; i < foto.length; i++) {
    try {
      pronte.add(await applicaRitaglio(foto[i], angoli[i], cartella, i));
    } catch (_) {
      pronte.add(foto[i]);
    }
  }
  return pronte;
}

class SchermataRitaglio extends StatefulWidget {
  const SchermataRitaglio({super.key, required this.foto, this.prepara = preparaFoto});

  final List<String> foto;

  /// Chi legge la foto e cerca i bordi (il banco di prova ne passa uno finto).
  final Future<FotoPronta> Function(String percorso) prepara;

  @override
  State<SchermataRitaglio> createState() => _SchermataRitaglioState();
}

class _SchermataRitaglioState extends State<SchermataRitaglio> {
  final Map<int, FotoPronta> _pronte = {};
  final Map<int, Object> _errori = {};
  final Set<int> _avviate = {};
  late final List<List<Punto>?> _scelte = List.filled(widget.foto.length, null);
  var _indice = 0;
  List<Punto>? _angoli;

  int get _totale => widget.foto.length;
  bool get _ultima => _indice == _totale - 1;

  @override
  void initState() {
    super.initState();
    _mostra(0);
  }

  /// Prepara la foto [i] (e già la successiva, così non si aspetta tra una e l'altra).
  void _mostra(int i) {
    _indice = i;
    _angoli = _scelte[i] ?? _pronte[i]?.bordi ?? (_pronte.containsKey(i) ? angoliTuttaFoto : null);
    for (final j in [i, i + 1]) {
      if (j >= _totale || !_avviate.add(j)) continue;
      widget.prepara(widget.foto[j]).then((pronta) {
        if (!mounted) return;
        setState(() {
          _pronte[j] = pronta;
          if (j == _indice && _angoli == null) _angoli = pronta.bordi ?? angoliTuttaFoto;
        });
      }, onError: (Object errore) {
        if (mounted) setState(() => _errori[j] = errore);
      });
    }
  }

  void _avanti() {
    if (_errori.containsKey(_indice)) {
      _scelte[_indice] = angoliTuttaFoto; // non si legge: entra così com'è
    } else {
      final angoli = _angoli;
      if (angoli == null) return;
      if (!_convesso(angoli)) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gli angoli si incrociano: rimettili ai quattro angoli della pagina.')));
        return;
      }
      _scelte[_indice] = angoli;
    }
    if (_ultima) {
      Navigator.of(context).pop(_scelte);
    } else {
      setState(() => _mostra(_indice + 1));
    }
  }

  /// Conferma questa foto e lascia alle restanti i bordi trovati da soli.
  void _automaticoPerLeRestanti() {
    final angoli = _angoli;
    if (angoli != null && _convesso(angoli)) _scelte[_indice] = angoli;
    Navigator.of(context).pop(_scelte);
  }

  Future<void> _indietro() async {
    if (_indice > 0) {
      setState(() => _mostra(_indice - 1));
      return;
    }
    final esci = await showDialog<bool>(
      context: context,
      builder: (contesto) => AlertDialog(
        title: const Text('Uscire senza creare il PDF?'),
        content: const Text('Le foto non vengono salvate.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(contesto, false), child: const Text('Resta')),
          TextButton(onPressed: () => Navigator.pop(contesto, true), child: const Text('Esci')),
        ],
      ),
    );
    if (esci == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final pronta = _pronte[_indice];
    final errore = _errori[_indice];
    final angoli = _angoli;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (fatto, _) {
        if (!fatto) _indietro();
      },
      child: Scaffold(
        backgroundColor: navy,
        body: Column(
          children: [
            Testata(
              sottotitolo: _totale == 1 ? 'Ritaglia la pagina' : 'Ritaglia la pagina · foto ${_indice + 1} di $_totale',
              indietro: _indietro,
            ),
            Expanded(
              child: errore != null
                  ? const _Messaggio(
                      icona: Icons.image_not_supported_outlined,
                      testo: 'Questa foto non si può ritagliare: la metto nel PDF così com\'è.')
                  : pronta == null || angoli == null
                      ? const _Messaggio(testo: 'Cerco i bordi della pagina…', attesa: true)
                      : _EditorAngoli(
                          key: ValueKey(_indice),
                          foto: pronta,
                          angoli: angoli,
                          onCambio: (nuovi) => setState(() => _angoli = nuovi),
                        ),
            ),
            _barraComandi(pronta, errore),
          ],
        ),
      ),
    );
  }

  Widget _barraComandi(FotoPronta? pronta, Object? errore) {
    final pronto = errore != null || (pronta != null && _angoli != null);
    final restanti = _totale - _indice - 1;
    final suggerimento = errore != null
        ? ''
        : pronta == null
            ? ' '
            : pronta.bordi == null
                ? 'Bordi non trovati: trascina gli angoli sulla pagina.'
                : 'Trascina gli angoli per correggere il ritaglio.';
    return Container(
      color: navy2,
      padding: EdgeInsets.fromLTRB(14, 10, 14, 12 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (suggerimento.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(suggerimento, style: const TextStyle(color: grigio300, fontSize: 13)),
            ),
          if (errore == null)
            Row(
              children: [
                Expanded(
                  child: _BottoneScuro(
                    icona: Icons.crop_free,
                    testo: 'Tutta la foto',
                    onTap: pronta == null ? null : () => setState(() => _angoli = angoliTuttaFoto),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _BottoneScuro(
                    icona: Icons.auto_fix_high,
                    testo: 'Automatico',
                    onTap: pronta?.bordi == null ? null : () => setState(() => _angoli = pronta!.bordi),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: pronto ? _avanti : null,
            icon: Icon(_ultima ? Icons.picture_as_pdf : Icons.arrow_forward),
            label: Text(_ultima ? 'Crea il PDF' : 'Avanti'),
          ),
          if (restanti > 0)
            TextButton(
              onPressed: pronto ? _automaticoPerLeRestanti : null,
              style: TextButton.styleFrom(foregroundColor: grigio300),
              child: Text(restanti == 1
                  ? 'Crea il PDF, l\'ultima foto la ritaglio da solo'
                  : 'Crea il PDF, le altre $restanti foto le ritaglio da solo'),
            ),
        ],
      ),
    );
  }
}

/// Vero se il quadrilatero non si incrocia (tutti i giri nello stesso verso).
bool _convesso(List<Punto> q) {
  var segno = 0;
  for (var i = 0; i < 4; i++) {
    final a = q[i], b = q[(i + 1) % 4], c = q[(i + 2) % 4];
    final giro = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
    final s = giro > 0 ? 1 : (giro < 0 ? -1 : 0);
    if (s == 0) continue;
    if (segno == 0) segno = s;
    if (s != segno) return false;
  }
  return segno != 0;
}

class _Messaggio extends StatelessWidget {
  const _Messaggio({required this.testo, this.icona, this.attesa = false});

  final String testo;
  final IconData? icona;
  final bool attesa;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (attesa)
              const CircularProgressIndicator(color: accento)
            else if (icona != null)
              Icon(icona, color: grigio300, size: 44),
            const SizedBox(height: 16),
            Text(testo, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _BottoneScuro extends StatelessWidget {
  const _BottoneScuro({required this.icona, required this.testo, this.onTap});

  final IconData icona;
  final String testo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: navy3,
        disabledForegroundColor: grigio500,
        disabledBackgroundColor: navy3.withValues(alpha: 0.5),
        minimumSize: const Size.fromHeight(44),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      icon: Icon(icona, size: 19),
      label: Text(testo, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// La foto con il riquadro da correggere: si prende l'angolo più vicino al dito.
class _EditorAngoli extends StatefulWidget {
  const _EditorAngoli({super.key, required this.foto, required this.angoli, required this.onCambio});

  final FotoPronta foto;
  final List<Punto> angoli;
  final ValueChanged<List<Punto>> onCambio;

  @override
  State<_EditorAngoli> createState() => _EditorAngoliState();
}

class _EditorAngoliState extends State<_EditorAngoli> {
  int? _preso;
  Offset? _dito;

  static const _margine = 26.0;
  static const _distanzaPresa = 56.0;
  static const _lente = 110.0;

  Rect _area(Size spazio) {
    final disponibile = Rect.fromLTWH(_margine, _margine, spazio.width - 2 * _margine, spazio.height - 2 * _margine);
    final rapporto = widget.foto.larghezza / widget.foto.altezza;
    var w = disponibile.width, h = w / rapporto;
    if (h > disponibile.height) {
      h = disponibile.height;
      w = h * rapporto;
    }
    return Rect.fromCenter(center: disponibile.center, width: w, height: h);
  }

  Offset _aSchermo(Punto p, Rect area) => Offset(area.left + p.x * area.width, area.top + p.y * area.height);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, vincoli) {
      final spazio = vincoli.biggest;
      final area = _area(spazio);
      final dito = _dito;
      // la lente sta sopra il dito (sotto lo coprirebbe); vicino al bordo alto va sotto
      final lenteSopra = dito == null || dito.dy > _lente + 40;
      final spostamento = Offset(0, lenteSopra ? -(_lente / 2 + 44) : _lente / 2 + 44);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) {
          var migliore = -1;
          var distanza = _distanzaPresa;
          for (var i = 0; i < 4; i++) {
            final dd = (_aSchermo(widget.angoli[i], area) - d.localPosition).distance;
            if (dd < distanza) {
              distanza = dd;
              migliore = i;
            }
          }
          if (migliore < 0) return;
          setState(() {
            _preso = migliore;
            _dito = _aSchermo(widget.angoli[migliore], area);
          });
        },
        onPanUpdate: (d) {
          final preso = _preso;
          if (preso == null) return;
          final punto = _aSchermo(widget.angoli[preso], area) + d.delta;
          final nuovo = Punto(
            ((punto.dx - area.left) / area.width).clamp(0.0, 1.0),
            ((punto.dy - area.top) / area.height).clamp(0.0, 1.0),
          );
          final angoli = [...widget.angoli]..[preso] = nuovo;
          setState(() => _dito = _aSchermo(nuovo, area));
          widget.onCambio(angoli);
        },
        onPanEnd: (_) => setState(() {
          _preso = null;
          _dito = null;
        }),
        child: Stack(
          children: [
            Positioned.fromRect(
              rect: area,
              child: Image.memory(widget.foto.anteprima, fit: BoxFit.fill, gaplessPlayback: true),
            ),
            Positioned.fill(
              child: CustomPaint(painter: _PittoreRitaglio(widget.angoli, area, _preso)),
            ),
            if (dito != null)
              Positioned(
                left: dito.dx - _lente / 2 + spostamento.dx,
                top: dito.dy - _lente / 2 + spostamento.dy,
                child: RawMagnifier(
                  size: const Size(_lente, _lente),
                  magnificationScale: 2.2,
                  focalPointOffset: -spostamento,
                  decoration: const MagnifierDecoration(
                    shape: CircleBorder(side: BorderSide(color: Colors.white, width: 3)),
                    shadows: [BoxShadow(color: Colors.black54, blurRadius: 10)],
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _PittoreRitaglio extends CustomPainter {
  _PittoreRitaglio(this.angoli, this.area, this.preso);

  final List<Punto> angoli;
  final Rect area;
  final int? preso;

  @override
  void paint(Canvas canvas, Size size) {
    final punti = [for (final a in angoli) Offset(area.left + a.x * area.width, area.top + a.y * area.height)];
    final riquadro = Path()..addPolygon(punti, true);
    // fuori dal ritaglio la foto si scurisce: si vede subito cosa resta
    final fuori = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(area)
      ..addPolygon(punti, true);
    canvas.drawPath(fuori, Paint()..color = Colors.black.withValues(alpha: 0.6));
    canvas.drawPath(
      riquadro,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = accento,
    );
    final bordo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..color = accento;
    for (var i = 0; i < 4; i++) {
      if (i == preso) {
        // mentre lo si trascina l'angolo è un anello vuoto con il mirino: nella lente si vede il punto vero
        canvas.drawCircle(punti[i], 16, bordo);
        final mirino = Paint()
          ..strokeWidth = 1.5
          ..color = Colors.white;
        canvas.drawLine(punti[i] - const Offset(9, 0), punti[i] + const Offset(9, 0), mirino);
        canvas.drawLine(punti[i] - const Offset(0, 9), punti[i] + const Offset(0, 9), mirino);
      } else {
        canvas.drawCircle(punti[i], 11, Paint()..color = Colors.white);
        canvas.drawCircle(punti[i], 11, bordo);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PittoreRitaglio vecchio) =>
      vecchio.angoli != angoli || vecchio.area != area || vecchio.preso != preso;
}
