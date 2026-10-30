import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:ephemera_ai/features/blend/theme_blend_screen.dart';
import 'package:ephemera_ai/features/editor/editor_screen.dart';
import 'package:ephemera_ai/features/editor/page_canvas.dart';
import 'package:ephemera_ai/models/journal.dart';
import 'package:ephemera_ai/providers.dart';
import 'package:ephemera_ai/theme.dart';

const _perspective = 0.0012;
const _flipAngle = math.pi / 2.2; // how far a page turns before the next shows

/// A journal as a book: swipe to turn pages (3D flip), tap a page to edit it.
class BookScreen extends ConsumerStatefulWidget {
  const BookScreen({super.key, required this.journalId});

  final String journalId;

  @override
  ConsumerState<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends ConsumerState<BookScreen> {
  final _controller = PageController();
  int _index = 0;
  static const _uuid = Uuid();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _addPage(Journal journal) async {
    final page = JournalPage(id: _uuid.v4());
    final updated = journal.withPages([...journal.pages, page]);
    final repository = await ref.read(journalRepositoryProvider.future);
    await repository.save(updated);
    ref.invalidate(journalsProvider);
    if (!mounted) return;
    _edit(updated, page.id);
  }

  void _edit(Journal journal, String pageId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditorScreen(journal: journal, pageId: pageId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final journals = ref.watch(journalsProvider);
    final journal = journals.valueOrNull
        ?.where((j) => j.id == widget.journalId)
        .firstOrNull;
    if (journal == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final pageCount = journal.pages.length;
    final paper = context.tokens.paper;
    return Scaffold(
      backgroundColor: Color(journal.coverColor),
      appBar: AppBar(
        title: Text(journal.title, style: TextStyle(color: paper)),
        backgroundColor: Color(journal.coverColor),
        foregroundColor: paper,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ThemeBlendScreen(journal: journal),
              ),
            ),
            style: TextButton.styleFrom(foregroundColor: paper),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Theme Blend'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pageCount + 1, // + the "add page" leaf
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _FlipLeaf(
                  controller: _controller,
                  index: i,
                  child: i == pageCount
                      ? _AddPageLeaf(onTap: () => _addPage(journal))
                      : GestureDetector(
                          onTap: () => _edit(journal, journal.pages[i].id),
                          child: JournalPageCanvas(page: journal.pages[i]),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _index < pageCount
                    ? 'Page ${_index + 1} of $pageCount · tap to edit'
                    : 'Add a page',
                style: TextStyle(color: paper),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rotates a page around its left edge (the spine) as it is swiped away.
class _FlipLeaf extends StatelessWidget {
  const _FlipLeaf({
    required this.controller,
    required this.index,
    required this.child,
  });

  final PageController controller;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final page = controller.hasClients && controller.position.haveDimensions
            ? controller.page ?? controller.initialPage.toDouble()
            : controller.initialPage.toDouble();
        final offset = (index - page).clamp(-1.0, 1.0);
        // Pages leaving to the left turn over the spine; incoming ones sit flat.
        final angle = offset < 0 ? offset * -_flipAngle : 0.0;
        final transform = Matrix4.identity()
          ..setEntry(3, 2, _perspective)
          ..rotateY(-angle);
        return Opacity(
          opacity: offset < 0 ? (1 + offset).clamp(0.0, 1.0) : 1.0,
          child: Transform(
            alignment: Alignment.centerLeft,
            transform: transform,
            child: child,
          ),
        );
      },
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 16,
                  offset: Offset(4, 6),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _AddPageLeaf extends StatelessWidget {
  const _AddPageLeaf({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AspectRatio(
      aspectRatio: 1 / pageAspect,
      child: Material(
        color: tokens.paper,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.note_add_outlined, size: 40, color: tokens.inkSoft),
                const SizedBox(height: 8),
                Text('Add a page', style: TextStyle(color: tokens.inkSoft)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
