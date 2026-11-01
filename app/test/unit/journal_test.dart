import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ephemera_ai/data/journal_repository.dart';
import 'package:ephemera_ai/features/editor/page_history.dart';
import 'package:ephemera_ai/models/journal.dart';

PageElement _text(String id, {double cx = 0.5}) => PageElement(
  id: id,
  kind: ElementKind.text,
  cx: cx,
  cy: 0.5,
  size: 0.07,
  text: id,
);

void main() {
  group('JournalPage', () {
    test('reordering moves an element one step and clamps at the ends', () {
      final page = const JournalPage(
        id: 'p',
      ).withElements([_text('a'), _text('b'), _text('c')]);

      expect(page.reordering('a', 1).elements.map((e) => e.id), [
        'b',
        'a',
        'c',
      ]);
      expect(page.reordering('c', 1).elements.map((e) => e.id), [
        'a',
        'b',
        'c',
      ]);
      expect(page.reordering('a', -1), same(page));
    });

    test('edits return new pages and leave the original untouched', () {
      final page = const JournalPage(id: 'p').adding(_text('a'));

      final moved = page.replacing(_text('a', cx: 0.9));

      expect(moved.element('a')!.cx, 0.9);
      expect(page.element('a')!.cx, 0.5);
      expect(page.removing('a').elements, isEmpty);
    });

    test('journal JSON round-trips pages and elements', () {
      final page = const JournalPage(id: 'p', paper: PaperStyle.kraft).adding(
        const PageElement(
          id: 's',
          kind: ElementKind.scrap,
          cx: 0.3,
          cy: 0.4,
          size: 0.42,
          rotation: 0.1,
          scrapId: 'scrap1',
          imagePath: '/a.png',
          imageAspect: 1.5,
        ),
      );
      final journal = Journal(
        id: 'j',
        title: 'Kyoto',
        createdAt: DateTime.utc(2026, 10, 30),
        pages: [page],
      );

      final back = Journal.fromJson(journal.toJson());

      expect(back.toJson(), journal.toJson());
      expect(back.pages.single.paper, PaperStyle.kraft);
    });
  });

  group('PageHistory', () {
    final empty = const JournalPage(id: 'p');

    test('undo and redo walk back and forth through steps', () {
      final one = empty.adding(_text('a'));
      final two = one.adding(_text('b'));
      var history = PageHistory.start(empty).push(one).push(two);

      history = history.undo();
      expect(history.current, same(one));
      history = history.undo();
      expect(history.current, same(empty));
      expect(history.canUndo, isFalse);
      history = history.redo().redo();
      expect(history.current, same(two));
      expect(history.canRedo, isFalse);
    });

    test('a new step after undo clears redo', () {
      final one = empty.adding(_text('a'));
      final other = empty.adding(_text('z'));

      final history = PageHistory.start(empty).push(one).undo().push(other);

      expect(history.canRedo, isFalse);
      expect(history.current, same(other));
    });

    test('keeps at most the history limit of undo steps', () {
      var history = PageHistory.start(empty);
      for (var i = 0; i < PageHistory.limit + 20; i++) {
        history = history.push(empty.adding(_text('e$i')));
      }
      var undos = 0;
      while (history.canUndo) {
        history = history.undo();
        undos++;
      }
      expect(undos, PageHistory.limit);
    });
  });

  group('FileJournalRepository', () {
    late Directory root;

    setUp(() async => root = await Directory.systemTemp.createTemp('journals'));
    tearDown(() async => root.delete(recursive: true));

    test(
      'create starts a journal with one blank page and persists it',
      () async {
        final repository = FileJournalRepository(root);

        final journal = await repository.create('Kyoto');

        expect(journal.pages, hasLength(1));
        final all = await FileJournalRepository(root).getAll();
        expect(all.single.title, 'Kyoto');
      },
    );

    test('save replaces the journal and delete removes it', () async {
      final repository = FileJournalRepository(root);
      final journal = await repository.create('Kyoto');
      final edited = journal.replacingPage(
        journal.pages.single.adding(_text('hello')),
      );

      await repository.save(edited);
      expect(
        (await repository.getAll()).single.pages.single.elements.single.text,
        'hello',
      );

      await repository.delete(journal.id);
      expect(await repository.getAll(), isEmpty);
    });
  });

  test(
    'book style and background survive a save, and old journals default',
    () {
      final journal = Journal(
        id: 'j',
        title: 'Kyoto',
        createdAt: DateTime.utc(2026, 11, 1),
      ).withLook(binding: BookBinding.notebook, backdrop: BookBackdrop.cork);

      final loaded = Journal.fromJson(journal.toJson());
      expect(loaded.binding, BookBinding.notebook);
      expect(loaded.backdrop, BookBackdrop.cork);
      expect(loaded.withPages(const []).binding, BookBinding.notebook);

      final old = Journal.fromJson({
        'id': 'o',
        'title': 'Old',
        'created_at': '2026-10-30T00:00:00Z',
      });
      expect(old.binding, BookBinding.book);
      expect(old.backdrop, BookBackdrop.cover);
    },
  );
}
