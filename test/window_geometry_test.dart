import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llmquota/window_geometry.dart';

void main() {
  test('same content refresh preserves manually resized dimensions', () {
    expect(
      updatedOverlaySize(
        current: const Size(900, 700),
        content: const Size(380, 400),
        previousContent: const Size(380, 400),
        display: const Size(1920, 1080),
      ),
      const Size(900, 700),
    );
  });

  test(
    'new content adjusts height while preserving manually selected width',
    () {
      expect(
        updatedOverlaySize(
          current: const Size(900, 700),
          content: const Size(380, 500),
          previousContent: const Size(380, 400),
          display: const Size(1920, 1080),
        ),
        const Size(900, 500),
      );
    },
  );

  test('HUD transitions can explicitly restore mode width', () {
    expect(
      updatedOverlaySize(
        current: const Size(900, 700),
        content: const Size(320, 300),
        previousContent: const Size(380, 400),
        display: const Size(640, 480),
        force: true,
        resetWidth: true,
      ),
      const Size(320, 300),
    );
  });

  test('default windows fit a small logical display with chrome margins', () {
    expect(
      constrainOverlaySize(const Size(380, 800), const Size(640, 480)),
      const Size(380, 416),
    );
    expect(
      constrainOverlaySize(const Size(320, 600), const Size(320, 240)),
      const Size(296, 176),
    );
  });

  test('wide user selected dimensions remain intact on larger displays', () {
    expect(
      constrainOverlaySize(const Size(1200, 720), const Size(1920, 1080)),
      const Size(1200, 720),
    );
  });

  test('minimum window dimensions cannot exceed the available display', () {
    expect(
      overlayMinimumSize(const Size(320, 240), hud: false),
      const Size(296, 176),
    );
    expect(
      overlayMinimumSize(const Size(320, 240), hud: true),
      const Size(280, 140),
    );
    expect(overlayMinimumSize(const Size(1, 1), hud: false), const Size(1, 1));
  });

  test('standard minimum dimensions remain unchanged on normal displays', () {
    expect(
      overlayMinimumSize(const Size(1920, 1080), hud: false),
      const Size(340, 260),
    );
    expect(
      overlayMinimumSize(const Size(1920, 1080), hud: true),
      const Size(280, 140),
    );
  });
}
