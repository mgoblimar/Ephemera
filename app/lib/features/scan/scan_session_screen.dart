import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ephemera_ai/data/proxy_client.dart';
import 'package:ephemera_ai/features/capture/photo_source.dart';
import 'package:ephemera_ai/features/scan/scan_motion.dart';
import 'package:ephemera_ai/features/scan/scan_widgets.dart';
import 'package:ephemera_ai/models/scan.dart';
import 'package:ephemera_ai/models/segmentation.dart';
import 'package:ephemera_ai/providers.dart';

/// Scan several photos (detection only), choose the pieces worth keeping,
/// then cut them all at once: up to 16 pieces per billed SAM request.
/// Pops with the number of scraps saved.
class ScanSessionScreen extends ConsumerStatefulWidget {
  const ScanSessionScreen({super.key, this.photoPicker = pickPhoto});

  /// Camera/gallery picker; replaceable in tests.
  final Future<PickedPhoto?> Function(BuildContext context) photoPicker;

  @override
  ConsumerState<ScanSessionScreen> createState() => _ScanSessionScreenState();
}

class _ScanSessionScreenState extends ConsumerState<ScanSessionScreen> {
  List<SessionPhoto> _photos = const [];
  Set<String> _chosen = const {};
  CutStyle _style = CutStyle.tight;
  CutSize _size = CutSize.m;
  bool _cutting = false;

  /// Set after a successful cut: the new scraps shown before leaving.
  ({List<Uint8List> pngs, int saved})? _reveal;
  Set<String> _splitting = const {};
  Set<String> _alreadySplit = const {};
  int _nextKey = 0;

  ProxyClient get _proxy => ref.read(proxyClientProvider);

