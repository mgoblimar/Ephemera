import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:ephemera_ai/config.dart';
import 'package:ephemera_ai/data/proxy_client.dart';
import 'package:ephemera_ai/features/blend/agent_layout.dart';
import 'package:ephemera_ai/features/blend/simple_layout.dart';
import 'package:ephemera_ai/features/editor/editor_screen.dart';
import 'package:ephemera_ai/models/blend_plan.dart';
import 'package:ephemera_ai/models/journal.dart';
import 'package:ephemera_ai/models/scrap.dart';
import 'package:ephemera_ai/providers.dart';
import 'package:ephemera_ai/theme.dart';

const _progressMessages = [
  'Searching your archive…',
  'Trying a few phrasings…',
  'Picking scraps that belong together…',
  'Choosing a palette…',
  'Writing captions…',
];
const _progressStep = Duration(seconds: 3);

/// Theme Blend (SPEC 4.6): type a theme, review the agent's plan, then build
/// a new page from it in [journal].
class ThemeBlendScreen extends ConsumerStatefulWidget {
  const ThemeBlendScreen({super.key, required this.journal});

  final Journal journal;

  @override
  ConsumerState<ThemeBlendScreen> createState() => _ThemeBlendScreenState();
}

class _ThemeBlendScreenState extends ConsumerState<ThemeBlendScreen> {
  final _theme = TextEditingController();
  BlendPlan? _plan;
  Set<String> _dropped = const {};

  /// Indexes of the plan's decorations the user turned off.
  Set<int> _skippedDecorations = const {};
  bool _planning = false;

  /// What Build is doing right now, or null when idle.
  String? _buildStep;
  String? _error;
  int _progress = 0;
  Timer? _ticker;
  static const _uuid = Uuid();

