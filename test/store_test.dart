// Schermate per la scheda del Play Store (1080×1920, 9:16) con PDF di esempio veri: home coi recenti, lettura,
// annotazioni, gestione pagine. Il lettore usa pdfium: qui lo scarica pdfrxInitialize() (serve la rete la prima
// volta). Finiscono in build/store/. Gira solo con `flutter test --dart-define=STORE=true test/store_test.dart`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:tkpdf/home.dart';
import 'package:tkpdf/pagine.dart';
import 'package:tkpdf/tema.dart';
import 'package:tkpdf/visualizza.dart';

import 'caratteri.dart';

const _store = bool.fromEnvironment('STORE');

/// Un PDF di esempio: intestazione, paragrafi e una tabella con i totali.
String _esempio(String nome, String titolo, int pagine) {
  final doc = sf.PdfDocument();
  // Arial di Windows: i caratteri standard del PDF non hanno il simbolo dell'euro
  final normale = File(r'C:\Windows\Fonts/arial.ttf').readAsBytesSync();
  final neretto = File(r'C:\Windows\Fonts/arialbd.ttf').readAsBytesSync();
  final titoloF = sf.PdfTrueTypeFont(neretto, 22);
  final testoF = sf.PdfTrueTypeFont(normale, 11);
  final grassetto = sf.PdfTrueTypeFont(neretto, 11);
  for (var p = 0; p < pagine; p++) {
    final pg = doc.pages.add();
    final g = pg.graphics;
    final w = pg.getClientSize().width;
    g.drawRectangle(brush: sf.PdfSolidBrush(sf.PdfColor(13, 27, 62)), bounds: ui.Rect.fromLTWH(0, 0, w, 60));
    g.drawString(titolo, titoloF, brush: sf.PdfBrushes.white, bounds: ui.Rect.fromLTWH(16, 16, w - 32, 30));
    g.drawString('Pagina ${p + 1} di $pagine', testoF, bounds: ui.Rect.fromLTWH(0, 70, w, 16));
    var y = 100.0;
    for (final par in [
      'Gentile cliente, di seguito trova il riepilogo dei servizi concordati e le condizioni di fornitura. '
          'I prezzi sono espressi in euro e si intendono IVA esclusa, salvo diversa indicazione.',
      'Il lavoro comprende sopralluogo, progettazione, realizzazione e assistenza per dodici mesi dalla consegna. '
          'Eventuali richieste aggiuntive saranno quotate a parte prima di procedere.',
    ]) {
      final r = sf.PdfTextElement(text: par, font: testoF)
          .draw(page: pg, bounds: ui.Rect.fromLTWH(0, y, w, 200))!;
      y = r.bounds.bottom + 14;
    }
    final griglia = sf.PdfGrid()..columns.add(count: 3);
    griglia.headers.add(1);
    final h = griglia.headers[0];
    h.cells[0].value = 'Descrizione';
    h.cells[1].value = 'Quantità';
    h.cells[2].value = 'Importo';
    h.style = sf.PdfGridRowStyle(backgroundBrush: sf.PdfSolidBrush(sf.PdfColor(232, 236, 244)), font: grassetto);
    for (final (d, q, i) in [
      ('Progetto grafico', '1', '€ 450,00'),
      ('Sito web con negozio', '1', '€ 1.200,00'),
      ('Foto prodotto', '30', '€ 300,00'),
      ('Assistenza annuale', '12', '€ 240,00'),
    ]) {
      final r = griglia.rows.add();
      r.cells[0].value = d;
      r.cells[1].value = q;
      r.cells[2].value = i;
    }
    griglia.style = sf.PdfGridStyle(font: testoF, cellPadding: sf.PdfPaddings(left: 6, right: 6, top: 6, bottom: 6));
    final fine = griglia.draw(page: pg, bounds: ui.Rect.fromLTWH(0, y, w, 0))!;
    g.drawString('Totale  € 2.190,00', titoloF, bounds: ui.Rect.fromLTWH(w - 240, fine.bounds.bottom + 20, 240, 30));
    g.drawString('Firma per accettazione', testoF, bounds: ui.Rect.fromLTWH(0, fine.bounds.bottom + 90, 200, 16));
    g.drawLine(sf.PdfPen(sf.PdfColor(120, 120, 120)), ui.Offset(0, fine.bounds.bottom + 130), ui.Offset(220, fine.bounds.bottom + 130));
  }
  final f = File('${Directory.systemTemp.path}/$nome.pdf')..writeAsBytesSync(doc.saveSync());
  doc.dispose();
  return f.path;
}

