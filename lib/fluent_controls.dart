import 'package:flutter/material.dart';
import 'package:gbt_fluent2_ui/gbt_fluent2_ui.dart';

/// Keeps Fluent icon actions accessible within compact desktop toolbars.
class FluentActionButton extends StatelessWidget {
  const FluentActionButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final Icon icon;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      label: tooltip,
      child: SizedBox(
        width: 36,
        height: 36,
        child: FluentButton(
          title: '',
          icon: Icon(icon.icon, size: 20, color: icon.color),
          onPressed: onPressed,
          size: FluentButtonSize.small,
          variant: FluentButtonVariant.subtle,
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            final colors = Theme.of(context).colorScheme;
            if (states.contains(WidgetState.disabled))
              return colors.onSurface.withValues(alpha: 0.38);
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused))
              return colors.primary;
            return icon.color ?? colors.onSurfaceVariant;
          }),
        ),
      ),
    ),
  );
}
