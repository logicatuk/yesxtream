import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform_info.dart';
import '../playlists/playlist_providers.dart';
import 'playlist_error.dart';
import 'provider_manager.dart';

/// Shows the responsive Add Provider experience.
/// Uses a full-screen route (D-pad, keyboard, mouse, and touch friendly).
Future<bool?> showAddProviderDialog(
  BuildContext context, {
  String? existingId,
  String? initialName,
  String? initialUrl,
  String? initialUsername,
  String? initialPassword,
  bool? isXtream,
}) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _AddProviderPage(
        existingId: existingId,
        initialName: initialName,
        initialUrl: initialUrl,
        initialUsername: initialUsername,
        initialPassword: initialPassword,
        isXtream: isXtream,
      ),
    ),
  );
}

enum _ProviderType { m3u, xtream }

class _AddProviderPage extends ConsumerStatefulWidget {
  final String? existingId;
  final String? initialName;
  final String? initialUrl;
  final String? initialUsername;
  final String? initialPassword;
  final bool? isXtream;

  const _AddProviderPage({
    this.existingId,
    this.initialName,
    this.initialUrl,
    this.initialUsername,
    this.initialPassword,
    this.isXtream,
  });

  @override
  ConsumerState<_AddProviderPage> createState() => _AddProviderPageState();
}

class _AddProviderPageState extends ConsumerState<_AddProviderPage> {
  static const _bgBase = Color(0xFF090912);
  static const _brandNavy = Color(0xFF100F29);
  static const _cardBg = Color(0xFF131224);
  static const _panelBg = Color(0xFF18172E);
  static const _inputBg = Color(0xFF1C1B33);
  static const _borderIdle = Color(0xFF2B294B);
  static const _accent = Color(0xFF6C5CE7);
  static const _accentBright = Color(0xFF8B7EF8);

  final _formKey = GlobalKey<FormState>();
  _ProviderType _type = _ProviderType.m3u;

  // M3U fields
  final _m3uName = TextEditingController();
  final _m3uUrl = TextEditingController();

  // Xtream fields
  final _xtreamName = TextEditingController();
  final _xtreamUrl = TextEditingController();
  final _xtreamUser = TextEditingController();
  final _xtreamPass = TextEditingController();

