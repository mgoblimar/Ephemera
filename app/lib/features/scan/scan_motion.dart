import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:ephemera_ai/theme.dart';

bool _reducedMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// A soft light band sweeping across [child] while something loads.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reducedMotion(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value * 3 - 1; // band travels from -1 to 2
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.45),
              Colors.white.withValues(alpha: 0),
            ],
            stops: [
              t - 0.25,
              t,
              t + 0.25,
            ].map((s) => s.clamp(0.0, 1.0)).toList(),
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}

/// Fades and scales [child] in, [index] steps after its siblings.
class PopIn extends StatelessWidget {
  const PopIn({super.key, required this.index, required this.child});

  static const _step = 60;
  static const _base = 260;
  static const _maxStagger = 8;

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (_reducedMotion(context)) return child;
    final delay = math.min(index, _maxStagger) * _step;
    final total = _base + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutBack),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.8 + 0.2 * t, child: child),
      ),
    );
  }
}

/// The freshly cut scraps dropping onto a sheet of paper, then [onDone].
/// Tapping skips ahead.
class CutReveal extends StatefulWidget {
  const CutReveal({super.key, required this.pngs, required this.onDone});

  final List<Uint8List> pngs;
  final VoidCallback onDone;

  @override
  State<CutReveal> createState() => _CutRevealState();
}

class _CutRevealState extends State<CutReveal>
    with SingleTickerProviderStateMixin {
  static const _shown = 12;
  late final AnimationController _controller;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.isCompleted) return;
    if (_reducedMotion(context)) _controller.value = 0.7;
    _controller.forward().whenComplete(_finish);
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final pngs = widget.pngs.take(_shown).toList();
    final count = widget.pngs.length;
    return GestureDetector(
      onTap: _finish,
      behavior: HitTestBehavior.opaque,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.35),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(20),
            constraints: const BoxConstraints(maxWidth: 520),
            decoration: BoxDecoration(
              color: tokens.paper,
              borderRadius: BorderRadius.circular(tokens.cardRadius),
              boxShadow: tokens.shadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Cut out $count scrap${count == 1 ? '' : 's'}!',
                  style: tokens.display(22),
                ),
                const SizedBox(height: 16),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final (i, png) in pngs.indexed)
                        _drop(i, pngs.length, png),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Saved to your archive',
                  style: tokens.hand(20, color: tokens.inkSoft),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Each scrap falls in from above with a little spin, one after another.
  Widget _drop(int i, int n, Uint8List png) {
    final start = 0.5 * i / math.max(n, 1);
    final t = Curves.easeOutBack.transform(
      ((_controller.value - start) / 0.3).clamp(0.0, 1.0),
    );
    final tilt = (math.Random(i).nextDouble() * 2 - 1) * 0.15;
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, (1 - t) * -40),
        child: Transform.rotate(
          angle: tilt + (1 - t) * 0.4,
          child: Image.memory(png, width: 84, height: 84, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
