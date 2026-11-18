import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/services/app_settings.dart';
import 'platform_info.dart';

/// Checks whether a channel/VOD group is locked by parental controls.
class ParentalGuard {
  ParentalGuard._();

  static const _adultKeywords = [
    'adult',
    'xxx',
    'porn',
    'erotic',
    '18+',
    'nsfw',
  ];

  static DateTime? _unlockedUntil;

  /// Whether parental controls are currently unlocked for the active session (15-min window).
  static bool get isSessionUnlocked {
    if (_unlockedUntil == null) return false;
    if (DateTime.now().isBefore(_unlockedUntil!)) {
      return true;
    }
    _unlockedUntil = null;
    return false;
  }

  /// Manually reset the session timer so PIN is re-prompted next time.
  static void resetSession() {
    _unlockedUntil = null;
  }

  static bool isLockedGroup(AppSettings settings, String? groupTitle) {
    if (!settings.parentalControlsEnabled) return false;
    if (settings.parentalPin.isEmpty) return false;
    final group = (groupTitle ?? '').trim();
    if (group.isEmpty) return false;

    final lower = group.toLowerCase();
    for (final locked in settings.lockedCategories) {
      if (lower.contains(locked.toLowerCase())) return true;
    }
    for (final kw in _adultKeywords) {
      if (lower.contains(kw)) return true;
    }
    return false;
  }

  /// Shows a PIN dialog. Returns true when unlocked (or controls off).
  /// Reuses a 15-minute temporary session unlock so users don't have to re-enter
  /// PIN on every stream or episode change.
  static Future<bool> unlockIfNeeded(
    BuildContext context,
    AppSettings settings, {
    String? groupTitle,
  }) async {
    if (!isLockedGroup(settings, groupTitle)) return true;
    if (isSessionUnlocked) return true;

    final ok = await requestPin(context, settings);
    if (ok) {
      // 15-minute grace period
      _unlockedUntil = DateTime.now().add(const Duration(minutes: 15));
    }
    return ok;
  }

  static Future<bool> requestPin(
    BuildContext context,
    AppSettings settings,
  ) async {
    if (!settings.parentalControlsEnabled || settings.parentalPin.isEmpty) {
      return true;
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _TvPinDialog(correctPin: settings.parentalPin),
    );

    if (ok != true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Incorrect PIN'),
          backgroundColor: Color(0xFFE84118),
          duration: Duration(seconds: 2),
        ),
      );
    }
    return ok == true;
  }
}

class _TvPinDialog extends StatefulWidget {
  final String correctPin;
  const _TvPinDialog({required this.correctPin});

  @override
  State<_TvPinDialog> createState() => _TvPinDialogState();
}

class _TvPinDialogState extends State<_TvPinDialog> {
  String _pin = '';
  bool _hasError = false;

  void _onDigit(String d) {
    if (_pin.length >= 4) return;
    setState(() {
      _hasError = false;
      _pin += d;
    });

    if (_pin.length == 4) {
      if (_pin == widget.correctPin) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _hasError = true);
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted) {
            setState(() {
              _pin = '';
              _hasError = false;
            });
          }
        });
      }
    }
  }

  void _onBackspace() {
    if (_pin.isNotEmpty) {
      setState(() {
        _hasError = false;
        _pin = _pin.substring(0, _pin.length - 1);
      });
    }
  }

  void _onClear() {
    setState(() {
      _hasError = false;
      _pin = '';
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      _onDigit('0');
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
      _onDigit('1');
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
      _onDigit('2');
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
      _onDigit('3');
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
      _onDigit('4');
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) {
      _onDigit('5');
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) {
      _onDigit('6');
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) {
      _onDigit('7');
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) {
      _onDigit('8');
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) {
      _onDigit('9');
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      _onBackspace();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop(false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildKeypadButton(String label, {VoidCallback? onTap, bool autofocus = false, IconData? icon}) {
    return SizedBox(
      width: 60,
      height: 48,
      child: OutlinedButton(
        autofocus: autofocus,
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFF2A2844)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ).copyWith(
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return const BorderSide(color: Colors.white, width: 2.2);
            }
            return const BorderSide(color: Color(0xFF2A2844));
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return const Color(0xFF6C5CE7).withValues(alpha: 0.4);
            }
            return const Color(0xFF16152B);
          }),
        ),
        child: icon != null
            ? Icon(icon, size: 18, color: Colors.white70)
            : Text(
                label,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Dialog(
        backgroundColor: const Color(0xFF131224),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Container(
          width: 320,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded, size: 36, color: Color(0xFF6C5CE7)),
              const SizedBox(height: 10),
              const Text(
                'Parental PIN Required',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Enter 4-digit PIN using remote or keypad',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
              const SizedBox(height: 18),

              // 4 PIN Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final filled = index < _pin.length;
                  final dotColor = _hasError
                      ? Colors.redAccent
                      : (filled ? const Color(0xFF6C5CE7) : Colors.white12);
                  final borderColor = _hasError
                      ? Colors.redAccent
                      : (filled ? const Color(0xFFA29BFE) : Colors.white30);

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dotColor,
                      border: Border.all(color: borderColor, width: 1.5),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 20),

              // On-Screen Keypad
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildKeypadButton('1', onTap: () => _onDigit('1'), autofocus: true),
                      _buildKeypadButton('2', onTap: () => _onDigit('2')),
                      _buildKeypadButton('3', onTap: () => _onDigit('3')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildKeypadButton('4', onTap: () => _onDigit('4')),
                      _buildKeypadButton('5', onTap: () => _onDigit('5')),
                      _buildKeypadButton('6', onTap: () => _onDigit('6')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildKeypadButton('7', onTap: () => _onDigit('7')),
                      _buildKeypadButton('8', onTap: () => _onDigit('8')),
                      _buildKeypadButton('9', onTap: () => _onDigit('9')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildKeypadButton('C', onTap: _onClear),
                      _buildKeypadButton('0', onTap: () => _onDigit('0')),
                      _buildKeypadButton('', onTap: _onBackspace, icon: Icons.backspace_outlined),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // Cancel button
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white60,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
