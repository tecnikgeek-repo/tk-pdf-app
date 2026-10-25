// Foto di Benvenuto, Informazioni e Licenze su un telefono 412×915 con i caratteri veri, per guardarle senza
// telefono. Gira solo con `flutter test --update-goldens test/schermate_golden_test.dart` (in CI sul ramo):
// le PNG finiscono in test/goldens/ e la CI le carica come artefatto. Con `flutter test` normale si salta.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tkpdf/tema.dart';
import 'package:tkpdf/tk_licenza.dart';
import 'package:tkpdf/tk_pro.dart';

import 'caratteri.dart';

const _telefono = Size(412, 915);

Future<void> _mostra(WidgetTester t, Widget schermata, {Size lato = _telefono}) async {
  t.view.physicalSize = lato * 2;
  t.view.devicePixelRatio = 2;
  await t.pumpWidget(MaterialApp(
      key: UniqueKey(),
      debugShowCheckedModeBanner: false,
      theme: temaKit(),
      home: schermata));
  await t.pump(const Duration(milliseconds: 300));
  // l'icona vera (asset) si decodifica solo fuori dal tempo finto del test
  await t.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(caricaCaratteri);

  testWidgets('foto delle schermate', skip: !autoUpdateGoldenFiles, (t) async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'tk-pdf',
        packageName: 'it.pietrodefilippis.tkpdf',
        version: '1.7.0',
        buildNumber: '17',
        buildSignature: '');
    configTk = configPdf;
    final lic = Licenza(slug: 'tk-pdf-app', versione: '1.7.0');
    await t.runAsync(lic.carica);
    proTk = ProTk(lic);
    addTearDown(t.view.reset);

    await _mostra(t, SchermataBenvenuto(lic: lic));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/benvenuto.png'));

    // con l'interruttore acceso
    await t.tap(find.byType(Switch));
    await t.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/benvenuto-statistiche.png'));

    Future<List<(String, String)>> righe() async => [('Documenti recenti', '3')];
    await _mostra(t, SchermataInformazioni(righe: righe));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/informazioni.png'));

    await t.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await t.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/informazioni-fondo.png'));

    // tutta la pagina in una foto sola (telefono «lungo»)
    await _mostra(t, SchermataInformazioni(righe: righe), lato: const Size(412, 1700));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/informazioni-intera.png'));

    await _mostra(t, const SchermataLicenze(versione: '1.7.0'));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/licenze.png'));

    // le due pagine che si aprono da Licenze: testo dell'AGPL e componenti (qui con due librerie finte)
    LicenseRegistry.addLicense(() async* {
      yield const LicenseEntryWithLineBreaks(['pdfrx'], 'MIT License\n\nCopyright (c) 2026 Esempio\n\n'
          'Permission is hereby granted, free of charge, to any person obtaining a copy\nof this software.');
      yield const LicenseEntryWithLineBreaks(['shared_preferences'], 'BSD 3-Clause License\n\nRedistribution and use '
          'in source and binary forms, with or without\nmodification, are permitted.');
    });
    Future<void> apri(String testo) async {
      await t.tap(find.text(testo));
      for (var i = 0; i < 4; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await t.pump(const Duration(milliseconds: 300));
      }
    }

    await apri('Leggi la licenza AGPL-3.0');
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/licenza-testo.png'));
    await t.drag(find.byType(Scrollable).first, const Offset(0, -6000));
    await t.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/licenza-testo-dentro.png'));
    await t.pageBack();
    await t.pump(const Duration(milliseconds: 600));

    await apri('Licenze dei componenti');
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/componenti.png'));
    await apri('pdfrx');
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/componenti-testo.png'));

    await t.pumpWidget(const SizedBox());
  });
}
