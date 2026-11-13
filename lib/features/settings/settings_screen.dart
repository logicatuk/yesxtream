import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/countdown_snackbar.dart';
import '../../data/datasources/local/database.dart' as db;
import '../../data/services/app_settings.dart';
import '../../data/services/app_update_service.dart';
import '../../data/services/device_identity_service.dart';
import '../../data/services/playback_history_service.dart';
import '../player/player_service.dart';
import '../providers/provider_manager.dart';

enum SettingsGroup {
  general('General', Icons.tune_rounded),
  playback('Playback', Icons.play_circle_outline_rounded),
  audioSubtitles('Audio/subtitles', Icons.subtitles_rounded),
  liveTvGuide('Live TV / Guide', Icons.live_tv_rounded),
  parentalControls('Parental controls', Icons.lock_outline_rounded),
  deviceLicense('Device / License', Icons.devices_rounded),
  privacy('Privacy', Icons.shield_outlined),
  helpAbout('Help / About', Icons.help_outline_rounded);

  final String label;
  final IconData icon;
  const SettingsGroup(this.label, this.icon);
}

class SettingsScreen extends ConsumerStatefulWidget {
  final SettingsGroup initialGroup;

  const SettingsScreen({
    super.key,
    this.initialGroup = SettingsGroup.general,
  });

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late SettingsGroup _selectedGroup;
  bool _keyRevealed = false;

  @override
  void initState() {
    super.initState();
    _selectedGroup = widget.initialGroup;
  }

