import 'package:ephemera_ai/models/journal.dart';

/// Undo/redo over immutable page snapshots.
class PageHistory {
  const PageHistory._(this.current, this._undo, this._redo);

  factory PageHistory.start(JournalPage page) =>
      PageHistory._(page, const [], const []);

  /// Kept generous; snapshots share element objects, so they're cheap.
  static const limit = 100;

  final JournalPage current;
  final List<JournalPage> _undo;
  final List<JournalPage> _redo;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Records [page] as a new step; clears the redo stack.
  PageHistory push(JournalPage page) {
    if (identical(page, current)) return this;
    final undo = [..._undo, current];
    final trimmed = undo.length > limit
        ? undo.sublist(undo.length - limit)
        : undo;
    return PageHistory._(page, List.unmodifiable(trimmed), const []);
  }

  PageHistory undo() {
    if (!canUndo) return this;
    return PageHistory._(
      _undo.last,
      List.unmodifiable(_undo.sublist(0, _undo.length - 1)),
      List.unmodifiable([..._redo, current]),
    );
  }

  PageHistory redo() {
    if (!canRedo) return this;
    return PageHistory._(
      _redo.last,
      List.unmodifiable([..._undo, current]),
      List.unmodifiable(_redo.sublist(0, _redo.length - 1)),
    );
  }
}
