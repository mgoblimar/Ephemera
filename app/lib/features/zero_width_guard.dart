import 'package:flutter/widgets.dart';

/// Renders nothing while the available width is zero. Grids assert on a zero
/// cross-axis extent, which some Android page transitions briefly produce.
class ZeroWidthGuard extends StatelessWidget {
  const ZeroWidthGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth <= 0 ? const SizedBox.shrink() : child,
    );
  }
}