  String _getGroupLabel(SettingsGroup group, AppSettings settings) {
    switch (group) {
      case SettingsGroup.general:
        return settings.tr('general_settings');
      case SettingsGroup.playback:
        return settings.tr('player_settings');
      case SettingsGroup.audioSubtitles:
        return '${settings.tr('audio_track')} / ${settings.tr('subtitle_track')}';
      case SettingsGroup.liveTvGuide:
        return settings.tr('nav_live');
      case SettingsGroup.parentalControls:
        return settings.tr('parental_controls');
      case SettingsGroup.deviceLicense:
        return 'Device / License';
      case SettingsGroup.privacy:
        return 'Privacy';
      case SettingsGroup.helpAbout:
        return settings.tr('about');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 650;
    final settings = ref.watch(appSettingsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D14),
        elevation: 0,
        title: Text(
          settings.tr('settings'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
      ),
      body: isCompact ? _buildCompactLayout(settings) : _buildTwoPanelLayout(settings),
    );
  }

  Widget _buildTwoPanelLayout(AppSettings settings) {
    return Row(
      children: [
        // ── Left Navigation Menu ──
        Container(
          width: 240,
          decoration: const BoxDecoration(
            color: Color(0xFF0F0E17),
            border: Border(
              right: BorderSide(color: Color(0xFF1E1E2E), width: 1),
            ),
          ),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            itemCount: SettingsGroup.values.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final group = SettingsGroup.values[index];
              final isSelected = group == _selectedGroup;

              return ListTile(
                autofocus: isSelected,
                focusColor: const Color(0xFF6C5CE7).withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                tileColor: isSelected ? const Color(0xFF6C5CE7).withValues(alpha: 0.22) : Colors.transparent,
                leading: Icon(
                  group.icon,
                  color: isSelected ? const Color(0xFFA29BFE) : Colors.white60,
                  size: 20,
                ),
                title: Text(
                  _getGroupLabel(group, settings),
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                onTap: () => setState(() => _selectedGroup = group),
              );
            },
          ),
        ),

        // ── Right Content Panel ──
        Expanded(
          child: Container(
            color: const Color(0xFF0A0A0F),
            child: _buildGroupContent(_selectedGroup),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactLayout(AppSettings settings) {
    return ListView(
      children: SettingsGroup.values.map((group) {
        final label = _getGroupLabel(group, settings);
        return ListTile(
          leading: Icon(group.icon, color: const Color(0xFF6C5CE7)),
          title: Text(label, style: const TextStyle(color: Colors.white)),
          trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  backgroundColor: const Color(0xFF0A0A0F),
                  appBar: AppBar(
                    backgroundColor: const Color(0xFF0D0D14),
                    title: Text(label),
                  ),
                  body: _buildGroupContent(group),
                ),
              ),
            );
          },
        );
      }).toList(),
    );
  }

  Widget _buildGroupContent(SettingsGroup group) {
    switch (group) {
      case SettingsGroup.general:
        return _buildGeneralSettings();
      case SettingsGroup.playback:
        return _buildPlaybackSettings();
      case SettingsGroup.audioSubtitles:
        return _buildAudioSubtitlesSettings();
      case SettingsGroup.liveTvGuide:
        return _buildLiveTvGuideSettings();
      case SettingsGroup.parentalControls:
        return _buildParentalControlsSettings();
      case SettingsGroup.deviceLicense:
        return _buildDeviceLicenseSettings();
      case SettingsGroup.privacy:
        return _buildPrivacySettings();
      case SettingsGroup.helpAbout:
        return _buildHelpAboutSettings();
    }
  }

  // ──────────────────────────────
  // 1. General Settings
  // ──────────────────────────────
  Widget _buildGeneralSettings() {
    final settings = ref.watch(appSettingsProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionHeader(title: 'General', subtitle: 'Language, startup behavior, and appearance'),
        _SettingsCard(
          children: [
            // Language
            ListTile(
              leading: const Icon(Icons.language_rounded, color: Colors.white70),
              title: const Text('Language', style: TextStyle(color: Colors.white)),
              trailing: DropdownButton<String>(
                value: settings.language,
                dropdownColor: const Color(0xFF1E1C2E),
                style: const TextStyle(color: Colors.white),
                underline: const SizedBox.shrink(),
                items: ['English', 'Spanish', 'French', 'German', 'Arabic', 'Portuguese']
                    .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    ref.read(appSettingsProvider.notifier).update((s) => s.copyWith(language: val));
                  }
                },
              ),
            ),
            const Divider(color: Color(0xFF26243A), height: 1),

            // Startup Page
            ListTile(
              leading: const Icon(Icons.launch_rounded, color: Colors.white70),
              title: const Text('Startup page', style: TextStyle(color: Colors.white)),
              trailing: DropdownButton<String>(
                value: settings.startupPage,
                dropdownColor: const Color(0xFF1E1C2E),
                style: const TextStyle(color: Colors.white),
                underline: const SizedBox.shrink(),
                items: ['Home', 'Live TV', 'Movies', 'Series']
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    ref.read(appSettingsProvider.notifier).update((s) => s.copyWith(startupPage: val));
                  }
                },
              ),
            ),
            const Divider(color: Color(0xFF26243A), height: 1),

            // Clock Format
            ListTile(
              leading: const Icon(Icons.access_time_rounded, color: Colors.white70),
              title: const Text('Clock format', style: TextStyle(color: Colors.white)),
              trailing: DropdownButton<String>(
                value: settings.clockFormat,
                dropdownColor: const Color(0xFF1E1C2E),
                style: const TextStyle(color: Colors.white),
                underline: const SizedBox.shrink(),
                items: ['12-hour', '24-hour']
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    ref.read(appSettingsProvider.notifier).update((s) => s.copyWith(clockFormat: val));
                  }
                },
              ),
            ),
            const Divider(color: Color(0xFF26243A), height: 1),

            // Text Size
            ListTile(
              leading: const Icon(Icons.format_size_rounded, color: Colors.white70),
              title: const Text('Text size', style: TextStyle(color: Colors.white)),
              trailing: DropdownButton<String>(
                value: settings.textSize,
                dropdownColor: const Color(0xFF1E1C2E),
                style: const TextStyle(color: Colors.white),
                underline: const SizedBox.shrink(),
                items: ['Small', 'Normal', 'Large']
                    .map((ts) => DropdownMenuItem(value: ts, child: Text(ts)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    ref.read(appSettingsProvider.notifier).update((s) => s.copyWith(textSize: val));
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ──────────────────────────────
  // 2. Playback Settings
  // ──────────────────────────────
  Widget _buildPlaybackSettings() {
    final settings = ref.watch(appSettingsProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionHeader(title: 'Playback', subtitle: 'Engine, stream protocol, buffer, and aspect ratio'),
        _SettingsCard(
          children: [
            // Hardware Acceleration
            SwitchListTile(
              secondary: const Icon(Icons.speed_rounded, color: Colors.white70),
              title: const Text('Hardware Acceleration', style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                'Use GPU hardware decoding (auto-safe / MediaCodec). Disable if experiencing black screen or codec issues.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              value: settings.hardwareAcceleration,
              activeColor: const Color(0xFF6C5CE7),
              onChanged: (val) {
                ref.read(appSettingsProvider.notifier).update((s) => s.copyWith(hardwareAcceleration: val));
                ref.read(playerServiceProvider).setHardwareAcceleration(val);
              },
            ),
            const Divider(color: Color(0xFF26243A), height: 1),

            // Stream Format / Protocol Selector (HLS vs MPEG-TS)
            ListTile(
              leading: const Icon(Icons.stream_rounded, color: Colors.white70),
              title: const Text('Stream Format / Protocol', style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                'Choose playback protocol for Xtream streams. HLS (.m3u8) can reduce buffering on some servers.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              trailing: DropdownButton<String>(
                value: settings.streamFormat,
                dropdownColor: const Color(0xFF1E1C2E),
                style: const TextStyle(color: Colors.white),
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 'ts', child: Text('MPEG-TS (.ts)')),
                  DropdownMenuItem(value: 'm3u8', child: Text('HLS (.m3u8)')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    ref.read(appSettingsProvider.notifier).update((s) => s.copyWith(streamFormat: val));
                  }
                },
              ),
            ),
            const Divider(color: Color(0xFF26243A), height: 1),

            // Default Aspect Ratio
            ListTile(
              leading: const Icon(Icons.aspect_ratio_rounded, color: Colors.white70),
              title: const Text('Default Aspect Ratio', style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                'Default display scaling applied when opening a video',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              trailing: DropdownButton<String>(
                value: settings.defaultAspectRatio,
                dropdownColor: const Color(0xFF1E1C2E),
                style: const TextStyle(color: Colors.white),
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 'Fit (Auto)', child: Text('Fit (Auto)')),
                  DropdownMenuItem(value: '16:9', child: Text('16:9')),
                  DropdownMenuItem(value: '4:3', child: Text('4:3')),
                  DropdownMenuItem(value: 'Fill / Stretch', child: Text('Fill / Stretch')),
                  DropdownMenuItem(value: 'Zoom', child: Text('Zoom')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    ref.read(appSettingsProvider.notifier).update((s) => s.copyWith(defaultAspectRatio: val));
                  }
                },
              ),
            ),
            const Divider(color: Color(0xFF26243A), height: 1),

            // Buffer Size
            _BufferSizeTile(),
            const Divider(color: Color(0xFF26243A), height: 1),

            // Failover Mode
            _FailoverModeTile(),
            const Divider(color: Color(0xFF26243A), height: 1),

            // User Agent
            _UserAgentTile(),
          ],
        ),
      ],
    );
  }

  // ──────────────────────────────
  // 3. Audio & Subtitles Settings
  // ──────────────────────────────
  Widget _buildAudioSubtitlesSettings() {
    final settings = ref.watch(appSettingsProvider);
    final languages = [
      'English',
      'Spanish',
      'French',
      'German',
      'Arabic',
      'Italian',
      'Portuguese',
      'Turkish',
      'Russian',
      'Japanese'
    ];

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionHeader(title: 'Audio & Subtitles', subtitle: 'Track preferences and episode behavior'),
        _SettingsCard(
          children: [
            // Preferred Audio Language
            ListTile(
              leading: const Icon(Icons.audiotrack_rounded, color: Colors.white70),
              title: const Text('Preferred audio language', style: TextStyle(color: Colors.white)),
              trailing: DropdownButton<String>(
                value: languages.contains(settings.preferredAudioLanguage)
                    ? settings.preferredAudioLanguage
                    : 'English',
                dropdownColor: const Color(0xFF1E1C2E),
                style: const TextStyle(color: Colors.white),
                underline: const SizedBox.shrink(),
                items: languages.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                onChanged: (val) {
                  if (val != null) {
                    ref.read(appSettingsProvider.notifier).update((s) => s.copyWith(preferredAudioLanguage: val));
                  }
                },
              ),
            ),
            const Divider(color: Color(0xFF26243A), height: 1),

            // Fallback Audio Language
            ListTile(
              leading: const Icon(Icons.queue_music_rounded, color: Colors.white70),
              title: const Text('Fallback audio language', style: TextStyle(color: Colors.white)),
              trailing: DropdownButton<String>(
                value: languages.contains(settings.fallbackAudioLanguage)
                    ? settings.fallbackAudioLanguage
                    : 'English',
                dropdownColor: const Color(0xFF1E1C2E),
                style: const TextStyle(color: Colors.white),
                underline: const SizedBox.shrink(),
                items: languages.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                onChanged: (val) {
                  if (val != null) {
                    ref.read(appSettingsProvider.notifier).update((s) => s.copyWith(fallbackAudioLanguage: val));
                  }
                },
              ),
            ),
            const Divider(color: Color(0xFF26243A), height: 1),

            // Subtitle Mode
            ListTile(
              leading: const Icon(Icons.subtitles_rounded, color: Colors.white70),
              title: const Text('Subtitle mode', style: TextStyle(color: Colors.white)),
              trailing: DropdownButton<String>(
                value: settings.subtitleMode,
                dropdownColor: const Color(0xFF1E1C2E),
                style: const TextStyle(color: Colors.white),
                underline: const SizedBox.shrink(),
                items: ['Off', 'On', 'Auto']
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    ref.read(appSettingsProvider.notifier).update((s) => s.copyWith(subtitleMode: val));
                  }
                },
              ),
            ),
            const Divider(color: Color(0xFF26243A), height: 1),

            // Preferred Subtitle Language
            ListTile(
              leading: const Icon(Icons.closed_caption_rounded, color: Colors.white70),
              title: const Text('Preferred subtitle language', style: TextStyle(color: Colors.white)),
              trailing: DropdownButton<String>(
                value: languages.contains(settings.preferredSubtitleLanguage)
                    ? settings.preferredSubtitleLanguage
                    : 'English',
                dropdownColor: const Color(0xFF1E1C2E),
                style: const TextStyle(color: Colors.white),
                underline: const SizedBox.shrink(),
                items: languages.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                onChanged: (val) {
                  if (val != null) {
                    ref.read(appSettingsProvider.notifier).update((s) => s.copyWith(preferredSubtitleLanguage: val));
                  }
                },
              ),
            ),
            const Divider(color: Color(0xFF26243A), height: 1),

            // Autoplay Next Episode
            SwitchListTile(
              secondary: const Icon(Icons.skip_next_rounded, color: Colors.white70),
              title: const Text('Autoplay next episode', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Automatically transition to next episode on completion',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              value: settings.autoplayNextEpisode,
              activeColor: const Color(0xFF6C5CE7),
              onChanged: (val) {
                ref.read(appSettingsProvider.notifier).update((s) => s.copyWith(autoplayNextEpisode: val));
              },
            ),
          ],
        ),
      ],
    );
  }

  // ──────────────────────────────
  // 4. Live TV / Guide Settings
  // ──────────────────────────────
  Widget _buildLiveTvGuideSettings() {
    final settings = ref.watch(appSettingsProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionHeader(title: 'Live TV & TV Guide', subtitle: 'EPG feeds, timezone shift, and auto-refresh'),
        _SettingsCard(
          children: [
            // Auto-Refresh on Startup
            SwitchListTile(
              secondary: const Icon(Icons.sync_rounded, color: Colors.white70),
              title: const Text('Auto-Refresh on Startup', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Automatically refresh channel lists and EPG schedules when the app opens',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              value: settings.autoRefreshOnStartup,
              activeColor: const Color(0xFF6C5CE7),
              onChanged: (val) {
                ref.read(appSettingsProvider.notifier).update((s) => s.copyWith(autoRefreshOnStartup: val));
              },
            ),
            const Divider(color: Color(0xFF26243A), height: 1),

            // Automatic Preview
            SwitchListTile(
              secondary: const Icon(Icons.visibility_rounded, color: Colors.white70),
              title: const Text('Automatic preview', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Start video preview automatically when focusing a channel',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              value: settings.autoPreview,
              activeColor: const Color(0xFF6C5CE7),
              onChanged: (val) {
                ref.read(appSettingsProvider.notifier).update((s) => s.copyWith(autoPreview: val));
              },
            ),
            const Divider(color: Color(0xFF26243A), height: 1),

            // EPG Time Shift (+/- 12 Hours)
            ListTile(
              leading: const Icon(Icons.schedule_rounded, color: Colors.white70),
              title: const Text('EPG Time Shift (Offset)', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                settings.epgTimeShiftHours == 0
                    ? 'No shift (0 hours) • Matches provider timezone'
                    : '${settings.epgTimeShiftHours > 0 ? "+" : ""}${settings.epgTimeShiftHours} hours • Shifts program guide schedule',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              trailing: DropdownButton<int>(
                value: settings.epgTimeShiftHours,
                dropdownColor: const Color(0xFF1E1C2E),
                style: const TextStyle(color: Colors.white),
                underline: const SizedBox.shrink(),
                items: List.generate(25, (i) {
                  final h = i - 12; // -12 to +12
                  final label = h == 0 ? '0h (None)' : (h > 0 ? '+$h hours' : '$h hours');
                  return DropdownMenuItem(value: h, child: Text(label));
                }),
                onChanged: (val) {
                  if (val != null) {
                    ref.read(appSettingsProvider.notifier).update((s) => s.copyWith(epgTimeShiftHours: val));
                  }
                },
              ),
            ),
            const Divider(color: Color(0xFF26243A), height: 1),

            // Auto Refresh Interval
            _AutoRefreshTile(),
          ],
        ),
      ],
    );
  }

  // ──────────────────────────────
  // 5. Parental Controls Settings
  // ──────────────────────────────
  Widget _buildParentalControlsSettings() {
    final settings = ref.watch(appSettingsProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionHeader(title: 'Parental Controls', subtitle: 'PIN protection and category locking'),
        _SettingsCard(
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.lock_rounded, color: Colors.white70),
              title: const Text('Enable Parental Controls', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                settings.parentalControlsEnabled
                    ? 'Active — PIN is required to access locked sections'
                    : 'Disabled',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              value: settings.parentalControlsEnabled,
              activeColor: const Color(0xFF6C5CE7),
              onChanged: (val) {
                if (val && settings.parentalPin.isEmpty) {
                  _showSetPinDialog(context);
                } else {
                  ref.read(appSettingsProvider.notifier).update((s) => s.copyWith(parentalControlsEnabled: val));
                }
              },
            ),
            const Divider(color: Color(0xFF26243A), height: 1),
            ListTile(
              leading: const Icon(Icons.pin_rounded, color: Colors.white70),
              title: const Text('Change PIN', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                settings.parentalPin.isNotEmpty ? 'PIN is set (••••)' : 'No PIN set',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              trailing: const Icon(Icons.edit_rounded, color: Colors.white54, size: 20),
              onTap: () => _showSetPinDialog(context),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _SettingsCard(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Locked Categories',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['Adult', 'Horror', 'News', 'Pay-Per-View'].map((cat) {
                  final isLocked = settings.lockedCategories.contains(cat);
                  return FilterChip(
                    label: Text(cat),
                    selected: isLocked,
                    selectedColor: const Color(0xFF6C5CE7).withValues(alpha: 0.35),
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(color: isLocked ? Colors.white : Colors.white70),
                    onSelected: (selected) {
                      final updated = List<String>.from(settings.lockedCategories);
                      if (selected) {
                        updated.add(cat);
                      } else {
                        updated.remove(cat);
                      }
                      ref.read(appSettingsProvider.notifier).update((s) => s.copyWith(lockedCategories: updated));
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showSetPinDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A192A),
        title: const Text('Set Parental PIN'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 4,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '4-Digit PIN',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final pin = ctrl.text.trim();
              if (pin.length == 4) {
                ref.read(appSettingsProvider.notifier).update((s) => s.copyWith(
                      parentalPin: pin,
                      parentalControlsEnabled: true,
                    ));
                Navigator.pop(ctx);
              }
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6C5CE7)),
            child: const Text('Save PIN'),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────
  // 6. Device / License Settings
  // ──────────────────────────────
  Widget _buildDeviceLicenseSettings() {
    final identityAsync = ref.watch(deviceIdentityProvider);
    final macAddress = identityAsync.value?.macAddress ?? 'Loading…';
    final deviceKey = identityAsync.value?.deviceKey ?? '••••••';

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionHeader(title: 'Device & License', subtitle: 'Hardware identification and active player license'),
        _SettingsCard(
          children: [
            // Device ID (Virtual MAC)
            ListTile(
              leading: const Icon(Icons.fingerprint_rounded, color: Colors.white70),
              title: const Text('Device ID / MAC', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                macAddress,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.copy_rounded, color: Colors.white54, size: 20),
                tooltip: 'Copy MAC',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: macAddress));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('MAC copied: $macAddress')),
                  );
                },
              ),
            ),
            const Divider(color: Color(0xFF26243A), height: 1),

            // Revealable 6-digit Device Key
            ListTile(
              leading: const Icon(Icons.vpn_key_rounded, color: Colors.white70),
              title: const Text('Device Key', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                _keyRevealed ? deviceKey : '••••••',
                style: const TextStyle(
                  color: Colors.white70,
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3.0,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(_keyRevealed ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        color: Colors.white54),
                    onPressed: () => setState(() => _keyRevealed = !_keyRevealed),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, color: Colors.white54, size: 20),
                    tooltip: 'Copy Key',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: deviceKey));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Device key copied')),
                      );
                    },
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF26243A), height: 1),

            // License Status
            const ListTile(
              leading: Icon(Icons.verified_rounded, color: Colors.greenAccent),
              title: Text('License Status', style: TextStyle(color: Colors.white)),
              subtitle: Text('Active (Lifetime Unlimited)', style: TextStyle(color: Colors.greenAccent)),
            ),
            const Divider(color: Color(0xFF26243A), height: 1),

            // App Version & Update
            ListTile(
              leading: const Icon(Icons.system_update_rounded, color: Colors.white70),
              title: const Text('App Version', style: TextStyle(color: Colors.white)),
              subtitle: Text('YesXtream v${AppUpdateService.currentVersion}',
                  style: const TextStyle(color: Colors.white54)),
              trailing: FilledButton(
                onPressed: () => _checkForUpdates(context),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6C5CE7)),
                child: const Text('Check Update'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ──────────────────────────────
  // 8. Privacy Settings
  // ──────────────────────────────
  Widget _buildPrivacySettings() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionHeader(title: 'Privacy & Storage', subtitle: 'Manage your local data and cache'),
        _SettingsCard(
          children: [
            ListTile(
              leading: const Icon(Icons.history_rounded, color: Colors.white70),
              title: const Text('Clear Watch History', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Remove playback resume progress and history',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              trailing: OutlinedButton(
                onPressed: () {
                  ref.read(watchHistoryProvider.notifier).clearAll();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Watch history cleared')),
                  );
                },
                child: const Text('Clear'),
              ),
            ),
            const Divider(color: Color(0xFF26243A), height: 1),
            ListTile(
              leading: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
              title: const Text('Reset All Data', style: TextStyle(color: Colors.redAccent)),
              subtitle: const Text('Remove all playlists, EPG cache, and preferences from this device',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              trailing: FilledButton(
                onPressed: () => _confirmResetAppData(context),
                style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                child: const Text('Reset'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _confirmResetAppData(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A192A),
        title: const Text('Reset All App Data?'),
        content: const Text(
          'This will permanently delete:\n'
          '• All imported IPTV and M3U playlists\n'
          '• All custom EPG sources and mappings\n'
          '• Watch history and favorite lists\n'
          '• Local caches\n\n'
          'Your player license will NOT be cancelled.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('App data reset. Please restart the app.')),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Confirm Reset'),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────
  // 9. Help & About Settings
  // ──────────────────────────────
  Widget _buildHelpAboutSettings() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionHeader(title: 'Help & About', subtitle: 'Support, remote controls, and documentation'),
        _SettingsCard(
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline_rounded, color: Color(0xFF6C5CE7)),
              title: const Text('YesXtream Player',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text('v${AppUpdateService.currentVersion} • High Performance IPTV & VOD Engine',
                  style: const TextStyle(color: Colors.white54)),
            ),
            const Divider(color: Color(0xFF26243A), height: 1),
            ListTile(
              leading: const Icon(Icons.gamepad_rounded, color: Colors.white70),
              title: const Text('Remote & Keyboard Shortcuts', style: TextStyle(color: Colors.white)),
              subtitle: const Text('View navigation and playback shortcuts',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
              onTap: () => _showButtonMappingInfo(context),
            ),
          ],
        ),
      ],
    );
  }

  void _showButtonMappingInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A192A),
        title: const Text('Remote & Keyboard Shortcuts'),
        content: const SingleChildScrollView(
          child: Text(
            'Navigation Controls:\n'
            '  ↑ ↓ ← →   Navigate menu and items\n'
            '  Enter / OK   Select item / Play stream\n'
            '  Esc / Back   Return to previous screen\n\n'
            'Video Player Controls:\n'
            '  Space / OK   Play / Pause\n'
            '  ← / →   Seek ±10 seconds\n'
            '  ↑ / ↓   Volume control\n'
            '  M   Mute / Unmute\n'
            '  Esc   Exit fullscreen or close drawer',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6C5CE7)),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141322),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF26243A), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

