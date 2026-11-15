import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/services/app_settings.dart';

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
  static Future<bool> unlockIfNeeded(
    BuildContext context,
    AppSettings settings, {
    String? groupTitle,
  }) async {
    if (!isLockedGroup(settings, groupTitle)) return true;
    return requestPin(context, settings);
  }

  static Future<bool> requestPin(
    BuildContext context,
    AppSettings settings,
  ) async {
    if (!settings.parentalControlsEnabled || settings.parentalPin.isEmpty) {
      return true;
    }
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A192A),
          title: const Text('Parental PIN'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 4,
            autofocus: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Enter 4-digit PIN',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) {
              final pin = controller.text.trim();
              Navigator.pop(ctx, pin == settings.parentalPin);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              autofocus: true,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6C5CE7),
              ),
              onPressed: () {
                final pin = controller.text.trim();
                Navigator.pop(ctx, pin == settings.parentalPin);
              },
              child: const Text('Unlock'),
            ),
          ],
        );
      },
    );
    controller.dispose();
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