  List<ScanPiece> get _chosenPieces => [
    for (final photo in _photos)
      for (final piece in photo.scan?.pieces ?? const <ScanPiece>[])
        if (_chosen.contains(piece.key)) piece,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _addPhoto());
  }

  Future<void> _addPhoto() async {
    final picked = await widget.photoPicker(context);
    if (picked == null || !mounted) return;
    final photo = SessionPhoto(
      key: _nextKey++,
      bytes: picked.bytes,
      filename: picked.filename,
    );
    setState(() => _photos = List.unmodifiable([..._photos, photo]));
    await _detect(photo);
  }

  Future<void> _detect(SessionPhoto photo) async {
    try {
      final scan = await _proxy.scanDetect(
        photo.bytes,
        filename: photo.filename,
      );
      if (!mounted) return;
      _replace(photo.withScan(scan));
      // Everything found starts chosen; untick what isn't worth keeping.
      setState(
        () => _chosen = Set.unmodifiable({
          ..._chosen,
          ...scan.pieces.map((p) => p.key),
        }),
      );
    } on ProxyException catch (e) {
      if (mounted) _replace(photo.withError(e.message));
    }
  }

  void _retry(SessionPhoto photo) {
    final retrying = photo.retrying();
    _replace(retrying);
    _detect(retrying);
  }

  void _remove(SessionPhoto photo) {
    final keys = photo.scan?.pieces.map((p) => p.key).toSet() ?? const {};
    setState(() {
      _photos = List.unmodifiable(_photos.where((p) => p.key != photo.key));
      _chosen = Set.unmodifiable(_chosen.difference(keys));
    });
  }

  void _replace(SessionPhoto updated) {
    setState(() {
      _photos = List.unmodifiable([
        for (final p in _photos) p.key == updated.key ? updated : p,
      ]);
    });
  }

  /// Asks Spark for the design elements inside [piece]; they arrive chosen.
  Future<void> _split(SessionPhoto photo, ScanPiece piece) async {
    setState(() => _splitting = Set.unmodifiable({..._splitting, piece.key}));
    try {
      final elements = await _proxy.scanSplit(piece);
      if (!mounted) return;
      final current = _photos.firstWhere((p) => p.key == photo.key);
      final scan = current.scan;
      if (scan != null) {
        _replace(current.withScan(scan.withElements(piece.id, elements)));
      }
      setState(() {
        _alreadySplit = Set.unmodifiable({..._alreadySplit, piece.key});
        _chosen = Set.unmodifiable({..._chosen, ...elements.map((e) => e.key)});
      });
      if (elements.isEmpty) {
        _showMessage('No separate designs found on this piece.');
      }
    } on ProxyException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) {
        setState(
          () => _splitting = Set.unmodifiable(
            Set.of(_splitting)..remove(piece.key),
          ),
        );
      }
    }
  }

  void _toggle(ScanPiece piece) {
    setState(() {
      _chosen = Set.unmodifiable(
        _chosen.contains(piece.key)
            ? (Set.of(_chosen)..remove(piece.key))
            : {..._chosen, piece.key},
      );
    });
  }

  void _chooseAll(SessionPhoto photo, bool chosen) {
    final keys = photo.scan?.pieces.map((p) => p.key).toSet() ?? const {};
    setState(() {
      _chosen = Set.unmodifiable(
        chosen ? {..._chosen, ...keys} : _chosen.difference(keys),
      );
    });
  }

  Future<void> _cutAndSave() async {
    final pieces = _chosenPieces;
    if (pieces.isEmpty) return;
    setState(() => _cutting = true);
    try {
      final result = await _proxy.scanCut(
        pieces: pieces,
        style: _style,
        size: _size,
      );
      final saved = await _saveByPhoto(result);
      if (!mounted) return;
      if (result.missedCount > 0) {
        _showMessage(
          "${result.missedCount} piece(s) couldn't be cut out. Try a clearer photo.",
        );
      }
      if (saved == 0) {
        Navigator.pop(context, saved);
        return;
      }
      setState(
        () => _reveal = (
          pngs: [for (final s in result.scraps) s.scrap.png],
          saved: saved,
        ),
      );
    } on ProxyException catch (e) {
      _showMessage(e.message);
    } on FileSystemException {
      _showMessage(
        "Couldn't save to your device. Check free storage and try again.",
      );
    } finally {
      if (mounted) setState(() => _cutting = false);
    }
  }

  /// Each photo becomes one capture in the archive, holding its own scraps.
  Future<int> _saveByPhoto(ScanCutResult result) async {
    final repository = await ref.read(scrapRepositoryProvider.future);
    var saved = 0;
    for (final photo in _photos) {
      final imageId = photo.scan?.imageId;
      final pieces = {
        for (final p in photo.scan?.pieces ?? const <ScanPiece>[]) p.id: p,
      };
      final cutouts = [
        for (final s in result.scraps)
          if (s.imageId == imageId) _withOrigin(s.scrap, pieces),
      ];
      if (cutouts.isEmpty) continue;
      final scraps = await repository.saveCapture(
        photoJpeg: photo.bytes,
        cutouts: cutouts,
      );
      saved += scraps.length;
    }
    ref.invalidate(scrapsProvider);
    // Read the new scraps' text and tags in the background (~₱0.01 each).
    unawaited(ref.read(enrichmentServiceProvider).enrichPending());
    return saved;
  }

  /// Records which whole piece a Split element came from (for archive filters).
  CutoutScrap _withOrigin(CutoutScrap scrap, Map<String, ScanPiece> pieces) {
    final parentId = pieces[scrap.maskId]?.parentId;
    if (parentId == null) return scrap;
    return scrap.withOrigin(
      parentPieceId: parentId,
      parentLabel: pieces[parentId]?.label,
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan session')),
      body: SafeArea(
        child: Stack(
          children: [
            _session(),
            if (_reveal case final reveal?)
              Positioned.fill(
                child: CutReveal(
                  pngs: reveal.pngs,
                  onDone: () => Navigator.pop(context, reveal.saved),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _session() {
    return Column(
      children: [
        Expanded(
          child: _photos.isEmpty
              ? const EmptySession()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    for (final photo in _photos)
                      PhotoSection(
                        photo: photo,
                        chosen: _chosen,
                        onToggle: _toggle,
                        onChooseAll: (all) => _chooseAll(photo, all),
                        onRetry: () => _retry(photo),
                        onRemove: () => _remove(photo),
                        splitting: _splitting,
                        alreadySplit: _alreadySplit,
                        onSplit: (piece) => _split(photo, piece),
                      ),
                  ],
                ),
        ),
        CutBar(
          chosenCount: _chosenPieces.length,
          style: _style,
          size: _size,
          cutting: _cutting,
          onStyle: (s) => setState(() => _style = s),
          onSize: (s) => setState(() => _size = s),
          onAddPhoto: _cutting ? null : _addPhoto,
          onCut: _cutAndSave,
        ),
      ],
    );
  }
}