// ──────────────────────────────────────────
// Preserved Helper Tiles & Screens
// ──────────────────────────────────────────

Future<void> _checkForUpdates(BuildContext context) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  final release = await AppUpdateService.checkForUpdate();

  if (!context.mounted) return;
  Navigator.of(context).pop();

  if (release == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      countdownSnackBar('Could not check for updates', seconds: 5),
    );
    return;
  }

  if (!release.isNewer) {
    ScaffoldMessenger.of(context).showSnackBar(
      countdownSnackBar(
        'You\'re up to date! (v${AppUpdateService.currentVersion})',
        seconds: 5,
      ),
    );
    return;
  }

  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      title: Text('Update Available — v${release.version}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current: v${AppUpdateService.currentVersion}\n'
            'Latest: v${release.version}\n',
          ),
          if (release.body.isNotEmpty)
            Text(
              release.body.length > 300 ? '${release.body.substring(0, 300)}…' : release.body,
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, 'later'), child: const Text('Later')),
        if (release.apkDownloadUrl != null)
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, 'install'),
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Download & Install'),
          ),
      ],
    ),
  );

  if (action == 'install' && release.apkDownloadUrl != null && context.mounted) {
    _downloadUpdate(context, release.apkDownloadUrl!);
  }
}

Future<void> _downloadUpdate(BuildContext context, String apkUrl) async {
  double progress = 0;
  late StateSetter dialogSetState;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        dialogSetState = setState;
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: const Text('Downloading Update…'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 12),
              Text('${(progress * 100).toStringAsFixed(0)}%'),
            ],
          ),
        );
      },
    ),
  );

  await AppUpdateService.downloadAndInstall(
    apkUrl,
    onProgress: (p) {
      try {
        dialogSetState(() => progress = p);
      } catch (_) {}
    },
    onError: (error) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      }
    },
  );
  if (context.mounted) Navigator.of(context).pop();
}