Future<void> _aspetta(WidgetTester t, [int giri = 16]) async {
  for (var i = 0; i < giri; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

final _k = GlobalKey();

/// Il tema dell'app con «Roboto» esplicito nei pulsanti: sul telefono è già il carattere di sistema, nei test
/// senza nome di carattere Flutter disegna quadratini.
ThemeData _tema() {
  final t = temaKit();
  const roboto = WidgetStatePropertyAll(TextStyle(fontFamily: 'Roboto', fontSize: 15, fontWeight: FontWeight.w700));
  ButtonStyle? con(ButtonStyle? s) => (s ?? const ButtonStyle()).copyWith(textStyle: roboto);
  return t.copyWith(
    filledButtonTheme: FilledButtonThemeData(style: con(t.filledButtonTheme.style)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: con(t.outlinedButtonTheme.style)),
    elevatedButtonTheme: ElevatedButtonThemeData(style: con(t.elevatedButtonTheme.style)),
    textButtonTheme: TextButtonThemeData(style: con(t.textButtonTheme.style)),
  );
}

Future<void> _mostra(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(1080, 1920);
  t.view.devicePixelRatio = 3;
  await t.pumpWidget(RepaintBoundary(
    key: _k,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _tema(),
      locale: const Locale('it'),
      supportedLocales: const [Locale('it')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: w,
    ),
  ));
  await _aspetta(t);
}

Future<void> _foto(WidgetTester t, String nome) async {
  await _aspetta(t, 8);
  await t.runAsync(() async {
    final img = await (_k.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 3);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/store').createSync(recursive: true);
    File('build/store/$nome.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('schermate per il Play Store', skip: !_store, (t) async {
    configTk = configPdf;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (_) async => Directory.systemTemp.path);
    late String preventivo, contratto, verbale;
    await t.runAsync(() async {
      await caricaCaratteri();
      // i pulsanti del tema non dicono il carattere: sul telefono è quello di sistema (Roboto), nei test sarebbe
      // il carattere finto a quadratini. Roboto anche come carattere predefinito dei test.
      final dir = '${Platform.environment['FLUTTER_ROOT'] ?? r'C:\dev/flutter'}/bin/cache/artifacts/material_fonts';
      final predefinito = FontLoader('FlutterTest');
      for (final n in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf']) {
        for (final f in [File('$dir/$n'), File('$dir/${n[0].toUpperCase()}${n.substring(1).replaceFirst('-r', '-R').replaceFirst('-m', '-M').replaceFirst('-b', '-B')}')]) {
          if (f.existsSync()) {
            predefinito.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
            break;
          }
        }
      }
      await predefinito.load();
      await pdfrxInitialize(tmpPath: '${Directory.systemTemp.path}/tkpdf-pdfium');
      preventivo = _esempio('Preventivo sito web', 'Preventivo n. 42/2026', 1);
      contratto = _esempio('Contratto di servizio', 'Contratto di servizio', 4);
      verbale = _esempio('Verbale riunione', 'Verbale della riunione', 2);
    });
    SharedPreferences.setMockInitialValues({'recenti': [preventivo, contratto, verbale]});

    await _mostra(t, const SchermataHome());
    await _foto(t, '1-home');

    await _mostra(t, SchermataVisualizza(percorso: preventivo));
    await _foto(t, '2-lettura');

    // Annota: penna attiva e due tratti sulla tabella e sul totale
    await t.tap(find.text('Annota').first);
    await t.pump();
    final area = t.getRect(find.byType(PdfViewer));
    for (final (da, a) in [
      (area.topLeft + Offset(area.width * .62, area.height * .47), area.topLeft + Offset(area.width * .92, area.height * .47)),
      (area.topLeft + Offset(area.width * .55, area.height * .55), area.topLeft + Offset(area.width * .95, area.height * .55)),
    ]) {
      final dito = await t.startGesture(da);
      for (var i = 1; i <= 12; i++) {
        await dito.moveTo(Offset.lerp(da, a, i / 12)! + Offset(0, (i % 2) * 3.0));
        await t.pump(const Duration(milliseconds: 16));
      }
      await dito.up();
      await t.pump();
    }
    await _foto(t, '3-annota');

    await _mostra(t, SchermataPagine(percorso: contratto));
    await _foto(t, '4-pagine');
    await t.pumpWidget(const SizedBox());
  });
}
