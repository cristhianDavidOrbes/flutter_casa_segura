import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:flutter_seguridad_en_casa/core/presentation/widgets/theme_toggle_button.dart';
import 'package:flutter_seguridad_en_casa/features/ai/data/ai_assistant_service.dart';
import 'package:flutter_seguridad_en_casa/features/ai/domain/ai_message.dart';
import 'package:flutter_seguridad_en_casa/repositories/device_repository.dart';
import 'package:flutter_seguridad_en_casa/services/remote_device_service.dart';

class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({super.key});

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage>
    with TickerProviderStateMixin {
  final _service = AiAssistantService();
  final DeviceRepository _deviceRepository = DeviceRepository.instance;
  final RemoteDeviceService _remoteService = RemoteDeviceService();
  final _messages = <AiMessage>[];
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  bool _isTyping = false;
  bool _showVideoPanel = false;
  bool _showDetectionPanel = false;
  bool _doorOpen = false;
  String? _videoUrl;

  VideoPlayerController? _videoController;
  late final AnimationController _videoAnimCtrl;
  late final AnimationController _detectionAnimCtrl;

  @override
  void initState() {
    super.initState();
    _videoAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _detectionAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _videoController?.dispose();
    _videoAnimCtrl.dispose();
    _detectionAnimCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;

    _inputCtrl.clear();
    final userMessage = AiMessage(
      role: AiMessageRole.user,
      text: text,
      timestamp: DateTime.now(),
    );
    setState(() {
      _messages.add(userMessage);
    });
    _scrollToBottom();

    _evaluateCommand(text);

    setState(() => _isTyping = true);
    final reply = await _service.generateReply(_messages);
    if (!mounted) return;

    setState(() {
      _messages.add(AiMessage(role: AiMessageRole.assistant, text: reply));
      _isTyping = false;
    });
    _scrollToBottom();
  }

  void _evaluateCommand(String text) {
    final lower = text.toLowerCase();
    final wantsVideo =
        lower.contains('ver el video') || lower.contains('muestra video');
    final removeVideo =
        lower.contains('quita el video') ||
        lower.contains('oculta video') ||
        lower.contains('cerrar video');
    final wantsDetection =
        lower.contains('detección') || lower.contains('deteccion');
    final removeDetection =
        lower.contains('oculta detección') ||
        lower.contains('oculta deteccion') ||
        lower.contains('quitar detección') ||
        lower.contains('quitar deteccion');
    final openDoor =
        lower.contains('abrir la puerta') || lower.contains('abre la puerta');
    final closeDoor =
        lower.contains('cerrar la puerta') ||
        lower.contains('cierra la puerta');

    if (wantsVideo) {
      _ensureVideo();
      _videoAnimCtrl.forward();
    } else if (removeVideo) {
      _hideVideo();
    }

    if (wantsDetection) {
      _hideVideo();
      setState(() => _showDetectionPanel = true);
      _detectionAnimCtrl.forward();
    } else if (removeDetection) {
      _detectionAnimCtrl.reverse().then((_) {
        if (!mounted) return;
        setState(() => _showDetectionPanel = false);
      });
    }

    if (openDoor || closeDoor) {
      final targetState = openDoor;
      setState(() => _doorOpen = targetState);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              targetState
                  ? 'Puerta principal abierta (simulación).'
                  : 'Puerta principal cerrada (simulación).',
            ),
          ),
        );
      });
    }
  }

  Future<void> _ensureVideo() async {
    if (_videoController != null) {
      _videoController!
        ..setLooping(true)
        ..play();
      setState(() => _showVideoPanel = true);
      return;
    }

    setState(() => _showVideoPanel = true);

    final stream = await _resolveCameraStreamUrl();
    VideoPlayerController controller;
    if (stream != null) {
      controller = VideoPlayerController.networkUrl(Uri.parse(stream));
    } else {
      controller = VideoPlayerController.asset('assets/carga.mp4');
    }

    await controller.initialize();
    controller
      ..setLooping(true)
      ..setVolume(0)
      ..play();

    setState(() {
      _videoUrl = stream;
      _videoController = controller;
    });
  }

  void _hideVideo() {
    if (_videoController != null) {
      _videoController!.pause();
    }
    _videoAnimCtrl.reverse().then((_) {
      if (!mounted) return;
      setState(() => _showVideoPanel = false);
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

  Future<String?> _resolveCameraStreamUrl() async {
    try {
      final devices = await _deviceRepository.listDevices();
      for (final device in devices) {
        final type = device.type.toLowerCase();
        if (type.contains('cam')) {
          final signals = await _remoteService.fetchLiveSignals(device.id);
          for (final signal in signals) {
            final stream = signal.extra['stream'];
            if (stream is String && stream.trim().isNotEmpty) {
              return stream.trim();
            }
            final snapshot = signal.snapshotPath;
            if (snapshot != null && snapshot.isNotEmpty) {
              return snapshot;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('No camera stream available: $e');
    }
    return null;
  }

  void _sendSuggested(String text) {
    _handleSubmit(text);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asistente IA'),
        actions: const [ThemeToggleButton()],
      ),
      body: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [cs.surface, cs.surfaceVariant.withOpacity(0.7)],
              ),
            ),
          ),
          Column(
            children: [
              AnimatedBuilder(
                animation: _videoAnimCtrl,
                builder: (context, child) {
                  return SizeTransition(
                    sizeFactor: CurvedAnimation(
                      parent: _videoAnimCtrl,
                      curve: Curves.easeInOut,
                    ),
                    axisAlignment: -1,
                    child: SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(0, -1),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: _videoAnimCtrl,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                      child: child!,
                    ),
                  );
                },
                child: _showVideoPanel
                    ? _VideoPanel(
                        controller: _videoController,
                        videoUrl: _videoUrl,
                      )
                    : const SizedBox.shrink(),
              ),
              AnimatedBuilder(
                animation: _detectionAnimCtrl,
                builder: (context, child) {
                  return SizeTransition(
                    sizeFactor: CurvedAnimation(
                      parent: _detectionAnimCtrl,
                      curve: Curves.easeInOut,
                    ),
                    axisAlignment: -1,
                    child: SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(0, -0.3),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: _detectionAnimCtrl,
                              curve: Curves.easeOut,
                            ),
                          ),
                      child: child!,
                    ),
                  );
                },
                child: _showDetectionPanel
                    ? _DetectionPanel(doorOpen: _doorOpen)
                    : const SizedBox.shrink(),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.only(bottom: 16, top: 12),
                    itemCount: _messages.length + (_isTyping ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_isTyping && index == _messages.length) {
                        return const _TypingBubble();
                      }
                      final message = _messages[index];
                      return _AiMessageBubble(message: message);
                    },
                  ),
                ),
              ),
              _QuickActions(onSelected: _sendSuggested),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: _InputBar(
                    controller: _inputCtrl,
                    onSend: _handleSubmit,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VideoPanel extends StatelessWidget {
  const _VideoPanel({required this.controller, required this.videoUrl});

  final VideoPlayerController? controller;
  final String? videoUrl;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (controller == null || !controller!.value.isInitialized) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        height: 160,
        decoration: BoxDecoration(
          color: cs.surfaceVariant,
          borderRadius: BorderRadius.circular(18),
        ),
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.9),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: controller!.value.aspectRatio,
              child: VideoPlayer(controller!),
            ),
            if (videoUrl != null)
              Positioned(
                left: 8,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    videoUrl!,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetectionPanel extends StatelessWidget {
  const _DetectionPanel({required this.doorOpen});

  final bool doorOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(0.35),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumen de sensores',
            style: TextStyle(
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _InfoChip(
                icon: Icons.security_outlined,
                label: 'Puerta principal',
                value: doorOpen ? 'Abierta' : 'Cerrada',
                color: doorOpen ? cs.error : cs.secondary,
              ),
              _InfoChip(
                icon: Icons.sensors,
                label: 'Detector movimiento',
                value: 'Activo',
                color: cs.primary,
              ),
              _InfoChip(
                icon: Icons.lightbulb_outline,
                label: 'Iluminación',
                value: 'Automática',
                color: cs.tertiary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Text(value, style: TextStyle(color: color.withOpacity(0.9))),
        ],
      ),
    );
  }
}