class _AutoRefreshTile extends StatefulWidget {
  @override
  State<_AutoRefreshTile> createState() => _AutoRefreshTileState();
}

class _AutoRefreshTileState extends State<_AutoRefreshTile> {
  int _intervalHours = 24;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _intervalHours = prefs.getInt('epg_auto_refresh_interval_hours') ?? 24;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.sync_rounded, color: Colors.white70),
      title: const Text('EPG auto-refresh interval', style: TextStyle(color: Colors.white)),
      trailing: DropdownButton<int>(
        value: _intervalHours,
        dropdownColor: const Color(0xFF1E1C2E),
        style: const TextStyle(color: Colors.white),
        underline: const SizedBox.shrink(),
        items: const [
          DropdownMenuItem(value: 6, child: Text('Every 6 hours')),
          DropdownMenuItem(value: 12, child: Text('Every 12 hours')),
          DropdownMenuItem(value: 24, child: Text('Every 24 hours')),
          DropdownMenuItem(value: 48, child: Text('Every 48 hours')),
        ],
        onChanged: (val) async {
          if (val != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('epg_auto_refresh_interval_hours', val);
            setState(() => _intervalHours = val);
          }
        },
      ),
    );
  }
}

class _BufferSizeTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final mode = settings.bufferMode;

    String subtitleText;
    switch (mode) {
      case 'low_latency':
        subtitleText = settings.tr('buffer_low_latency_desc');
        break;
      case 'ultra':
        subtitleText = settings.tr('buffer_ultra_desc');
        break;
      default:
        subtitleText = settings.tr('buffer_standard_desc');
    }

    return ListTile(
      leading: const Icon(Icons.speed_rounded, color: Colors.white70),
      title: Text(settings.tr('buffer_mode'), style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        subtitleText,
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
      trailing: DropdownButton<String>(
        value: mode,
        dropdownColor: const Color(0xFF1E1C2E),
        style: const TextStyle(color: Colors.white, fontSize: 13),
        underline: const SizedBox.shrink(),
        items: [
          DropdownMenuItem(
            value: 'low_latency',
            child: Text(settings.tr('buffer_low_latency')),
          ),
          DropdownMenuItem(
            value: 'standard',
            child: Text(settings.tr('buffer_standard')),
          ),
          DropdownMenuItem(
            value: 'ultra',
            child: Text(settings.tr('buffer_ultra')),
          ),
        ],
        onChanged: (val) async {
          if (val != null) {
            await ref.read(appSettingsProvider.notifier).update((s) => s.copyWith(bufferMode: val));
            final prefs = await SharedPreferences.getInstance();
            final legacySec = val == 'low_latency' ? 5 : (val == 'ultra' ? 45 : 15);
            await prefs.setInt('player_buffer_seconds', legacySec);
          }
        },
      ),
    );
  }
}

