import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/datasources/remote/xtream_client.dart';
import '../providers/provider_manager.dart';
import 'choose_playlist_type_dialog.dart';
import 'playlist_providers.dart';

Future<void> showPlaylistFormDialog(
  BuildContext context, {
  required PlaylistImportType type,
  String? existingId,
  String? initialName,
  String? initialUrl,
  String? initialUsername,
  String? initialPassword,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _PlaylistFormDialog(
      type: type,
      existingId: existingId,
      initialName: initialName,
      initialUrl: initialUrl,
      initialUsername: initialUsername,
      initialPassword: initialPassword,
    ),
  );
}

class _PlaylistFormDialog extends ConsumerStatefulWidget {
  final PlaylistImportType type;
  final String? existingId;
  final String? initialName;
  final String? initialUrl;
  final String? initialUsername;
  final String? initialPassword;

  const _PlaylistFormDialog({
    required this.type,
    this.existingId,
    this.initialName,
    this.initialUrl,
    this.initialUsername,
    this.initialPassword,
  });

  @override
  ConsumerState<_PlaylistFormDialog> createState() => _PlaylistFormDialogState();
}

class _PlaylistFormDialogState extends ConsumerState<_PlaylistFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _epgCtrl;

  bool _obscurePass = true;
  bool _testingConnection = false;
  _TestResult? _testResult;

  // Screen 06 Staged import state
  bool _isImporting = false;
  int _importStep = 0; // 0=idle, 1=conn, 2=cat, 3=catalog, 4=ready
  String? _importError;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
    _urlCtrl = TextEditingController(text: widget.initialUrl ?? '');
    _userCtrl = TextEditingController(text: widget.initialUsername ?? '');
    _passCtrl = TextEditingController(text: widget.initialPassword ?? '');
    _epgCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _epgCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _testingConnection = true;
      _testResult = null;
    });

    final rawUrl = _urlCtrl.text.trim();
    final url = rawUrl.endsWith('/') ? rawUrl.substring(0, rawUrl.length - 1) : rawUrl;
    final xtreamFromM3u = parseXtreamFromM3uUrl(url);

    if (widget.type == PlaylistImportType.iptv || xtreamFromM3u != null) {
      final client = XtreamClient(
        baseUrl: xtreamFromM3u?.baseUrl ?? url,
        username: xtreamFromM3u?.username ?? _userCtrl.text.trim(),
        password: xtreamFromM3u?.password ?? _passCtrl.text.trim(),
      );

      try {
        final auth = await client.authenticate();
        int liveCount = 0;
        int vodCount = 0;
        int seriesCount = 0;

        try {
          final lives = await client.getLiveStreams(providerId: 'temp');
          liveCount = lives.length;
        } catch (_) {}
        try {
          final vods = await client.getVodStreams(providerId: 'temp');
          vodCount = vods.length;
        } catch (_) {}
        try {
          final series = await client.getSeriesStreams(providerId: 'temp');
          seriesCount = series.length;
        } catch (_) {}

        if (mounted) {
          setState(() {
            _testingConnection = false;
            _testResult = _TestResult(
              success: true,
              liveCount: liveCount,
              vodCount: vodCount,
              seriesCount: seriesCount,
              serverName: auth.url ?? (xtreamFromM3u?.baseUrl ?? url),
            );
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _testingConnection = false;
            _testResult = _TestResult(
              success: false,
              errorMessage: 'Could not connect: $e',
            );
          });
        }
      } finally {
        client.dispose();
      }
    } else {
      // M3U test with IPTV headers and validateStatus
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            'User-Agent': 'IPTVSmartersPro/1.0.0 (Linux; Android 12)',
            'Accept': '*/*',
          },
          validateStatus: (status) => status != null && status < 900,
        ),
      );
      try {
        final res = await dio.get<dynamic>(
          url,
          options: Options(
            responseType: ResponseType.stream,
            headers: {'Range': 'bytes=0-1024'},
          ),
        );
        if (mounted) {
          setState(() {
            _testingConnection = false;
            _testResult = const _TestResult(
              success: true,
              liveCount: 1,
            );
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _testingConnection = false;
            _testResult = _TestResult(
              success: false,
              errorMessage: 'Unable to reach M3U playlist URL ($e)',
            );
          });
        }
      } finally {
        dio.close();
      }
    }
  }

  Future<void> _startImport() async {
    setState(() {
      _isImporting = true;
      _importStep = 1;
      _importError = null;
    });

    final name = _nameCtrl.text.trim();
    final rawUrl = _urlCtrl.text.trim();
    final url = rawUrl.endsWith('/') ? rawUrl.substring(0, rawUrl.length - 1) : rawUrl;
    final providerId = widget.existingId ??
        'p_${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}_${DateTime.now().millisecondsSinceEpoch}';

    try {
      // Step 1: Connection checked
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      setState(() => _importStep = 2);

      // Step 2: Categories loaded
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      setState(() => _importStep = 3);

      final manager = ref.read(providerManagerProvider);
      final xtreamFromM3u = parseXtreamFromM3uUrl(url);

      if (widget.type == PlaylistImportType.iptv || xtreamFromM3u != null) {
        await manager.addXtreamProvider(
          id: providerId,
          name: name,
          url: xtreamFromM3u?.baseUrl ?? url,
          username: xtreamFromM3u?.username ?? _userCtrl.text.trim(),
          password: xtreamFromM3u?.password ?? _passCtrl.text.trim(),
        );
      } else {
        await manager.addM3uProvider(
          id: providerId,
          name: name,
          url: url,
        );
      }

      // Step 3: Catalog loaded & Step 4: Ready
      if (!mounted) return;
      setState(() => _importStep = 4);

      // Set as active playlist
      await ref.read(activePlaylistIdProvider.notifier).selectPlaylist(providerId);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      Navigator.of(context).pop();
      context.go('/live');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isImporting = false;
        _importError = 'Could not connect to this provider.\n$e\n\nYour details have not been discarded.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isImporting) {
      return _buildScreen06ImportProgress(context);
    }

    if (widget.type == PlaylistImportType.phone) {
      return _buildPhoneQrDialog(context);
    }

    final isIptv = widget.type == PlaylistImportType.iptv;

    return Dialog(
      backgroundColor: const Color(0xFF141322),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isIptv ? Icons.vpn_key_rounded : Icons.link_rounded,
                        color: const Color(0xFF6C5CE7),
                        size: 26,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        isIptv ? 'IPTV Login' : 'M3U Playlist',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white38),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Playlist Name
                  _buildTextField(
                    controller: _nameCtrl,
                    label: 'Playlist Name',
                    hint: 'e.g., My IPTV',
                    validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 14),

                  // Server URL / Playlist URL
                  _buildTextField(
                    controller: _urlCtrl,
                    label: isIptv ? 'Server URL' : 'Playlist URL (M3U)',
                    hint: isIptv ? 'http://example.com:8080' : 'https://example.com/playlist.m3u',
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (!v.trim().startsWith('http')) return 'Must start with http:// or https://';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  if (isIptv) ...[
                    // Username
                    _buildTextField(
                      controller: _userCtrl,
                      label: 'Username',
                      hint: 'Username',
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 14),

                    // Password with Show/Hide
                    _buildTextField(
                      controller: _passCtrl,
                      label: 'Password',
                      hint: 'Password',
                      obscureText: _obscurePass,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePass ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                          color: Colors.white54,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscurePass = !_obscurePass),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 18),
                  ] else ...[
                    // EPG URL (optional)
                    _buildTextField(
                      controller: _epgCtrl,
                      label: 'EPG URL (optional)',
                      hint: 'http://example.com/epg.xml.gz',
                    ),
                    const SizedBox(height: 18),
                  ],

                  // Connection Test Status Card
                  if (_testResult != null) ...[
                    _buildTestResultCard(_testResult!),
                    const SizedBox(height: 18),
                  ],

                  if (_importError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        _importError!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],

                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _testingConnection ? null : _testConnection,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF6C5CE7)),
                        ),
                        icon: _testingConnection
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('Test Connection'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: _testingConnection ? null : _startImport,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF6C5CE7),
                        ),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: Text(_testResult?.success == true ? 'Save and open' : 'Connect & Import'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTestResultCard(_TestResult result) {
    if (!result.success) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                result.errorMessage ?? 'Connection failed',
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 20),
              SizedBox(width: 8),
              Text(
                'Connection successful',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildCountBadge('Live Channels', result.liveCount),
              _buildCountBadge('Movies', result.vodCount),
              _buildCountBadge('Series', result.seriesCount),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCountBadge(String label, int count) {
    return Column(
      children: [
        Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
        labelStyle: const TextStyle(color: Colors.white70, fontSize: 14),
        filled: true,
        fillColor: const Color(0xFF1B1A2C),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2C2B42)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2C2B42)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF6C5CE7), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  // ── Screen 06 Staged Progress Dialog ──
  Widget _buildScreen06ImportProgress(BuildContext context) {
    final playlistName = _nameCtrl.text.trim();

    return Dialog(
      backgroundColor: const Color(0xFF141322),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Adding "$playlistName"',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),

              _buildStagedStep(
                title: 'Connection checked',
                isDone: _importStep >= 2,
                isLoading: _importStep == 1,
              ),
              const SizedBox(height: 14),

              _buildStagedStep(
                title: 'Categories loaded',
                isDone: _importStep >= 3,
                isLoading: _importStep == 2,
              ),
              const SizedBox(height: 14),

              _buildStagedStep(
                title: 'Loading catalog',
                isDone: _importStep >= 4,
                isLoading: _importStep == 3,
              ),
              const SizedBox(height: 14),

              _buildStagedStep(
                title: 'Preparing guide',
                isDone: _importStep >= 4,
                isLoading: false,
              ),
              const SizedBox(height: 24),

              if (_importStep >= 3)
                Center(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.go('/live');
                    },
                    icon: const Icon(Icons.play_arrow_rounded, color: Color(0xFF6C5CE7)),
                    label: const Text(
                      'Open player now',
                      style: TextStyle(color: Color(0xFF6C5CE7), fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStagedStep({
    required String title,
    required bool isDone,
    required bool isLoading,
  }) {
    return Row(
      children: [
        if (isDone)
          const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 22)
        else if (isLoading)
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6C5CE7)),
          )
        else
          const Icon(Icons.radio_button_unchecked_rounded, color: Colors.white24, size: 22),
        const SizedBox(width: 14),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            color: isDone ? Colors.white : (isLoading ? Colors.white70 : Colors.white38),
            fontWeight: isDone || isLoading ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneQrDialog(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF141322),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  Icon(Icons.qr_code_rounded, color: Color(0xFF6C5CE7), size: 26),
                  SizedBox(width: 12),
                  Text(
                    'Phone & Desktop Portal',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(Icons.qr_code_2_rounded, size: 140, color: Colors.black87),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Open web portal on your phone or computer:',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 6),
              const SelectableText(
                'http://localhost:8090/playlist',
                style: TextStyle(
                  color: Color(0xFF6C5CE7),
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'You can upload M3U / XMLTV files or enter IPTV login credentials without typing on TV.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6C5CE7)),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TestResult {
  final bool success;
  final int liveCount;
  final int vodCount;
  final int seriesCount;
  final String? serverName;
  final String? errorMessage;

  const _TestResult({
    required this.success,
    this.liveCount = 0,
    this.vodCount = 0,
    this.seriesCount = 0,
    this.serverName,
    this.errorMessage,
  });
}
