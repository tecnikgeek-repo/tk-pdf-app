// Rifare una foto in mezzo alle altre, percentuale di avanzamento e PDF creato fuori dal filo dello schermo.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:tkpdf/avanzamento.dart';
import 'package:tkpdf/bordi.dart';
import 'package:tkpdf/documenti.dart' as doc;
import 'package:tkpdf/ritaglio.dart';
import 'package:tkpdf/tema.dart';

import 'caratteri.dart';

final _jpg = img.encodeJpg(img.Image(width: 60, height: 80));

class _CartellaFinta extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  _CartellaFinta(this.percorso);
  final String percorso;
  @override
  Future<String?> getApplicationDocumentsPath() async => percorso;
}

void main() {
  setUpAll(caricaCaratteri);

  testWidgets('Rifai sostituisce solo la foto in vista, anche in mezzo alle altre', (t) async {
    configTk = configPdf;
    t.view.physicalSize = const Size(412, 915) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final lette = <String>[];
    FotoRitagliate? esito;
    await t.pumpWidget(MaterialApp(
      theme: temaKit(),
      home: Builder(
        builder: (context) => TextButton(
          child: const Text('apri'),
          onPressed: () async {
            esito = await Navigator.of(context).push<FotoRitagliate>(MaterialPageRoute(
              builder: (_) => SchermataRitaglio(
                foto: const ['a', 'b', 'c'],
                prepara: (p) async {
                  lette.add(p);
                  return FotoPronta(_jpg, angoliTuttaFoto, 60, 80);
                },
                rifai: () async => 'b-nuova',
              ),
            ));
          },
        ),
      ),
    ));
    await t.tap(find.text('apri'));
    await t.pumpAndSettle();

    // tocco la seconda foto nella striscia e la rifaccio
    await t.tap(find.text('2'));
    await t.pumpAndSettle();
    expect(find.textContaining('foto 2 di 3'), findsOneWidget);
    await t.tap(find.text('Rifai questa foto'));
    await t.pumpAndSettle();
    expect(lette, contains('b-nuova'));
    expect(find.textContaining('foto 2 di 3'), findsOneWidget);

    await t.tap(find.text('Avanti'));
    await t.pumpAndSettle();
    await t.tap(find.text('Crea il PDF'));
    await t.pumpAndSettle();
    expect(esito!.foto, ['a', 'b-nuova', 'c']);
    expect(esito!.angoli, hasLength(3));
  });

  test('il PDF si crea fuori dal filo dello schermo e racconta le pagine fatte', () async {
    final cartella = Directory.systemTemp.createTempSync('tkpdf-avanzamento');
    addTearDown(() => cartella.deleteSync(recursive: true));
    PathProviderPlatform.instance = _CartellaFinta(cartella.path);
    final foto = <String>[];
    for (var i = 0; i < 3; i++) {
      final f = File('${cartella.path}/f$i.jpg')..writeAsBytesSync(_jpg);
      foto.add(f.path);
    }
    final passi = <String>[];
    final percorso = await doc.pdfDaImmagini(foto, nome: 'Prova', avanzamento: (f, tot) => passi.add('$f/$tot'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(passi, ['1/3', '2/3', '3/3']);
    final letto = PdfDocument(inputBytes: File(percorso).readAsBytesSync());
    expect(letto.pages.count, 3);
    letto.dispose();

    final passiUnione = <String>[];
    final uniti = await doc.unisci([percorso, percorso], avanzamento: (f, tot) => passiUnione.add('$f/$tot'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(passiUnione, ['1/2', '2/2']);
    final letti = PdfDocument(inputBytes: File(uniti).readAsBytesSync());
    expect(letti.pages.count, 6);
    letti.dispose();
  });

  testWidgets('la finestra mostra la percentuale, che non torna indietro, e si chiude da sola', (t) async {
    late Avanzamento a;
    final fine = Completer<void>();
    await t.pumpWidget(MaterialApp(
      theme: temaKit(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            child: const Text('via'),
            onPressed: () => conAvanzamento<void>(context, 'Creo il PDF', (av) async {
              a = av;
              await fine.future;
            }),
          ),
        ),
      ),
    ));
    await t.tap(find.text('via'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Creo il PDF'), findsOneWidget);
    a.segna(0.42, 'Pagina 3 di 7');
    await t.pump();
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('Pagina 3 di 7'), findsOneWidget);
    a.segna(0.1, 'in ritardo');
    await t.pump();
    expect(find.text('42%'), findsOneWidget);
    fine.complete();
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Creo il PDF'), findsNothing);
  });
}