class _FailoverModeTile extends StatefulWidget {
  @override
  State<_FailoverModeTile> createState() => _FailoverModeTileState();
}

class _FailoverModeTileState extends State<_FailoverModeTile> {
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _enabled = prefs.getBool('failover_enabled') ?? true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.alt_route_rounded, color: Colors.white70),
      title: const Text('Stream auto-failover', style: TextStyle(color: Colors.white)),
      subtitle: const Text('Automatically switch to backup stream when buffering stalls',
          style: TextStyle(color: Colors.white54, fontSize: 12)),
      value: _enabled,
      activeColor: const Color(0xFF6C5CE7),
      onChanged: (val) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('failover_enabled', val);
        setState(() => _enabled = val);
      },
    );
  }
}

class _UserAgentTile extends StatefulWidget {
  @override
  State<_UserAgentTile> createState() => _UserAgentTileState();
}

class _UserAgentTileState extends State<_UserAgentTile> {
  String _userAgent = 'IPTVSmartersPlayer';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userAgent = prefs.getString('custom_user_agent') ?? 'IPTVSmartersPlayer';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.http_rounded, color: Colors.white70),
      title: const Text('HTTP User-Agent', style: TextStyle(color: Colors.white)),
      subtitle: Text(_userAgent, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      trailing: const Icon(Icons.edit_rounded, color: Colors.white54, size: 20),
      onTap: () async {
        final ctrl = TextEditingController(text: _userAgent);
        final result = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A192A),
            title: const Text('User-Agent Header'),
            content: TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6C5CE7)),
                child: const Text('Save'),
              ),
            ],
          ),
        );
        if (result != null && mounted) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('custom_user_agent', result);
          setState(() => _userAgent = result);
        }
      },
    );
  }
}
