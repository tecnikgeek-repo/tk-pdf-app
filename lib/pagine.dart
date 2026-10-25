// Gestione pagine: miniature, riordino trascinando, rotazione ed eliminazione.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'documenti.dart' as doc;
import 'tema.dart';

class SchermataPagine extends StatefulWidget {
  const SchermataPagine({super.key, required this.percorso});

  final String percorso;

  @override
  State<SchermataPagine> createState() => _SchermataPagineState();
}

class _Pagina {
  _Pagina(this.originale, this.miniatura);
  final int originale; // indice di partenza, da 0
  final Uint8List? miniatura;
  int rotazione = 0; // gradi aggiunti
}

class _SchermataPagineState extends State<SchermataPagine> {
  List<_Pagina> _pagine = [];
  bool _carico = true;
  bool _modificato = false;

  @override
  void initState() {
    super.initState();
    _apri();
  }

  Future<void> _apri() async {
    final documento = await PdfDocument.openFile(widget.percorso);
    final elenco = <_Pagina>[];
    for (var i = 0; i < documento.pages.length; i++) {
      final pagina = documento.pages[i];
      final scala = 150 / pagina.width;
      final resa = await pagina.render(
        width: (pagina.width * scala).round(),
        height: (pagina.height * scala).round(),
      );
      Uint8List? png;
      if (resa != null) {
        final immagine = await resa.createImage();
        final dati = await immagine.toByteData(format: ui.ImageByteFormat.png);
        png = dati?.buffer.asUint8List();
        immagine.dispose();
      }
      elenco.add(_Pagina(i, png));
    }
    await documento.dispose();
    if (mounted) {
      setState(() {
        _pagine = elenco;
        _carico = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: grigio100,
      body: Column(
        children: [
          Testata(
            sottotitolo: _carico ? 'Preparo le miniature…' : '${_pagine.length} pagine · trascina per riordinare',
            indietro: () => Navigator.of(context).pop(false),
            azioni: [
              if (_modificato)
                AzioneTk(Icons.save_outlined, 'Salva', _salva),
            ],
          ),
          Expanded(
            child: _carico
                ? const Center(child: CircularProgressIndicator())
                : ReorderableListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _pagine.length,
                    onReorderItem: (da, a) => setState(() {
                      _pagine.insert(a, _pagine.removeAt(da));
                      _modificato = true;
                    }),
                    itemBuilder: (context, i) => _riga(i),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _riga(int i) {
    final pagina = _pagine[i];
    return Card(
      key: ValueKey(pagina.originale),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 86,
              decoration: BoxDecoration(border: Border.all(color: grigio300), color: Colors.white),
              child: pagina.miniatura == null
                  ? const Icon(Icons.description_outlined, color: grigio300)
                  : RotatedBox(
                      quarterTurns: (pagina.rotazione ~/ 90) % 4,
                      child: Image.memory(pagina.miniatura!, fit: BoxFit.contain),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Pagina ${i + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: navy)),
            ),
            IconButton(
              tooltip: 'Ruota',
              onPressed: () => setState(() {
                pagina.rotazione = (pagina.rotazione + 90) % 360;
                _modificato = true;
              }),
              icon: const Icon(Icons.rotate_right),
            ),
            IconButton(
              tooltip: 'Elimina',
              onPressed: _pagine.length > 1
                  ? () => setState(() {
                        _pagine.removeAt(i);
                        _modificato = true;
                      })
                  : null,
              icon: const Icon(Icons.delete_outline),
            ),
            ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle, color: grigio500)),
          ],
        ),
      ),
    );
  }

  Future<void> _salva() async {
    final barra = ScaffoldMessenger.of(context);
    barra.showSnackBar(const SnackBar(content: Text('Salvo le pagine…'), duration: Duration(seconds: 30)));
    try {
      await doc.riordina(
        widget.percorso,
        _pagine.map((p) => p.originale).toList(),
        {for (var i = 0; i < _pagine.length; i++) i: _pagine[i].rotazione},
      );
      barra.hideCurrentSnackBar();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (errore) {
      barra.hideCurrentSnackBar();
      barra.showSnackBar(SnackBar(content: Text('Non riuscito: $errore')));
    }
  }
}

/// Apre la gestione pagine; ritorna true se il documento è stato cambiato.
Future<bool> gestisciPagine(BuildContext context, String percorso) async {
  if (!await File(percorso).exists()) return false;
  if (!context.mounted) return false;
  final esito = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => SchermataPagine(percorso: percorso)),
  );
  return esito ?? false;
}
