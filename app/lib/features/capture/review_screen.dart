import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ephemera_ai/data/proxy_client.dart';
import 'package:ephemera_ai/features/capture/photo_with_masks.dart';
import 'package:ephemera_ai/models/segmentation.dart';
import 'package:ephemera_ai/providers.dart';
import 'package:ephemera_ai/theme.dart';

/// Shows the masks SAM found, lets the user keep/discard them, tap to add
/// missed items, pick a cut style, and save the cutouts to the archive.
/// Pops with the number of scraps saved.
class CaptureReviewScreen extends ConsumerStatefulWidget {
  const CaptureReviewScreen({
    super.key,
    required this.photo,
    required this.filename,
  });

  final Uint8List photo;
  final String filename;

  @override
  ConsumerState<CaptureReviewScreen> createState() =>
      _CaptureReviewScreenState();
}

class _CaptureReviewScreenState extends ConsumerState<CaptureReviewScreen> {
  SegmentResult? _result;
  String? _error;
  Set<String> _kept = const {};
  CutStyle _style = CutStyle.tight;
  CutSize _size = CutSize.m;
  bool _adding = false;
  bool _saving = false;

  ProxyClient get _proxy => ref.read(proxyClientProvider);

  @override
  void initState() {
    super.initState();
    _segment();
  }

  Future<void> _segment() async {
    setState(() => _error = null);
    try {
      final result = await _proxy.segmentAuto(
        widget.photo,
        filename: widget.filename,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _kept = Set.unmodifiable(result.masks.map((m) => m.id));
      });
    } on ProxyException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _addAt(Offset photoPoint) async {
    final result = _result;
    if (result == null || _adding) return;
    setState(() => _adding = true);
    try {
      final mask = await _proxy.segmentPoint(result.imageId, [
        TapPoint(photoPoint.dx, photoPoint.dy),
      ]);
      if (!mounted) return;
      setState(() {
        _result = result.withMask(mask);
        _kept = Set.unmodifiable({..._kept, mask.id});
      });
    } on ProxyException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  void _toggle(String maskId) {
    setState(() {
      _kept = Set.unmodifiable(
        _kept.contains(maskId)
            ? ({..._kept}..remove(maskId))
            : {..._kept, maskId},
      );
    });
  }

  Future<void> _save() async {
    final result = _result;
    if (result == null || _kept.isEmpty) return;
    setState(() => _saving = true);
    try {
      final keptIds = result.masks
          .map((m) => m.id)
          .where(_kept.contains)
          .toList();
      final cutouts = await _proxy.cutout(
        imageId: result.imageId,
        maskIds: keptIds,
        style: _style,
        size: _size,
      );
      final labels = {for (final m in result.masks) m.id: m.label};
      final repository = await ref.read(scrapRepositoryProvider.future);
      final saved = await repository.saveCapture(
        photoJpeg: result.photoJpeg,
        cutouts: [for (final c in cutouts) c.withLabel(labels[c.maskId])],
      );
      ref.invalidate(scrapsProvider);
      if (mounted) Navigator.pop(context, saved.length);
    } on ProxyException catch (e) {
      _showMessage(e.message);
    } on FileSystemException {
      _showMessage(
        "Couldn't save to your device. Check free storage and try again.",
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
      appBar: AppBar(title: const Text('Review cutouts')),
      body: switch ((_result, _error)) {
        (_, final String error) => _ErrorView(
          message: error,
          onRetry: _segment,
        ),
        (null, _) => const _LoadingView(),
        (final SegmentResult result, _) => _buildReview(result),
      },
    );
  }

  Widget _buildReview(SegmentResult result) {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: PhotoWithMasks(
                  result: result,
                  kept: _kept,
                  onTapPhoto: _addAt,
                ),
              ),
            ),
          ),
          if (_adding) const LinearProgressIndicator(),
          Text(
            result.masks.isEmpty
                ? 'Tap an item to cut it out.'
                : 'Tap anything we missed to add it.',
            style: const TextStyle(color: Palette.inkSoft),
          ),
          const SizedBox(height: 8),
          _MaskChips(masks: result.masks, kept: _kept, onToggle: _toggle),
          _CutStylePicker(
            style: _style,
            size: _size,
            onStyle: (s) => setState(() => _style = s),
            onSize: (s) => setState(() => _size = s),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _kept.isEmpty || _saving ? null : _save,
                child: Text(
                  _saving
                      ? 'Cutting…'
                      : 'Save ${_kept.length} scrap${_kept.length == 1 ? '' : 's'}',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MaskChips extends StatelessWidget {
  const _MaskChips({
    required this.masks,
    required this.kept,
    required this.onToggle,
  });

  final List<MaskCandidate> masks;
  final Set<String> kept;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: [
        for (final (index, mask) in masks.indexed)
          FilterChip(
            label: Text('${index + 1}'),
            selected: kept.contains(mask.id),
            selectedColor: Palette.maskTints[index % Palette.maskTints.length]
                .withValues(alpha: 0.35),
            onSelected: (_) => onToggle(mask.id),
          ),
      ],
    );
  }
}

class _CutStylePicker extends StatelessWidget {
  const _CutStylePicker({
    required this.style,
    required this.size,
    required this.onStyle,
    required this.onSize,
  });

  final CutStyle style;
  final CutSize size;
  final ValueChanged<CutStyle> onStyle;
  final ValueChanged<CutSize> onSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<CutStyle>(
              segments: const [
                ButtonSegment(value: CutStyle.tight, label: Text('Tight')),
                ButtonSegment(value: CutStyle.sticker, label: Text('Sticker')),
                ButtonSegment(value: CutStyle.margin, label: Text('Margin')),
              ],
              selected: {style},
              showSelectedIcon: false,
              onSelectionChanged: (s) => onStyle(s.first),
            ),
          ),
          const SizedBox(width: 8),
          SegmentedButton<CutSize>(
            segments: const [
              ButtonSegment(value: CutSize.s, label: Text('S')),
              ButtonSegment(value: CutSize.m, label: Text('M')),
              ButtonSegment(value: CutSize.l, label: Text('L')),
            ],
            selected: {size},
            showSelectedIcon: false,
            // Border size only matters for sticker and margin cuts.
            onSelectionChanged: style == CutStyle.tight
                ? null
                : (s) => onSize(s.first),
          ),
        ],
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Finding your scraps…'),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
