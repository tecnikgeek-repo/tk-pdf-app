// Banco di prova (non fa parte dell'app): apre un PDF finto nel visualizzatore e ci mette sopra
// i riquadri della modifica testo, per controllare che finiscano davvero sulle righe e che il
// tocco arrivi. Serve perché il visualizzatore non si può provare nei test normali.
//
// Uso:  flutter build web -t lib/banco_prova.dart  +  python tools/anteprima.py prova
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: _Banco()));
}

class _Riga {
  _Riga(this.testo, this.riquadro);
  final String testo;
  final Rect riquadro;
}

class _Banco extends StatefulWidget {
  const _Banco();

  @override
  State<_Banco> createState() => _BancoState();
}

class _BancoState extends State<_Banco> {
  Uint8List? _pdf;
  List<_Riga> _righe = const [];
  String _stato = 'preparo…';

  @override
  void initState() {
    super.initState();
    _prepara();
  }

  Future<void> _prepara() async {
    final doc = sf.PdfDocument();
    final pagina = doc.pages.add();
    final font = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 14);
    final grande = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 22, style: sf.PdfFontStyle.bold);
    pagina.graphics.drawString('Fattura di prova', grande, bounds: const Rect.fromLTWH(40, 40, 400, 30));
    const voci = [
      'Cliente: Mario Rossi',
      'Importo totale: 1.250,00 euro',
      'Scadenza: 30/10/2026',
      'Nota: riga in fondo alla pagina',
    ];
    for (var i = 0; i < voci.length; i++) {
      final y = i == voci.length - 1 ? 700.0 : 120.0 + i * 40;
      pagina.graphics.drawString(voci[i], font, bounds: Rect.fromLTWH(40, y, 450, 20));
    }
    final byte = Uint8List.fromList(await doc.save());
    doc.dispose();

    final riletto = sf.PdfDocument(inputBytes: byte);
    final righe = sf.PdfTextExtractor(riletto)
        .extractTextLines(startPageIndex: 0, endPageIndex: 0)
        .where((r) => r.text.trim().isNotEmpty)
        .map((r) => _Riga(r.text, r.bounds))
        .toList();
    riletto.dispose();
    setState(() {
      _pdf = byte;
      _righe = righe;
      _stato = 'righe: ${righe.length}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final pdf = _pdf;
    return Scaffold(
      appBar: AppBar(title: Text(_stato, style: const TextStyle(fontSize: 13))),
      body: pdf == null
          ? const Center(child: CircularProgressIndicator())
          : PdfViewer.data(
              pdf,
              sourceName: 'prova',
              params: PdfViewerParams(
                margin: 10,
                pageOverlaysBuilder: (context, riquadroPagina, pagina) => [
                  Positioned.fill(child: _livello(Size(riquadroPagina.width, riquadroPagina.height))),
                ],
              ),
            ),
    );
  }

  Widget _livello(Size dimensione) {
    const misura = Size(595, 842); // A4 in punti, come la pagina generata
    return Stack(
      children: [
        for (final riga in _righe)
          Positioned(
            left: riga.riquadro.left / misura.width * dimensione.width,
            top: riga.riquadro.top / misura.height * dimensione.height,
            width: riga.riquadro.width / misura.width * dimensione.width,
            height: riga.riquadro.height / misura.height * dimensione.height,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _stato = 'toccata: ${riga.testo}'),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0x59FFE4E6),
                  border: Border.all(color: const Color(0xFFE11D48), width: 0.8),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
