// Finestra di attesa con la percentuale, per i lavori che durano, e scelta di dove salvare il PDF.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'documenti.dart' as doc;
import 'recenti.dart';
import 'tema.dart';

/// A che punto è il lavoro: finché nessuno chiama [segna] la barra si muove senza numero.
class Avanzamento {
  final _stato = ValueNotifier<(double?, String)>((null, ''));

  /// [frazione] da 0 a 1. Non torna mai indietro, anche se i passaggi arrivano in ritardo.
  void segna(double frazione, String testo) {
    final prima = _stato.value.$1 ?? 0;
    _stato.value = (frazione.clamp(prima, 1.0), testo);
  }
}

/// Testo mostrato sotto la barra: «42%» oppure niente se la percentuale non si conosce.
String percentuale(double? frazione) => frazione == null ? '' : '${(frazione * 100).floor()}%';

/// Fa il lavoro con la finestra aperta, che non si può chiudere finché non ha finito.
Future<T> conAvanzamento<T>(
  BuildContext context,
  String titolo,
  Future<T> Function(Avanzamento) lavoro,
) async {
  final avanzamento = Avanzamento();
  final navigatore = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: FinestraAvanzamento(titolo: titolo, stato: avanzamento._stato),
    ),
  );
  try {
    return await lavoro(avanzamento);
  } finally {
    navigatore.pop();
  }
}

class FinestraAvanzamento extends StatelessWidget {
  const FinestraAvanzamento({super.key, required this.titolo, required this.stato});

  final String titolo;
  final ValueListenable<(double?, String)> stato;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(titolo),
      content: ValueListenableBuilder<(double?, String)>(
        valueListenable: stato,
        builder: (_, valore, _) {
          final (frazione, testo) = valore;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: frazione,
                      minHeight: 8,
                      color: accento,
                      backgroundColor: grigio200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  if (frazione != null) ...[
                    const SizedBox(width: 12),
                    Text(percentuale(frazione), style: const TextStyle(fontWeight: FontWeight.w700, color: navy)),
                  ],
                ],
              ),
              if (testo.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(testo, style: const TextStyle(color: grigio500, fontSize: 13)),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Apre la finestra «Salva» di Android o iPhone per scegliere cartella e nome del PDF.
/// Il file resta comunque dentro tk-pdf, tra i recenti: annullare non fa perdere niente.
Future<void> chiediDoveSalvare(BuildContext context, String percorso, {bool avvisaSeAnnulli = true}) async {
  final barra = ScaffoldMessenger.of(context);
  try {
    final salvato = await doc.salvaCopiaDove(percorso);
    if (salvato) {
      barra.showSnackBar(SnackBar(content: Text('Salvato: ${nomeFile(percorso)}')));
    } else if (avvisaSeAnnulli) {
      barra.showSnackBar(const SnackBar(content: Text('Non salvato altrove: il PDF resta in tk-pdf, tra i file recenti.')));
    }
  } catch (errore) {
    barra.showSnackBar(SnackBar(content: Text('Non riesco a salvarlo lì: $errore')));
  }
}
