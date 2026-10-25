// Elenco dei file aperti di recente, tenuto nelle impostazioni del telefono.
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

const _chiave = 'recenti';

Future<List<String>> recenti() async {
  final pref = await SharedPreferences.getInstance();
  final elenco = pref.getStringList(_chiave) ?? const <String>[];
  final esistenti = <String>[];
  for (final p in elenco) {
    if (await File(p).exists()) esistenti.add(p);
  }
  if (esistenti.length != elenco.length) await pref.setStringList(_chiave, esistenti);
  return esistenti;
}

Future<void> aggiungiRecente(String percorso) async {
  final pref = await SharedPreferences.getInstance();
  final elenco = (pref.getStringList(_chiave) ?? <String>[]).where((p) => p != percorso).toList();
  elenco.insert(0, percorso);
  await pref.setStringList(_chiave, elenco.take(20).toList());
}

Future<void> dimenticaRecente(String percorso) async {
  final pref = await SharedPreferences.getInstance();
  final elenco = (pref.getStringList(_chiave) ?? <String>[]).where((p) => p != percorso).toList();
  await pref.setStringList(_chiave, elenco);
}

String nomeFile(String percorso) => percorso.split(Platform.pathSeparator).last.split('/').last;

String dimensioneLeggibile(int byte) {
  if (byte < 1024) return '$byte B';
  if (byte < 1024 * 1024) return '${(byte / 1024).toStringAsFixed(0)} KB';
  return '${(byte / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';
}
