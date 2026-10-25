// Schermata iniziale, come quella del software per computer: barra navy, schede,
// riga strumenti e scheda di benvenuto con i file recenti (con anteprima della prima pagina).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdfrx/pdfrx.dart' as rx;

import 'documenti.dart' as doc;
import 'recenti.dart';
import 'ritaglio.dart';
import 'tema.dart';
import 'tk_pro.dart';
import 'visualizza.dart';

/// Schede dell'app, le stesse del computer.

class SchermataHome extends StatefulWidget {
  const SchermataHome({super.key});

  @override
  State<SchermataHome> createState() => _SchermataHomeState();
}

class _SchermataHomeState extends State<SchermataHome> {
  List<String> _recenti = const [];
  final Map<String, Uint8List?> _anteprime = {};
  bool _occupato = false;

  @override
  void initState() {
    super.initState();
    _aggiorna();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // primo avvio: benvenuto (software libero, privacy, statistiche) PRIMA di qualunque chiamata in rete
      if (mounted) await benvenutoTk(context);
      // controllo discreto: parla solo se c'è una versione nuova
      if (mounted) proponiAggiornamento(context, avvisaSeAggiornata: false);
      // invito al caffè: al primo avvio e poi al massimo una volta al mese, mai sopra un'altra finestra
      if (mounted) invitoCaffe(context);
    });
  }

  Future<void> _aggiorna() async {
    final elenco = await recenti();
    if (mounted) setState(() => _recenti = elenco);
    for (final percorso in elenco.take(8)) {
      if (!_anteprime.containsKey(percorso)) {
        _anteprime[percorso] = await anteprimaPrimaPagina(percorso);
        if (mounted) setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Testata(
            sottotitolo: 'Nessun documento aperto',
            azioni: [
              AzioneTk(Icons.info, 'Informazioni',
                  () => apriInformazioni(context,
                      righe: () async => [('Documenti recenti', '${(await recenti()).length}')])),
            ],
          ),
          // schede spente finché non c'è un documento, come sul computer
          BarraSchede(voci: schedeTk, scelta: 0, onScelta: (_) {}, attive: false),
          RigaStrumenti(children: [
            BottoneStrumento(testo: 'Apri', icona: Icons.folder_open_outlined, onTap: _apri),
            BottoneStrumento(testo: 'Scansiona', icona: Icons.document_scanner_outlined, onTap: _scansiona),
            BottoneStrumento(testo: 'Da foto', icona: Icons.photo_library_outlined, onTap: _daFoto),
            BottoneStrumento(testo: 'Unisci', icona: Icons.merge_type, onTap: _unisci),
          ]),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _aggiorna,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 18, 14, 24),
                children: [_cardBenvenuto()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardBenvenuto() {
    return CardTk(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
      child: Column(
        children: [
          const LogoTk(lato: 72),
          const SizedBox(height: 12),
          const Text('tk-pdf', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: navy)),
          const SizedBox(height: 6),
          const Text('Apri, annota, firma, scansiona e modifica i tuoi PDF.',
              textAlign: TextAlign.center, style: TextStyle(color: grigio500, fontSize: 13.5)),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _occupato ? null : _scansiona,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scansiona un documento'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _occupato ? null : _apri,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Apri un PDF'),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _occupato ? null : _daFoto,
                  icon: const Icon(Icons.photo_library_outlined, size: 19),
                  label: const Text('Da foto', style: TextStyle(fontSize: 14)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _occupato ? null : _unisci,
                  icon: const Icon(Icons.merge_type, size: 19),
                  label: const Text('Unisci', style: TextStyle(fontSize: 14)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Align(alignment: Alignment.centerLeft, child: TitoloSezione('File recenti')),
          const SizedBox(height: 8),
          if (_recenti.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Ancora nessun file: scansiona un documento o aprine uno.',
                  style: TextStyle(color: grigio500, fontSize: 13)),
            )
          else
            ..._recenti.map(_riga),
          const SizedBox(height: 10),
          const Text('creato da TecnikGeek', style: TextStyle(color: grigio300, fontSize: 11.5)),
        ],
      ),
    );
  }

  Widget _riga(String percorso) {
    final file = File(percorso);
    final dimensione = file.existsSync() ? dimensioneLeggibile(file.lengthSync()) : '';
    final anteprima = _anteprime[percorso];
    return InkWell(
      onTap: () async {
        await apriPdf(context, percorso);
        await _aggiorna();
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 50,
              decoration: BoxDecoration(color: grigio100, border: Border.all(color: grigio200)),
              clipBehavior: Clip.antiAlias,
              child: anteprima == null
                  ? const Icon(Icons.picture_as_pdf, color: accento, size: 18)
                  : Image.memory(anteprima, fit: BoxFit.cover),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nomeFile(percorso),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, color: navy, fontSize: 14)),
                  Text(dimensione, style: const TextStyle(color: grigio500, fontSize: 12)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Togli dai recenti',
              onPressed: () async {
                await dimenticaRecente(percorso);
                _anteprime.remove(percorso);
                await _aggiorna();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scansiona() async {
    final immagini = await _protetto(() => CunningDocumentScanner.getPictures(
          noOfPages: 20,
          scannerSource: ScannerSource.cameraAndGallery,
        ));
    if (immagini == null || immagini.isEmpty) return;
    await _ritagliaECrea(immagini, 'Scansione');
  }

  Future<void> _daFoto() async {
    final scelte = await _protetto(() => ImagePicker().pickMultiImage());
    if (scelte == null || scelte.isEmpty) return;
    await _ritagliaECrea(scelte.map((x) => x.path).toList(), 'Foto');
  }

  Future<void> _apri() async {
    final scelta = await _protetto(() => FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        ));
    final percorso = scelta?.path;
    if (percorso == null) return;
    if (!mounted) return;
    await apriPdf(context, percorso);
    await _aggiorna();
  }

  Future<void> _unisci() async {
    final scelta = await _protetto(() => FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        ));
    final file = (scelta ?? const []).map((f) => f.path).whereType<String>().toList();
    if (file.length < 2) {
      _avviso('Scegli almeno due PDF da unire.');
      return;
    }
    await _lavora('Unisco i file…', () => doc.unisci(file));
  }

  /// Prima il ritaglio (bordi trovati da soli, correggibili), poi il PDF.
  Future<void> _ritagliaECrea(List<String> immagini, String nome) async {
    if (!mounted) return;
    final angoli = await ritagliaFoto(context, immagini);
    if (angoli == null || !mounted) return;
    await _lavora('Ritaglio le pagine e creo il PDF…',
        () async => doc.pdfDaImmagini(await applicaRitagli(immagini, angoli), nome: nome));
  }

  Future<void> _lavora(String messaggio, Future<String> Function() azione) async {
    setState(() => _occupato = true);
    final barra = ScaffoldMessenger.of(context);
    barra.showSnackBar(SnackBar(content: Text(messaggio), duration: const Duration(seconds: 30)));
    try {
      final percorso = await azione();
      barra.hideCurrentSnackBar();
      if (!mounted) return;
      await apriPdf(context, percorso);
      await _aggiorna();
    } catch (errore) {
      barra.hideCurrentSnackBar();
      _avviso('Non riuscito: $errore');
    } finally {
      if (mounted) setState(() => _occupato = false);
    }
  }

  /// Esegue l'azione mostrando l'errore invece di far chiudere l'app.
  Future<T?> _protetto<T>(Future<T> Function() azione) async {
    try {
      return await azione();
    } catch (errore) {
      _avviso('Non riuscito: $errore');
      return null;
    }
  }

  void _avviso(String testo) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(testo)));
  }
}

/// Miniatura della prima pagina, per riconoscere il file a colpo d'occhio.
Future<Uint8List?> anteprimaPrimaPagina(String percorso) async {
  try {
    final documento = await rx.PdfDocument.openFile(percorso);
    final pagina = documento.pages.first;
    final scala = 200 / pagina.width;
    final resa =
        await pagina.render(width: (pagina.width * scala).round(), height: (pagina.height * scala).round());
    Uint8List? png;
    if (resa != null) {
      final immagine = await resa.createImage();
      final dati = await immagine.toByteData(format: ui.ImageByteFormat.png);
      png = dati?.buffer.asUint8List();
      immagine.dispose();
    }
    await documento.dispose();
    return png;
  } catch (_) {
    return null;
  }
}
