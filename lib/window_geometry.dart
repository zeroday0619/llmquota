import 'dart:math' as math;

import 'package:flutter/widgets.dart';

// Flutter exposes display bounds rather than the operating system work area.
// These margins leave room for window chrome without adding a screen plugin.
Size availableOverlaySize(Size displaySize) => Size(
  math.max(1, displaySize.width - 24),
  math.max(1, displaySize.height - 64),
);

Size constrainOverlaySize(Size requested, Size displaySize) {
  final available = availableOverlaySize(displaySize);
  return Size(
    requested.width.clamp(1, available.width).toDouble(),
    requested.height.clamp(1, available.height).toDouble(),
  );
}

Size updatedOverlaySize({
  required Size current,
  required Size content,
  required Size previousContent,
  required Size display,
  bool force = false,
  bool resetWidth = false,
}) {
  final requested = !force && content == previousContent
      ? current
      : Size(resetWidth ? content.width : current.width, content.height);
  return constrainOverlaySize(requested, display);
}

Size overlayMinimumSize(Size displaySize, {required bool hud}) =>
    constrainOverlaySize(
      hud ? const Size(280, 140) : const Size(340, 260),
      displaySize,
    );
