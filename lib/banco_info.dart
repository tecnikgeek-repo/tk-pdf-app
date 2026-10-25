// Banco di prova: apre direttamente la schermata Informazioni (per le anteprime).
import 'package:flutter/material.dart';

import 'tema.dart';

void main() {
  configTk = configPdf;
  runApp(MaterialApp(debugShowCheckedModeBanner: false, theme: temaKit(), home: const SchermataInformazioni()));
}