  @override
  void dispose() {
    _theme.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _makePlan() async {
    final theme = _theme.text.trim();
    if (theme.isEmpty) {
      setState(
        () => _error =
            'Describe a theme first, e.g. "slow Sunday café, warm browns"',
      );
      return;
    }
    final archive = await ref.read(scrapsProvider.future);
    if (!mounted) return;
    if (archive.isEmpty) {
      setState(() => _error = 'Your archive is empty. Scan some scraps first.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _planning = true;
      _error = null;
      _progress = 0;
    });
    _ticker = Timer.periodic(_progressStep, (_) {
      if (mounted) {
        setState(() => _progress = (_progress + 1) % _progressMessages.length);
      }
    });
    try {
      final plan = await ref
          .read(proxyClientProvider)
          .agentPlan(theme: theme, archive: _offeredToAgent(archive));
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _dropped = const {};
        _skippedDecorations = const {};
        if (plan.scraps.isEmpty) {
          _error = 'No scraps matched that theme. Try other words.';
        }
      });
    } on ProxyException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      _ticker?.cancel();
      if (mounted) setState(() => _planning = false);
    }
  }

  /// Leaves out slivers and specks that would look broken on a page, unless
  /// that would leave the agent nothing to work with.
  static List<Scrap> _offeredToAgent(List<Scrap> archive) {
    final usable = archive.where((s) => !s.tooWeakForAgent).toList();
    return usable.isEmpty ? archive : usable;
  }

  Future<void> _build(BlendPlan plan, Map<String, Scrap> byId) async {
    final scraps = [
      for (final s in plan.scraps)
        if (!_dropped.contains(s.id) && byId[s.id] != null) byId[s.id]!,
    ];
    final decorations = [
      for (final (i, e) in plan.ephemera.indexed)
        if (!_skippedDecorations.contains(i)) e,
    ];
    if (decorations.isNotEmpty) {
      setState(
        () => _buildStep =
            'Making ${decorations.length} decoration${decorations.length == 1 ? '' : 's'}…',
      );
      scraps.addAll(await _makeDecorations(plan, decorations));
      if (!mounted) return;
    }
    setState(() => _buildStep = 'Arranging your page…');
    final page = await _arrange(plan, scraps);
    if (!mounted) return;
    final journal = widget.journal.withPages([...widget.journal.pages, page]);
    try {
      final repository = await ref.read(journalRepositoryProvider.future);
      await repository.save(journal);
    } on FileSystemException {
      if (mounted) {
        setState(() {
          _buildStep = null;
          _error = "Couldn't save the new page. Check free storage.";
        });
      }
      return;
    }
    ref.invalidate(journalsProvider);
    if (!mounted) return;
    setState(() => _buildStep = null);
    unawaited(
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => EditorScreen(journal: journal, pageId: page.id),
        ),
      ),
    );
  }

  /// Muse Image makes the decorations side by side; each one is saved to the
  /// archive. One that fails is skipped (and counted) so the page still builds.
  Future<List<Scrap>> _makeDecorations(
    BlendPlan plan,
    List<({String kind, String prompt})> decorations,
  ) async {
    final proxy = ref.read(proxyClientProvider);
    final repository = await ref.read(scrapRepositoryProvider.future);
    final results = await Future.wait([
      for (final d in decorations)
        proxy
            .generateEphemera(
              kind: d.kind,
              prompt: d.prompt,
              palette: plan.palette,
            )
            .then<Scrap?>(repository.saveGenerated)
            .catchError(
              (Object _) => null,
              test: (e) => e is ProxyException || e is FileSystemException,
            ),
    ]);
    ref.invalidate(scrapsProvider);
    final made = results.whereType<Scrap>().toList();
    final failed = decorations.length - made.length;
    if (failed > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "$failed decoration${failed == 1 ? '' : 's'} couldn't be made; built without ${failed == 1 ? 'it' : 'them'}.",
          ),
        ),
      );
    }
    return made;
  }

  /// The agent arranges the page; if that fails, the simple cascade keeps
  /// Build working (and says so).
  Future<JournalPage> _arrange(BlendPlan plan, List<Scrap> scraps) async {
    final pageId = _uuid.v4();
    final paper = paperFromName(plan.paper);
    try {
      final layout = await ref
          .read(proxyClientProvider)
          .agentLayout(plan: plan, scraps: scraps);
      return pageFromAgentLayout(
        pageId: pageId,
        layout: layout,
        scraps: scraps,
        paper: paper,
      );
    } on ProxyException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't reach the designer; used a simple layout."),
          ),
        );
      }
      return simpleLayout(
        pageId: pageId,
        scraps: scraps,
        captions: plan.captions,
        paper: paper,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final byId = {
      for (final s in ref.watch(scrapsProvider).valueOrNull ?? const <Scrap>[])
        s.id: s,
    };
    final plan = _plan;
    return Scaffold(
      appBar: AppBar(title: const Text('Theme Blend')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text('What should this page feel like?', style: tokens.display(20)),
            const SizedBox(height: 12),
            TextField(
              controller: _theme,
              enabled: !_planning,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _makePlan(),
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                hintText: 'Slow Sunday café, warm browns',
                errorText: _error,
                errorMaxLines: 3,
                filled: true,
                fillColor: tokens.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(tokens.cardRadius),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _planning ? null : _makePlan,
              icon: const Icon(Icons.auto_awesome),
              label: Text(plan == null ? 'Plan a page' : 'Plan again'),
            ),
            const SizedBox(height: 24),
            if (_planning)
              _Planning(message: _progressMessages[_progress])
            else if (plan != null && plan.scraps.isNotEmpty)
              PlanCards(
                plan: plan,
                byId: byId,
                dropped: _dropped,
                onToggle: (id) => setState(() {
                  _dropped = Set.unmodifiable(
                    _dropped.contains(id)
                        ? (Set.of(_dropped)..remove(id))
                        : {..._dropped, id},
                  );
                }),
                skippedDecorations: _skippedDecorations,
                onToggleDecoration: (i) => setState(() {
                  _skippedDecorations = Set.unmodifiable(
                    _skippedDecorations.contains(i)
                        ? (Set.of(_skippedDecorations)..remove(i))
                        : {..._skippedDecorations, i},
                  );
                }),
                buildStep: _buildStep,
                onBuild: () => _build(plan, byId),
              ),
          ],
        ),
      ),
    );
  }
}

class _Planning extends StatelessWidget {
  const _Planning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      children: [
        CircularProgressIndicator(color: tokens.accent),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            message,
            key: ValueKey(message),
            style: tokens.hand(24, color: tokens.inkSoft),
          ),
        ),
      ],
    );
  }
}

/// The plan as cards: title, palette, chosen scraps (tap to drop), captions.
class PlanCards extends StatelessWidget {
  const PlanCards({
    super.key,
    required this.plan,
    required this.byId,
    required this.dropped,
    required this.onToggle,
    required this.onBuild,
    this.skippedDecorations = const {},
    this.onToggleDecoration,
    this.buildStep,
  });