class _AiMessageBubble extends StatelessWidget {
  const _AiMessageBubble({required this.message});

  final AiMessage message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUser = message.role == AiMessageRole.user;
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final bgColor = isUser ? cs.primary : cs.surfaceVariant.withOpacity(0.9);
    final fgColor = isUser ? cs.onPrimary : cs.onSurface;

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            message.text,
            style: TextStyle(color: fgColor, fontSize: 15),
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final value = _controller.value;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                final offset = (value + index / 3) % 1;
                final opacity =
                    0.3 + (offset < 0.5 ? offset * 1.4 : (1 - offset) * 1.4);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: CircleAvatar(
                    radius: 4,
                    backgroundColor: cs.primary.withOpacity(
                      opacity.clamp(0.2, 1),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final actions = <String>[
      'Quiero ver el video',
      'Muestra las detecciones',
      'Abrir la puerta',
      'Cierra la puerta',
      'Dame un resumen de seguridad',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: actions.map((action) {
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ActionChip(
                label: Text(action),
                backgroundColor: cs.surfaceVariant,
                onPressed: () => onSelected(action),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.onSend});

  final TextEditingController controller;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            textInputAction: TextInputAction.send,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              filled: true,
              fillColor: cs.surfaceVariant.withOpacity(0.6),
              hintText: 'Escribe tu mensaje',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            onSubmitted: onSend,
          ),
        ),
        const SizedBox(width: 10),
        FloatingActionButton.small(
          onPressed: () => onSend(controller.text),
          tooltip: 'Enviar',
          child: const Icon(Icons.send_rounded),
        ),
      ],
    );
  }
}
