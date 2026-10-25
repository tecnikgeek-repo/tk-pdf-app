// Prove della licenza libera: tutto sbloccato, codice dispositivo casuale, statistiche solo col consenso.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tkpdf/tk_licenza.dart';

Future<Licenza> _nuova([Map<String, Object> salvato = const {}]) async {
  SharedPreferences.setMockInitialValues(salvato);
  final lic = Licenza(slug: 'tk-pdf-app', versione: 'prova');
  await lic.carica();
  return lic;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tutte le funzioni per tutti: niente Pro, niente Free/Pro', () async {
    final lic = await _nuova();
    expect(lic.sbloccato, isTrue);
    expect(lic.freePro, isFalse);
    expect(lic.isPro, isFalse);
    expect(lic.proGratis, isFalse);
    expect((await lic.attivaOCodice('AAAA-BBBB-CCCC-DDDD')).ok, isTrue);
  });

  test('anche con i dati del Pro delle versioni vecchie resta tutto sbloccato', () async {
    final lic = await _nuova({
      'tk_licenza_tk-pdf-app': jsonEncode({
        'prodotto': {'free_pro': true, 'donazione': 'https://www.paypal.com/donate/?hosted_button_id=X'},
      }),
    });
    expect(lic.sbloccato, isTrue);
    expect(lic.freePro, isFalse);
    expect(lic.donazione, endsWith('&locale.x=it_IT'));
  });

  test('codice dispositivo casuale, conservato e diverso per ogni installazione', () async {
    final a = await _nuova();
    expect(a.dispositivo, matches(RegExp(r'^[0-9a-f]{32}$')));
    final salvato = (await SharedPreferences.getInstance()).getString('tk_licenza_tk-pdf-app')!;
    final ancora = await _nuova({'tk_licenza_tk-pdf-app': salvato});
    expect(ancora.dispositivo, a.dispositivo, reason: 'lo stesso telefono tiene lo stesso codice');
    final b = await _nuova();
    expect(b.dispositivo, isNot(a.dispositivo));
    expect(b.codiceDonazione, matches(RegExp(r'^TKPDFA-[0-9A-F]{6}$')));
  });

  test('statistiche: nessuna risposta all\'inizio, poi la scelta resta', () async {
    final lic = await _nuova();
    expect(lic.consensoStatistiche, isNull);
    expect(lic.benvenutoVisto, isFalse);
    await lic.impostaStatistiche(false);
    expect(lic.consensoStatistiche, isFalse);
    final salvato = (await SharedPreferences.getInstance()).getString('tk_licenza_tk-pdf-app')!;
    final dopo = await _nuova({'tk_licenza_tk-pdf-app': salvato});
    expect(dopo.consensoStatistiche, isFalse);
  });

  test('senza consenso il segnale non parte (nessuna rete)', () async {
    final lic = await _nuova();
    await lic.segnale(); // senza consenso esce subito: se chiamasse il server, nei test fallirebbe
    final s = jsonDecode((await SharedPreferences.getInstance()).getString('tk_licenza_tk-pdf-app')!) as Map;
    expect(s.containsKey('segnale'), isFalse);
  });

  test('link PayPal sempre in italiano', () {
    expect(urlItaliano('https://www.paypal.com/donate/?hosted_button_id=X'), endsWith('&locale.x=it_IT'));
    expect(urlItaliano('https://www.paypal.com/donate/?hosted_button_id=X&locale.x=it_IT'),
        'https://www.paypal.com/donate/?hosted_button_id=X&locale.x=it_IT');
    expect(urlItaliano('https://pietrodefilippis.it/donazione/'), 'https://pietrodefilippis.it/donazione/');
  });
}