  final BlendPlan plan;

  /// What Build is doing (shown on the button), or null when idle.
  final String? buildStep;
  final Set<int> skippedDecorations;
  final ValueChanged<int>? onToggleDecoration;
  final Map<String, Scrap> byId;
  final Set<String> dropped;
  final ValueChanged<String> onToggle;
  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final kept = plan.scraps.where((s) => !dropped.contains(s.id)).length;
    final decorations = plan.ephemera.length - skippedDecorations.length;
    final building = buildStep != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(plan.title, style: tokens.display(26)),
        const SizedBox(height: 4),
        Text(
          '${plan.paper} paper · ${plan.toolCalls} archive searches',
          style: TextStyle(color: tokens.inkSoft),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final hex in plan.palette)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: CircleAvatar(radius: 14, backgroundColor: _color(hex)),
              ),
          ],
        ),
        if (plan.layoutIntent.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            plan.layoutIntent,
            style: TextStyle(color: tokens.ink, height: 1.4),
          ),
        ],
        const SizedBox(height: 16),
        for (final s in plan.scraps)
          _PlanScrapRow(
            scrap: byId[s.id],
            reason: s.reason,
            kept: !dropped.contains(s.id),
            onTap: () => onToggle(s.id),
          ),
        if (plan.captions.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final caption in plan.captions)
            Text('“$caption”', style: tokens.hand(24)),
        ],
        if (plan.ephemera.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Decorations to make', style: tokens.display(18)),
          const SizedBox(height: 8),
          for (final (i, e) in plan.ephemera.indexed)
            DecorationRow(
              kind: e.kind,
              prompt: e.prompt,
              kept: !skippedDecorations.contains(i),
              onTap: onToggleDecoration == null
                  ? null
                  : () => onToggleDecoration!(i),
            ),
          Text(
            decorations == 0
                ? 'No decorations: nothing extra to pay'
                : '$decorations decoration${decorations == 1 ? '' : 's'} · ≈₱${(decorations * decorationCostPesos).toStringAsFixed(2)}',
            style: TextStyle(color: tokens.inkSoft),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: kept == 0 || building ? null : onBuild,
            child: Text(
              buildStep ??
                  'Build page with $kept scrap${kept == 1 ? '' : 's'}'
                      '${decorations > 0 ? ' + $decorations decoration${decorations == 1 ? '' : 's'}' : ''}',
            ),
          ),
        ),
      ],
    );
  }

  static Color _color(String hex) =>
      Color(int.parse('FF${hex.substring(1)}', radix: 16));
}

class _PlanScrapRow extends StatelessWidget {
  const _PlanScrapRow({
    required this.scrap,
    required this.reason,
    required this.kept,
    required this.onTap,
  });

  final Scrap? scrap;
  final String reason;
  final bool kept;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final path = scrap?.pngPath;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(tokens.cardRadius),
          onTap: onTap,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: kept ? 1 : 0.4,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 64,
                    child: path == null
                        ? null
                        : Image.file(
                            File(path),
                            fit: BoxFit.contain,
                            cacheWidth: 192,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      reason.isEmpty ? (scrap?.type ?? 'scrap') : reason,
                      style: TextStyle(color: tokens.ink),
                    ),
                  ),
                  Icon(
                    kept ? Icons.check_circle : Icons.circle_outlined,
                    color: kept ? tokens.accent : tokens.inkSoft,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One decoration the agent wants made: its kind, the prompt, and a toggle.
class DecorationRow extends StatelessWidget {
  const DecorationRow({
    super.key,
    required this.kind,
    required this.prompt,
    required this.kept,
    this.onTap,
  });

  static const _icons = {
    'stamp': Icons.local_post_office_outlined,
    'tape': Icons.straighten,
    'label': Icons.label_outline,
    'ticket': Icons.confirmation_number_outlined,
    'sticker': Icons.star_outline,
  };

  final String kind;
  final String prompt;
  final bool kept;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(tokens.cardRadius),
          onTap: onTap,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: kept ? 1 : 0.4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    _icons[kind] ?? Icons.auto_awesome,
                    color: tokens.secondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$kind  ',
                            style: TextStyle(
                              color: tokens.ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text: prompt,
                            style: TextStyle(color: tokens.inkSoft),
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    kept ? Icons.check_circle : Icons.circle_outlined,
                    color: kept ? tokens.accent : tokens.inkSoft,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
