// Colori e pezzi propri di tk-pdf (schede, riga strumenti); tutto il resto è nel kit comune delle app TK.
import 'package:flutter/material.dart';

import 'kit_tk.dart';

export 'kit_tk.dart';

const accento = Color(0xFFE11D48);
const accentoScuro = Color(0xFFBE123C);
const accentoChiaro = Color(0xFFFFE4E6);

/// Simbolo di tk-pdf: foglio bianco con l'angolo piegato e le righe di testo.
Widget simboloPdf(double lato) => CustomPaint(size: Size.square(lato * .56), painter: _FoglioBianco());

const configPdf = ConfigTk(
  nome: 'tk-pdf',
  motto: 'PDF in tasca',
  descrizione: 'Lettore ed editor PDF',
  accento: accento,
  accentoScuro: accentoScuro,
  simbolo: simboloPdf,
  manifestUrl:
      'https://dl.dropboxusercontent.com/scl/fi/14qyarkq4ehn8v5j3e398/tkpdf-version.json?rlkey=5r263eh8dxw0mhcircfhk0y06',
  altrove: ("C'è anche per Windows e Mac", 'https://pietrodefilippis.it/software/'),
  logoOriginale: logoOriginale,
  avvioColorato: true,
  eccezioneLicenza: 'Syncfusion Flutter PDF, Google ML Kit',
);

/// Icona vera dell'app (lo stesso file da cui nasce l'icona del telefono): testata, benvenuto, splash, Informazioni.
Widget logoOriginale(double lato) =>
    Image.asset('assets/icona.png', width: lato, height: lato, filterQuality: FilterQuality.high);


/// Le cinque schede del documento.
const schedeTk = <(IconData, String)>[
  (Icons.visibility_outlined, 'Visualizza'),
  (Icons.draw_outlined, 'Annota'),
  (Icons.history_edu_outlined, 'Firma e moduli'),
  (Icons.edit_note, 'Modifica testo'),
  (Icons.auto_awesome_motion_outlined, 'Pagine'),
];

/// Schede in una fascia scura sotto la testata: la scelta diventa una pillola d'accento.
/// Tutte sempre in vista (niente scorrimento), si dividono la larghezza.
class BarraSchede extends StatelessWidget {
  const BarraSchede({super.key, required this.voci, required this.scelta, required this.onScelta, this.attive = true});

  final List<(IconData, String)> voci;
  final int scelta;
  final ValueChanged<int> onScelta;
  final bool attive;

  @override
  Widget build(BuildContext context) => Container(
        color: navy2,
        padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
        child: SizedBox(
          height: 54,
          child: Row(children: [
            for (var i = 0; i < voci.length; i++)
              Expanded(
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: _scheda(i)),
              ),
          ]),
        ),
      );

  Widget _scheda(int i) {
    final attiva = attive && i == scelta;
    final colore = attiva ? bianco : (attive ? grigio300 : grigio500);
    return Material(
      color: attiva ? accento : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: attive ? () => onScelta(i) : null,
        borderRadius: BorderRadius.circular(12),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(voci[i].$1, size: 20, color: colore),
          const SizedBox(height: 2),
          Text(
            voci[i].$2,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 10, height: 1.05, color: colore),
          ),
        ]),
      ),
    );
  }
}

/// Riga degli strumenti bianca sotto le schede.
class RigaStrumenti extends StatelessWidget {
  const RigaStrumenti({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          SizedBox(
            height: 50,
            // sfumatura a destra: fa capire che la riga scorre quando i pulsanti non ci stanno
            child: ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Colors.white, Colors.white, Colors.transparent],
                stops: [0, 0.93, 1],
              ).createShader(rect),
              blendMode: BlendMode.dstIn,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
                children: children,
              ),
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

/// Pulsante della riga strumenti: pillola grigia, d'accento quando è attivo.
class BottoneStrumento extends StatelessWidget {
  const BottoneStrumento({
    super.key,
    required this.testo,
    required this.onTap,
    this.icona,
    this.attivo = false,
    this.abilitato = true,
  });

  final String testo;
  final IconData? icona;
  final VoidCallback onTap;
  final bool attivo;
  final bool abilitato;

  @override
  Widget build(BuildContext context) {
    final colore = attivo ? accentoScuro : (abilitato ? navy : grigio300);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: attivo ? accentoChiaro : grigio100,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: abilitato ? onTap : null,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: attivo ? accento : Colors.transparent),
            ),
            child: Row(
              children: [
                if (icona != null) ...[
                  Icon(icona, size: 16, color: colore),
                  const SizedBox(width: 5),
                ],
                Text(testo,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colore)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FoglioBianco extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 56;  // disegno pensato su 56
    final foglio = Path()
      ..moveTo(10 * s, 4 * s)
      ..lineTo(34 * s, 4 * s)
      ..lineTo(46 * s, 16 * s)
      ..lineTo(46 * s, 52 * s)
      ..lineTo(10 * s, 52 * s)
      ..close();
    canvas.drawPath(foglio, Paint()..color = Colors.white);
    final piega = Path()
      ..moveTo(34 * s, 4 * s)
      ..lineTo(34 * s, 16 * s)
      ..lineTo(46 * s, 16 * s)
      ..close();
    canvas.drawPath(piega, Paint()..color = const Color(0xFFFFC9D2));
    final riga = Paint()..color = accentoChiaro;
    for (var i = 0; i < 3; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(17 * s, (24 + i * 8) * s, (22 - i * 4) * s, 3.4 * s), Radius.circular(2 * s)),
        riga,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
