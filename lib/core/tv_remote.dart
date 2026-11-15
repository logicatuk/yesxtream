import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'platform_info.dart';

/// OK / Select on Samsung, LG, and Fire TV remotes.
///
/// Fire Stick sends DPAD center (`select`) or gamepad A. Samsung and LG send
/// Enter. Some firmware also reports numpad enter.
bool tvIsOkKey(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.gameButtonA;
}

/// True when [pixels] already keeps a child fully inside the viewport.
///
/// [revealAtStart] is the scroll offset that pins the child to the leading
/// edge. [revealAtEnd] pins it to the trailing edge. Any offset between those
/// two leaves the child on screen.
bool tvScrollOffsetKeepsChildVisible({
  required double pixels,
  required double revealAtStart,
  required double revealAtEnd,
  double slack = 4,
}) {
  final minOff = math.min(revealAtStart, revealAtEnd);
  final maxOff = math.max(revealAtStart, revealAtEnd);
  return pixels >= minOff - slack && pixels <= maxOff + slack;
}

/// TV scroll behavior without the glowing overscroll shader, which is
/// expensive on webOS and Tizen GPUs.
class TvScrollBehavior extends MaterialScrollBehavior {
  const TvScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

/// Keeps the D-pad highlight on screen and caps image memory on TVs.
class TvFocusFollower {
  TvFocusFollower._();

  static bool _installed = false;
  static bool _scheduled = false;
  static bool _cacheTuned = false;

  static void install() {
    if (_installed) return;
    _installed = true;
    FocusManager.instance.addListener(_onFocusChange);
  }

  static void tuneImageCache() {
    if (_cacheTuned || !PlatformInfo.isTV) return;
    _cacheTuned = true;
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSize = 60;
    cache.maximumSizeBytes = 32 * 1024 * 1024;
  }

  static void _onFocusChange() {
    if (!PlatformInfo.isTV || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _keepFocusedVisible();
    });
  }

  static void _keepFocusedVisible() {
    if (!PlatformInfo.isTV) return;
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null || !context.mounted) return;
    if (context.widget is EditableText) return;
    if (context.findAncestorWidgetOfExactType<EditableText>() != null) return;

    try {
      final scrollable = Scrollable.maybeOf(context);
      if (scrollable == null || !scrollable.position.hasContentDimensions) {
        return;
      }
      final render = context.findRenderObject();
      if (render is! RenderBox || !render.attached || !render.hasSize) return;
      final viewport = RenderAbstractViewport.maybeOf(render);
      if (viewport == null) return;

      final position = scrollable.position;
      final revealStart = viewport.getOffsetToReveal(render, 0.0).offset;
      final revealEnd = viewport.getOffsetToReveal(render, 1.0).offset;
      if (tvScrollOffsetKeepsChildVisible(
        pixels: position.pixels,
        revealAtStart: revealStart,
        revealAtEnd: revealEnd,
      )) {
        return;
      }

      final target = viewport
          .getOffsetToReveal(render, 0.35)
          .offset
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((target - position.pixels).abs() < 1) return;
      position.jumpTo(target);
    } catch (_) {}
  }
}
