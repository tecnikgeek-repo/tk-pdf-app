// Visualizzatore PDF: lettura, annotazioni a dito, firma, condivisione e operazioni sul documento.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import 'annota.dart';
import 'documenti.dart' as doc;
import 'modifica_testo.dart';
import 'pagine.dart';
import 'testo.dart';
import 'recenti.dart';
import 'tema.dart';

class SchermataVisualizza extends StatefulWidget {
  const SchermataVisualizza({super.key, required this.percorso});

  final String percorso;

  @override
  State<SchermataVisualizza> createState() => _SchermataVisualizzaState();
}

class _SchermataVisualizzaState extends State<SchermataVisualizza> {
  final _controllo = PdfViewerController();
  late String _percorso = widget.percorso;
  int _pagina = 1;
  int _pagine = 0;
  Key _chiave = UniqueKey();

  int _scheda = 0;
  Strumento _strumento = Strumento.nessuno;
  Pennello _pennello = const Pennello(accento, 2.5);
  final List<Tratto> _tratti = [];
  final List<FirmaDaMettere> _firme = [];
  Uint8List? _firmaPronta;
  List<RigaPagina> _righeTesto = const [];
  int _paginaRighe = 0;

  bool get _daSalvare => _tratti.isNotEmpty || _firme.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_daSalvare,
      onPopInvokedWithResult: (uscito, _) async {
        if (!uscito && _daSalvare) await _chiediSalvataggio();
      },
      child: Scaffold(
        backgroundColor: grigio200,
        body: Column(
          children: [
            Testata(
              sottotitolo: _daSalvare
                  ? '${nomeFile(_percorso)} · da salvare'
                  : (_pagine > 0 ? '${nomeFile(_percorso)} · pag. $_pagina di $_pagine' : nomeFile(_percorso)),
              indietro: () async {
                if (_daSalvare) {
                  await _chiediSalvataggio();
                } else if (mounted) {
                  Navigator.of(context).pop();
                }
              },
              azioni: [
                if (_daSalvare)
                  AzioneTk(Icons.save_outlined, 'Salva', _salva),
                AzioneTk(Icons.ios_share, 'Condividi', _condividi),
                AzioneTk(Icons.tune, 'Strumenti del documento', _menu),
              ],
            ),
            BarraSchede(
              voci: schedeTk,
              scelta: _scheda,
              onScelta: _cambiaScheda,
            ),
            _barraStrumenti(),
            Expanded(
              child: PdfViewer.file(
                _percorso,
                key: _chiave,
                controller: _controllo,
                params: PdfViewerParams(
                  backgroundColor: grigio200,
                  margin: 10,
                  // con penna o evidenziatore attivi il dito disegna invece di scorrere
                  panEnabled: _strumento != Strumento.penna && _strumento != Strumento.evidenziatore,
                  onViewerReady: (documento, controllo) {
                    setState(() => _pagine = documento.pages.length);
                  },
                  onPageChanged: (numero) {
                    setState(() => _pagina = numero ?? 1);
                    if (_strumento == Strumento.testo) _caricaRighe();
                  },
                  pageOverlaysBuilder: (context, riquadroPagina, pagina) => [
                    if (_strumento == Strumento.testo)
                      Positioned.fill(
                        child: _livelloTesto(pagina.pageNumber,
                            Size(riquadroPagina.width, riquadroPagina.height)),
                      )
                    else
                    Positioned.fill(
                      child: _strumento == Strumento.firma
                          ? GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (d) => _appoggiaFirma(pagina.pageNumber, d.localPosition,
                                  Size(riquadroPagina.width, riquadroPagina.height)),
                            )
                          : LivelloDisegno(
                              pagina: pagina.pageNumber,
                              dimensione: Size(riquadroPagina.width, riquadroPagina.height),
                              strumento: _strumento,
                              pennello: _pennello,
                              tratti: _tratti,
                              firme: _firme,
                              onNuovoTratto: (t) => setState(() => _tratti.add(t)),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            _barraPagine(),
          ],
        ),
      ),
    );
  }

  /// Strumenti della scheda scelta, come la riga strumenti del computer.
  Widget _barraStrumenti() {
    switch (_scheda) {
      case 1: // Annota
        return RigaStrumenti(children: [
          BottoneStrumento(
              testo: 'Penna',
              icona: Icons.edit_outlined,
              attivo: _strumento == Strumento.penna,
              onTap: () => _scegli(Strumento.penna)),
          BottoneStrumento(
              testo: 'Evidenzia',
              icona: Icons.brush_outlined,
              attivo: _strumento == Strumento.evidenziatore,
              onTap: () => _scegli(Strumento.evidenziatore)),
          BottoneStrumento(
              testo: 'Annulla tratto',
              icona: Icons.undo,
              abilitato: _tratti.isNotEmpty,
              onTap: () => setState(() => _tratti.removeLast())),
          BottoneStrumento(testo: 'Salva', icona: Icons.save_outlined, abilitato: _daSalvare, onTap: _salva),
        ]);
      case 2: // Firma
        return RigaStrumenti(children: [
          BottoneStrumento(
              testo: 'Firma',
              icona: Icons.draw_outlined,
              attivo: _strumento == Strumento.firma,
              onTap: () => _scegli(Strumento.firma)),
          BottoneStrumento(testo: 'Salva', icona: Icons.save_outlined, abilitato: _daSalvare, onTap: _salva),
        ]);
      case 3: // Modifica testo
        return RigaStrumenti(children: [
          BottoneStrumento(
              testo: 'Modifica testo',
              icona: Icons.text_fields,
              attivo: _strumento == Strumento.testo,
              onTap: () => _scegli(Strumento.testo)),
          BottoneStrumento(
              testo: 'Riconosci testo', icona: Icons.auto_fix_high, onTap: _riconosciTesto),
        ]);
      case 4: // Pagine
        return RigaStrumenti(children: [
          BottoneStrumento(testo: 'Gestisci pagine', icona: Icons.auto_awesome_motion_outlined, onTap: _gestisciPagine),
          BottoneStrumento(testo: 'Ruota tutte', icona: Icons.rotate_right, onTap: _ruota),
          BottoneStrumento(testo: 'Comprimi', icona: Icons.compress, onTap: _comprimi),
          BottoneStrumento(testo: 'Password', icona: Icons.lock_outline, onTap: _password),
        ]);
      default: // Visualizza
        return RigaStrumenti(children: [
          BottoneStrumento(
              testo: 'Leggi',
              icona: Icons.pan_tool_alt_outlined,
              attivo: _strumento == Strumento.nessuno,
              onTap: () => _scegli(Strumento.nessuno)),
          BottoneStrumento(testo: 'Condividi', icona: Icons.ios_share, onTap: _condividi),
        ]);
    }
  }

  /// Cambiare scheda sceglie lo strumento giusto, come sul computer.
  void _cambiaScheda(int indice) {
    setState(() => _scheda = indice);
    switch (indice) {
      case 1:
        _scegli(Strumento.penna);
      case 2:
        _scegli(Strumento.firma);
      case 3:
        _scegli(Strumento.testo);
      default:
        _scegli(Strumento.nessuno);
    }
  }

  Future<void> _gestisciPagine() async {
    final cambiato = await gestisciPagine(context, _percorso);
    if (cambiato) await _ricarica();
  }

  /// Rilegge il documento dal disco.
  ///
  /// pdfrx tiene in memoria i documenti già aperti, con il percorso come chiave: dopo un
  /// salvataggio il file è cambiato ma a schermo resterebbe quello vecchio (sembra che non
  /// sia successo niente). Con `forceReload` lo rilegge davvero.
  Future<void> _ricarica() async {
    await PdfDocumentRefFile(_percorso).resolveListenable().load(forceReload: true);
    if (mounted) setState(() => _chiave = UniqueKey());
  }

  Widget _barraPagine() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(8, 6, 8, MediaQuery.of(context).padding.bottom + 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _pagina > 1 ? () => _controllo.goToPage(pageNumber: _pagina - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text(_pagine > 0 ? '$_pagina / $_pagine' : '—',
              style: const TextStyle(fontWeight: FontWeight.w700, color: navy)),
          IconButton(
            onPressed: _pagine > 0 && _pagina < _pagine
                ? () => _controllo.goToPage(pageNumber: _pagina + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Future<void> _scegli(Strumento strumento) async {
    if (strumento == Strumento.firma && _firmaPronta == null) {
      final png = await showModalBottomSheet<Uint8List>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const FoglioFirma(),
      );
      if (png == null) return;
      _firmaPronta = png;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Tocca il punto dove mettere la firma')));
      }
    }
    if (strumento == Strumento.testo) {
      await _caricaRighe();
      if (_righeTesto.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Questa pagina è una immagine: non ha testo da toccare.'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(label: 'Riconosci testo', onPressed: _riconosciTesto),
        ));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Tocca una riga evidenziata per cambiarla')));
      }
    }
    if (strumento == Strumento.penna || strumento == Strumento.evidenziatore) {
      _pennello = strumento == Strumento.evidenziatore
          ? const Pennello(Color(0xFFFDE047), 2.5)
          : const Pennello(accento, 2.5);
    }
    setState(() => _strumento = strumento);
  }

  Future<void> _caricaRighe() async {
    try {
      final righe = await righeDellaPagina(_percorso, _pagina);
      if (mounted) {
        setState(() {
          _righeTesto = righe;
          _paginaRighe = _pagina;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _righeTesto = const []);
    }
  }

  Widget _livelloTesto(int pagina, Size dimensione) {
    if (pagina != _paginaRighe) return const SizedBox.shrink();
    final misure = _misuraPagina(pagina);
    return Stack(
      children: [
        for (final riga in _righeTesto) _riquadroRiga(riga, misure, dimensione),
      ],
    );
  }

  /// Riquadro tocca-e-cambia di una riga. L'area sensibile è alta almeno 28: le righe
  /// sottili erano quasi impossibili da centrare col dito.
  Widget _riquadroRiga(RigaPagina riga, Size misure, Size dimensione) {
    final alto = riga.riquadro.height / misure.height * dimensione.height;
    final altoTocco = alto < 28 ? 28.0 : alto;
    final largo = riga.riquadro.width / misure.width * dimensione.width;
    return Positioned(
      left: riga.riquadro.left / misure.width * dimensione.width,
      top: riga.riquadro.top / misure.height * dimensione.height - (altoTocco - alto) / 2,
      width: largo < 24 ? 24 : largo,
      height: altoTocco,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _modificaRiga(riga),
        child: Center(
          child: SizedBox(
            height: alto,
            width: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                color: accentoChiaro.withValues(alpha: 0.35),
                border: Border.all(color: accento, width: 0.8),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Size _misuraPagina(int pagina) {
    final p = _controllo.isReady ? _controllo.pages[pagina - 1] : null;
    return p == null ? const Size(595, 842) : Size(p.width, p.height);
  }

  Future<void> _modificaRiga(RigaPagina riga) async {
    final controllo = TextEditingController(text: riga.testo);
    final nuovo = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifica testo'),
        content: TextField(
          controller: controllo,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(labelText: 'Testo della riga'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(context, controllo.text), child: const Text('Applica')),
        ],
      ),
    );
    if (nuovo == null || nuovo == riga.testo) return;
    var rifatta = true;
    await _lavora('Cambio il testo…', () async {
      rifatta = await cambiaRiga(_percorso, _pagina, riga, nuovo);
      return _percorso;
    }, ricarica: true);
    if (!mounted) return;
    if (!rifatta) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Riga cambiata (il testo vecchio resta cercabile sotto).')));
    }
    await _caricaRighe();
  }

  Future<void> _appoggiaFirma(int pagina, Offset posizione, Size dimensione) async {
    final png = _firmaPronta;
    if (png == null) return;
    // l'immagine serve anche per mostrare subito la firma sulla pagina, prima di salvare
    final immagine = await decodeImageFromList(png);
    const largaFrazione = 0.35;
    final larga = largaFrazione * dimensione.width;
    final alta = larga * immagine.height / immagine.width;
    if (!mounted) return;
    setState(() {
      _firme.add(FirmaDaMettere(
        pagina: pagina,
        // centrata dove si è toccato, non con l'angolo sul dito
        posizione: Offset(
          ((posizione.dx - larga / 2) / dimensione.width).clamp(0.0, 1 - largaFrazione),
          ((posizione.dy - alta / 2) / dimensione.height).clamp(0.0, 1 - alta / dimensione.height),
        ),
        png: png,
        anteprima: immagine,
      ));
      _strumento = Strumento.nessuno;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Firma messa: ora tocca Salva per scriverla nel documento')));
  }

  Future<void> _chiediSalvataggio() async {
    final scelta = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifiche non salvate'),
        content: const Text('Vuoi salvare i segni fatti sul documento?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'annulla'), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(context, 'scarta'), child: const Text('Esci senza salvare')),
          FilledButton(onPressed: () => Navigator.pop(context, 'salva'), child: const Text('Salva')),
        ],
      ),
    );
    if (!mounted || scelta == null || scelta == 'annulla') return;
    if (scelta == 'salva') {
      await _salva();
      if (!mounted) return;
    }
    setState(() {
      _tratti.clear();
      _firme.clear();
    });
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _salva() async {
    await _lavora('Salvo i segni…', () async {
      await applicaTratti(_percorso, _tratti, firme: _firme);
      _tratti.clear();
      _firme.clear();
      return _percorso;
    }, ricarica: true);
  }

  Future<void> _condividi() async {
    await SharePlus.instance.share(ShareParams(files: [XFile(_percorso)], title: nomeFile(_percorso)));
  }

  void _menu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.auto_awesome_motion_outlined),
              title: const Text('Gestisci pagine (riordina, ruota, elimina)'),
              onTap: () async {
                Navigator.pop(context);
                final cambiato = await gestisciPagine(context, _percorso);
                if (cambiato) await _ricarica();
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Salva con password'),
              onTap: () {
                Navigator.pop(context);
                _password();
              },
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('Rendi il testo modificabile (riconoscimento)'),
              onTap: () {
                Navigator.pop(context);
                _riconosciTesto();
              },
            ),
            ListTile(
              leading: const Icon(Icons.compress),
              title: const Text('Comprimi (file più leggero)'),
              onTap: () {
                Navigator.pop(context);
                _comprimi();
              },
            ),
            ListTile(
              leading: const Icon(Icons.rotate_right),
              title: const Text('Ruota tutte le pagine'),
              onTap: () {
                Navigator.pop(context);
                _ruota();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _password() async {
    final controllo = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Salva con password'),
        content: TextField(
          controller: controllo,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password', hintText: 'almeno 4 caratteri'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(context, controllo.text), child: const Text('Salva')),
        ],
      ),
    );
    if (password == null || password.length < 4) return;
    await _lavora('Creo la copia protetta…', () => doc.conPassword(_percorso, password));
  }

  Future<void> _riconosciTesto() async {
    final barra = ScaffoldMessenger.of(context);
    barra.showSnackBar(const SnackBar(content: Text('Riconosco il testo…'), duration: Duration(minutes: 5)));
    try {
      final nuovo = await rendiTestoModificabile(_percorso, avanzamento: (pagina, totale) {
        barra.hideCurrentSnackBar();
        barra.showSnackBar(SnackBar(
            content: Text('Riconosco il testo: pagina $pagina di $totale'),
            duration: const Duration(minutes: 5)));
      });
      barra.hideCurrentSnackBar();
      if (!mounted) return;
      if (nuovo == null) {
        barra.showSnackBar(const SnackBar(content: Text('Nessuna scritta da riconoscere: le pagine hanno già testo.')));
        return;
      }
      await aggiungiRecente(nuovo);
      if (!mounted) return;
      setState(() {
        _percorso = nuovo;
        _chiave = UniqueKey();
      });
      barra.showSnackBar(SnackBar(content: Text('Testo riconosciuto: ${nomeFile(nuovo)}')));
    } catch (errore) {
      barra.hideCurrentSnackBar();
      barra.showSnackBar(SnackBar(content: Text('Riconoscimento non riuscito: $errore')));
    }
  }

  Future<void> _comprimi() async {
    await _lavora('Comprimo…', () => doc.comprimi(_percorso));
  }

  Future<void> _ruota() async {
    final pagine = await doc.numeroPagine(_percorso);
    await _lavora('Ruoto le pagine…', () async {
      await doc.modificaPagine(_percorso, rotazioni: {for (var i = 0; i < pagine; i++) i: 90});
      return _percorso;
    }, ricarica: true);
  }

  Future<void> _lavora(String messaggio, Future<String> Function() azione, {bool ricarica = false}) async {
    final barra = ScaffoldMessenger.of(context);
    barra.showSnackBar(SnackBar(content: Text(messaggio), duration: const Duration(seconds: 30)));
    try {
      final risultato = await azione();
      barra.hideCurrentSnackBar();
      if (!mounted) return;
      if (ricarica) {
        await _ricarica();
        if (!mounted) return;
        barra.showSnackBar(const SnackBar(content: Text('Salvato')));
      } else if (risultato != _percorso) {
        await aggiungiRecente(risultato);
        if (!mounted) return;
        setState(() {
          _percorso = risultato;
          _chiave = UniqueKey();
        });
        barra.showSnackBar(SnackBar(content: Text('Salvato: ${nomeFile(risultato)}')));
      }
    } catch (errore) {
      barra.hideCurrentSnackBar();
      barra.showSnackBar(SnackBar(content: Text('Non riuscito: $errore')));
    }
  }
}

/// Apre un PDF e lo segna tra i recenti.
Future<void> apriPdf(BuildContext context, String percorso) async {
  if (!await File(percorso).exists()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Il file non esiste più.')));
    }
    return;
  }
  await aggiungiRecente(percorso);
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => SchermataVisualizza(percorso: percorso)),
  );
}
