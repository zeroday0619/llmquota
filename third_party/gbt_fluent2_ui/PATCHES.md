# Local compatibility patch

This directory contains gbt_fluent2_ui 7.0.0 source from pub.dev under its original MIT license. The application uses this copy through a dependency override because the upstream ThemeData subclass does not compile against Flutter 3.47.

Theme compatibility changes in `lib/src/fluent_with_material/mixed_fluent_theme.dart`:

- Accept both legacy theme wrappers and current data objects for app bar and input decoration themes, including `copyWith`, and pass normalized data to `ThemeData.raw`.
- Use `BottomAppBarThemeData` for bottom app bar themes.
- Accept and preserve `CarouselViewThemeData` in construction, copying, and raw construction.

Button layout changes in `lib/src/components/fluent_components/fluent_button/` allow button titles to wrap under constrained width and larger text scaling. Icon-only actions omit the empty title and title spacing to preserve their constrained hit area. Small and medium button labels use the application label typography instead of the caption ramp. Subtle buttons honor the provided foreground color so the app can apply neutral resting icons and accessible focus/disabled states.

Remove the override after an upstream release includes equivalent compatibility fixes and passes the application test suite.