  bool _obscurePassword = true;
  bool _loading = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    if (widget.isXtream == true) {
      _type = _ProviderType.xtream;
    } else if (widget.isXtream == false) {
      _type = _ProviderType.m3u;
    }
    if (widget.initialName != null) {
      _m3uName.text = widget.initialName!;
      _xtreamName.text = widget.initialName!;
    }
    if (widget.initialUrl != null) {
      _m3uUrl.text = widget.initialUrl!;
      _xtreamUrl.text = widget.initialUrl!;
    }
    if (widget.initialUsername != null) {
      _xtreamUser.text = widget.initialUsername!;
    }
    if (widget.initialPassword != null) {
      _xtreamPass.text = widget.initialPassword!;
    }
  }

  @override
  void dispose() {
    _m3uName.dispose();
    _m3uUrl.dispose();
    _xtreamName.dispose();
    _xtreamUrl.dispose();
    _xtreamUser.dispose();
    _xtreamPass.dispose();
    super.dispose();
  }

  String _slugify(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  String _generateId(String name) {
    final slug = _slugify(name);
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '${slug.isEmpty ? 'provider' : slug}-$ts';
  }

  String? _validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    return null;
  }

  String? _validateUrl(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Required';
    final lower = trimmed.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return 'URL must start with http:// or https://';
    }
    return null;
  }

  void _selectType(_ProviderType type) {
    if (_loading || _type == type) return;
    setState(() => _type = type);
  }

  Future<void> _submit() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    void onProgress(int _, String msg) {
      if (mounted) setState(() => _statusMessage = msg);
    }

    final targetId = widget.existingId ??
        (_type == _ProviderType.m3u
            ? _generateId(_m3uName.text.trim())
            : _generateId(_xtreamName.text.trim()));

    if (_type == _ProviderType.m3u) {
      await _addProvider(targetId, () {
        final manager = ref.read(providerManagerProvider);
        return manager.addM3uProvider(
          id: targetId,
          name: _m3uName.text.trim(),
          url: _m3uUrl.text.trim(),
          onProgress: onProgress,
        );
      });
    } else {
      await _addProvider(targetId, () {
        final manager = ref.read(providerManagerProvider);
        return manager.addXtreamProvider(
          id: targetId,
          name: _xtreamName.text.trim(),
          url: _xtreamUrl.text.trim(),
          username: _xtreamUser.text.trim(),
          password: _xtreamPass.text.trim(),
          onProgress: onProgress,
        );
      });
    }
  }

  Future<void> _addProvider(
    String newId,
    Future<void> Function() action,
  ) async {
    setState(() {
      _loading = true;
      _statusMessage = 'Connecting...';
    });
    try {
      await action();
      await ref.read(activePlaylistIdProvider.notifier).selectPlaylist(newId);
      ref.invalidate(activePlaylistStatsProvider);
      ref.invalidate(activePlaylistHasMoviesProvider);
      ref.invalidate(activePlaylistHasSeriesProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.existingId != null
                ? 'Playlist updated successfully'
                : 'Provider added successfully',
          ),
        ),
      );
    } on ProviderLimitException catch (e) {
      if (!mounted) return;
      _showFeedbackDialog(
        icon: Icons.workspaces_outline,
        iconColor: const Color(0xFFFFB142),
        title: 'Provider Limit Reached',
        message: e.toString(),
      );
    } catch (e) {
      if (!mounted) return;
      final info = formatPlaylistError(e);
      _showFeedbackDialog(
        icon: info.icon,
        iconColor: info.color,
        title: info.title,
        message: info.message,
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusMessage = null;
        });
      }
    }
  }

  void _showFeedbackDialog({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
  }) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: _borderIdle),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white70, height: 1.45),
        ),
        actions: [
          FilledButton(
            autofocus: true,
            style: FilledButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _pasteInto(TextEditingController controller) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    controller.text = text;
    controller.selection = TextSelection.collapsed(offset: text.length);
  }

  void _handleBack() {
    final pf = FocusManager.instance.primaryFocus;
    if (pf?.context?.findAncestorWidgetOfExactType<EditableText>() != null) {
      pf!.unfocus();
      return;
    }
    Future.microtask(() {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewInsetsBottom = MediaQuery.viewInsetsOf(context).bottom;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _handleBack,
        const SingleActivator(LogicalKeyboardKey.goBack): _handleBack,
      },
      child: Focus(
        canRequestFocus: false,
        child: Scaffold(
          backgroundColor: _bgBase,
          body: Stack(
            children: [
              _buildAmbientBackdrop(),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final useTwoPane =
                        constraints.maxWidth >= 820 &&
                        constraints.maxHeight >= 500;
                    final horizontalPad = constraints.maxWidth < 480
                        ? 14.0
                        : (useTwoPane ? 32.0 : 22.0);
                    final verticalPad =
                        constraints.maxHeight < 520 ? 12.0 : 24.0;

                    return Center(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPad,
                          verticalPad,
                          horizontalPad,
                          verticalPad + viewInsetsBottom,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: useTwoPane ? 960 : 560,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _cardBg.withValues(alpha: 0.96),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: _borderIdle),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  blurRadius: 36,
                                  offset: const Offset(0, 18),
                                ),
                                BoxShadow(
                                  color: _accent.withValues(alpha: 0.12),
                                  blurRadius: 48,
                                  spreadRadius: -10,
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Form(
                              key: _formKey,
                              child: useTwoPane
                                  ? _buildTwoPaneLayout()
                                  : _buildCompactLayout(
                                      isNarrow: constraints.maxWidth < 470,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAmbientBackdrop() {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _brandNavy.withValues(alpha: 0.75),
                    _bgBase,
                    const Color(0xFF0D0B1D),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -120,
            left: -80,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _accent.withValues(alpha: 0.22),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -140,
            right: -60,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF00B8D4).withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTwoPaneLayout() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: const BoxDecoration(
                color: _panelBg,
                border: Border(
                  right: BorderSide(color: _borderIdle),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(showCloseButton: false),
                  const SizedBox(height: 24),
                  const Text(
                    'CONNECTION TYPE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: Colors.white54,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SourceModeCard(
                    title: 'M3U Playlist',
                    subtitle: 'Paste a direct M3U or M3U+ link',
                    badge: 'Link',
                    icon: Icons.link_rounded,
                    selected: _type == _ProviderType.m3u,
                    autofocus: _type == _ProviderType.m3u,
                    enabled: !_loading,
                    onTap: () => _selectType(_ProviderType.m3u),
                  ),
                  const SizedBox(height: 12),
                  _SourceModeCard(
                    title: 'Xtream Codes',
                    subtitle: 'Server URL, username & password',
                    badge: 'Full API',
                    icon: Icons.dns_rounded,
                    selected: _type == _ProviderType.xtream,
                    autofocus: _type == _ProviderType.xtream,
                    enabled: !_loading,
                    onTap: () => _selectType(_ProviderType.xtream),
                  ),
                  const Spacer(),
                  const SizedBox(height: 20),
                  _buildStatusPanel(),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(30, 26, 30, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _type == _ProviderType.m3u
                                  ? 'M3U Playlist Details'
                                  : 'Xtream Codes Login',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _type == _ProviderType.m3u
                                  ? 'Import channels and groups from your playlist URL.'
                                  : 'Connect Live TV, Movies, Series, and EPG guide.',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white60,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildCloseButton(),
                    ],
                  ),
                  const SizedBox(height: 22),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: KeyedSubtree(
                      key: ValueKey(_type),
                      child: _buildActiveForm(sideBySideCredentials: true),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildActionRow(compact: false),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactLayout({required bool isNarrow}) {
    return Padding(
      padding: EdgeInsets.all(isNarrow ? 18 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(showCloseButton: true),
          const SizedBox(height: 18),
          if (isNarrow)
            _buildCompactSegmentedSwitcher()
          else
            Row(
              children: [
                Expanded(
                  child: _SourceModeCard(
                    title: 'M3U Playlist',
                    subtitle: 'Direct M3U / M3U+ link',
                    icon: Icons.link_rounded,
                    compact: true,
                    selected: _type == _ProviderType.m3u,
                    autofocus: _type == _ProviderType.m3u,
                    enabled: !_loading,
                    onTap: () => _selectType(_ProviderType.m3u),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SourceModeCard(
                    title: 'Xtream Codes',
                    subtitle: 'URL, user & password',
                    icon: Icons.dns_rounded,
                    compact: true,
                    selected: _type == _ProviderType.xtream,
                    autofocus: _type == _ProviderType.xtream,
                    enabled: !_loading,
                    onTap: () => _selectType(_ProviderType.xtream),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: KeyedSubtree(
              key: ValueKey(_type),
              child: _buildActiveForm(sideBySideCredentials: !isNarrow),
            ),
          ),
          if (_loading) ...[
            const SizedBox(height: 16),
            _buildStatusPanel(),
          ],
          const SizedBox(height: 22),
          _buildActionRow(compact: isNarrow),
        ],
      ),
    );
  }

  Widget _buildCompactSegmentedSwitcher() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: _panelBg,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: _borderIdle),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSegmentedPill(
              label: 'M3U Playlist',
              icon: Icons.link_rounded,
              selected: _type == _ProviderType.m3u,
              autofocus: _type == _ProviderType.m3u,
              onTap: () => _selectType(_ProviderType.m3u),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildSegmentedPill(
              label: 'Xtream Codes',
              icon: Icons.dns_rounded,
              selected: _type == _ProviderType.xtream,
              autofocus: _type == _ProviderType.xtream,
              onTap: () => _selectType(_ProviderType.xtream),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedPill({
    required String label,
    required IconData icon,
    required bool selected,
    required bool autofocus,
    required VoidCallback onTap,
  }) {
    return FilledButton(
      autofocus: autofocus,
      onPressed: _loading ? null : onTap,
      style: FilledButton.styleFrom(
        elevation: 0,
        backgroundColor: selected ? _accent : Colors.transparent,
        foregroundColor: selected ? Colors.white : Colors.white60,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
        ),
      ).copyWith(
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return const BorderSide(color: Colors.white, width: 2);
          }
          return null;
        }),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader({required bool showCloseButton}) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _brandNavy,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _accent.withValues(alpha: 0.45)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            'assets/icon/yestream.png',
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(
              Icons.live_tv_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.existingId != null ? 'Edit Playlist' : 'Add Provider',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.existingId != null
                    ? 'Update your connection details'
                    : 'Connect your IPTV playlist or server',
                style: const TextStyle(fontSize: 12.5, color: Colors.white60),
              ),
            ],
          ),
        ),
        if (showCloseButton) _buildCloseButton(),
      ],
    );
  }

  Widget _buildCloseButton() {
    return Tooltip(
      message: 'Close',
      child: IconButton(
        onPressed: _loading ? null : () => Navigator.of(context).pop(),
        style: IconButton.styleFrom(
          backgroundColor: _inputBg,
          foregroundColor: Colors.white70,
          minimumSize: const Size(42, 42),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ).copyWith(
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return const BorderSide(color: Colors.white, width: 2);
            }
            return const BorderSide(color: _borderIdle);
          }),
        ),
        icon: const Icon(Icons.close_rounded, size: 20),
      ),
    );
  }

  Widget _buildStatusPanel() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _loading
            ? _accent.withValues(alpha: 0.12)
            : _inputBg.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _loading ? _accent.withValues(alpha: 0.5) : _borderIdle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (_loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _accentBright,
                  ),
                )
              else
                const Icon(
                  Icons.verified_user_outlined,
                  size: 17,
                  color: _accentBright,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _loading
                      ? (_statusMessage ?? 'Connecting to provider...')
                      : (_type == _ProviderType.m3u
                            ? 'Supports M3U & M3U Plus streams'
                            : 'Syncs Live TV, VOD, Series & EPG'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: _loading ? FontWeight.w600 : FontWeight.w500,
                    color: _loading ? Colors.white : Colors.white70,
                  ),
                ),
              ),
            ],
          ),
          if (_loading) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: const LinearProgressIndicator(
                minHeight: 4,
                backgroundColor: Color(0xFF28264A),
                valueColor: AlwaysStoppedAnimation<Color>(_accentBright),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveForm({required bool sideBySideCredentials}) {
    if (_type == _ProviderType.m3u) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTextField(
            controller: _m3uName,
            label: 'Provider Name',
            hint: 'e.g. Home IPTV',
            icon: Icons.badge_outlined,
            validator: _validateRequired,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _m3uUrl,
            label: 'M3U URL',
            hint: 'http://example.com/playlist.m3u',
            icon: Icons.link_rounded,
            validator: _validateUrl,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: _submit,
            suffix: _buildPasteSuffix(() => _pasteInto(_m3uUrl)),
          ),
        ],
      );
    }

    final userField = _buildTextField(
      controller: _xtreamUser,
      label: 'Username',
      hint: 'Account username',
      icon: Icons.person_outline_rounded,
      validator: _validateRequired,
      textInputAction: TextInputAction.next,
    );

    final passField = _buildTextField(
      controller: _xtreamPass,
      label: 'Password',
      hint: 'Account password',
      icon: Icons.lock_outline_rounded,
      obscureText: _obscurePassword,
      validator: _validateRequired,
      textInputAction: TextInputAction.done,
      onSubmitted: _submit,
      suffix: IconButton(
        tooltip: _obscurePassword ? 'Show password' : 'Hide password',
        onPressed: _loading
            ? null
            : () => setState(() => _obscurePassword = !_obscurePassword),
        icon: Icon(
          _obscurePassword
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          size: 19,
          color: Colors.white60,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTextField(
          controller: _xtreamName,
          label: 'Provider Name',
          hint: 'e.g. My Xtream Server',
          icon: Icons.badge_outlined,
          validator: _validateRequired,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        _buildTextField(
          controller: _xtreamUrl,
          label: 'Server URL',
          hint: 'http://server.domain:port',
          icon: Icons.dns_outlined,
          validator: _validateUrl,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          suffix: _buildPasteSuffix(() => _pasteInto(_xtreamUrl)),
        ),
        const SizedBox(height: 14),
        if (sideBySideCredentials)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: userField),
              const SizedBox(width: 14),
              Expanded(child: passField),
            ],
          )
        else ...[
          userField,
          const SizedBox(height: 14),
          passField,
        ],
      ],
    );
  }

  Widget _buildPasteSuffix(VoidCallback onPaste) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: TextButton.icon(
        onPressed: _loading ? null : onPaste,
        style: TextButton.styleFrom(
          foregroundColor: _accentBright,
          backgroundColor: _accent.withValues(alpha: 0.14),
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        icon: const Icon(Icons.content_paste_rounded, size: 15),
        label: const Text(
          'Paste',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    bool obscureText = false,
    VoidCallback? onSubmitted,
    Widget? suffix,
  }) {
    final tvBorderWidth = PlatformInfo.isTV ? 2.5 : 1.8;

    return TextFormField(
      controller: controller,
      enabled: !_loading,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      autocorrect: false,
      enableSuggestions: false,
      onFieldSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white60, fontSize: 14),
        hintStyle: const TextStyle(color: Colors.white30, fontSize: 13.5),
        prefixIcon: Icon(icon, size: 20, color: Colors.white54),
        suffixIcon: suffix,
        suffixIconConstraints: const BoxConstraints(minHeight: 38),
        filled: true,
        fillColor: _inputBg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _borderIdle),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _borderIdle.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _accentBright, width: tvBorderWidth),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFFF6B81)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: const Color(0xFFFF6B81),
            width: tvBorderWidth,
          ),
        ),
      ),
    );
  }

  Widget _buildActionRow({required bool compact}) {
    final submitBtn = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: FilledButton.icon(
        onPressed: _loading ? null : _submit,
        style: FilledButton.styleFrom(
          backgroundColor: _accent,
          disabledBackgroundColor: _accent.withValues(alpha: 0.55),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: _loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.add_circle_outline_rounded, size: 20),
        label: Text(
          _loading
              ? (_statusMessage ?? 'Connecting...')
              : (widget.existingId != null ? 'Save Changes' : 'Add Provider'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
        ),
      ),
    );

    final cancelBtn = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: OutlinedButton(
        onPressed: _loading ? null : () => Navigator.of(context).pop(),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white70,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ).copyWith(
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return const BorderSide(color: Colors.white, width: 2.2);
            }
            return const BorderSide(color: _borderIdle);
          }),
        ),
        child: const Text(
          'Cancel',
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
      ),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          submitBtn,
          const SizedBox(height: 10),
          cancelBtn,
        ],
      );
    }

    return Row(
      children: [
        cancelBtn,
        const SizedBox(width: 12),
        Expanded(child: submitBtn),
      ],
    );
  }
}

