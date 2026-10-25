// tk-pdf per Android e iPhone — TecnikGeek (pietrodefilippis.it)
// Copyright (C) 2026 Pietro De Filippis (TecnikGeek) — AGPL-3.0-or-later, vedi COPYING
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdfrx/pdfrx.dart';

import 'home.dart';
import 'tema.dart';
import 'tk_licenza.dart';
import 'tk_pro.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configTk = configPdf;
  pdfrxFlutterInitialize();
  registraLicenzaAgpl();
  await _avviaLicenza();
  runApp(const AppTkPdf());
}

/// Benvenuto, statistiche (solo col consenso) e invito al caffè: tutte le funzioni sono per tutti.
Future<void> _avviaLicenza() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final lic = Licenza(slug: 'tk-pdf-app', versione: info.version);
    await lic.carica();
    proTk = ProTk(lic);
    lic.avvia(); // segnale del giorno in sottofondo, SOLO se l'utente ha detto sì alle statistiche
  } catch (_) {
    proTk = null; // senza memoria niente benvenuto né statistiche: l'app funziona lo stesso
  }
}

class AppTkPdf extends StatelessWidget {
  const AppTkPdf({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'tk-pdf',
        debugShowCheckedModeBanner: false,
        theme: temaKit(),
        // menu del testo («Incolla», «Copia»), calendari e messaggi di sistema in italiano
        locale: const Locale('it'),
        supportedLocales: const [Locale('it')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const ConAvvio(child: SchermataHome()),
      );
}