class _SourceModeCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String? badge;
  final IconData icon;
  final bool selected;
  final bool autofocus;
  final bool enabled;
  final bool compact;
  final VoidCallback onTap;

  const _SourceModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.autofocus,
    required this.enabled,
    required this.onTap,
    this.badge,
    this.compact = false,
  });

  @override
  State<_SourceModeCard> createState() => _SourceModeCardState();
}

class _SourceModeCardState extends State<_SourceModeCard> {
  static const _accent = Color(0xFF6C5CE7);
  static const _accentBright = Color(0xFF9387FF);
  static const _idleBg = Color(0xFF1E1D37);
  static const _borderIdle = Color(0xFF2D2B4E);

  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    final borderColor = _focused
        ? Colors.white
        : (active ? _accentBright : _borderIdle);
    final borderWidth = _focused ? 2.4 : (active ? 1.8 : 1.0);
    final fillColor = active
        ? _accent.withValues(alpha: _focused ? 0.28 : 0.18)
        : (_hovered || _focused
              ? _idleBg.withValues(alpha: 0.95)
              : _idleBg.withValues(alpha: 0.65));

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                event.logicalKey == LogicalKeyboardKey.space ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          if (widget.enabled) widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        button: true,
        selected: active,
        label: widget.title,
        child: MouseRegion(
          cursor: widget.enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.enabled ? widget.onTap : null,
            child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: EdgeInsets.all(widget.compact ? 12 : 14),
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: borderWidth),
              boxShadow: active || _focused
                  ? [
                      BoxShadow(
                        color: (_focused ? Colors.white : _accent)
                            .withValues(alpha: 0.14),
                        blurRadius: 16,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: widget.compact ? 36 : 42,
                  height: widget.compact ? 36 : 42,
                  decoration: BoxDecoration(
                    color: active
                        ? _accent
                        : const Color(0xFF282648),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    widget.icon,
                    size: widget.compact ? 19 : 21,
                    color: active ? Colors.white : Colors.white70,
                  ),
                ),
                SizedBox(width: widget.compact ? 10 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: widget.compact ? 13.5 : 15,
                                fontWeight: FontWeight.w700,
                                color: active ? Colors.white : Colors.white70,
                              ),
                            ),
                          ),
                          if (widget.badge != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: active
                                    ? _accent.withValues(alpha: 0.35)
                                    : Colors.white10,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                widget.badge!,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: active
                                      ? Colors.white
                                      : Colors.white54,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: widget.compact ? 11.5 : 12,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  active
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: widget.compact ? 18 : 20,
                  color: active ? _accentBright : Colors.white24,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}
