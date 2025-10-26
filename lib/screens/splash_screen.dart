import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class SplashScreen extends StatefulWidget {
  final Widget nextPage;

  const SplashScreen({super.key, required this.nextPage});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _showNext = false;
  late final VideoPlayerController _videoController;
  late final Future<void> _initializeVideo;
  bool _videoReleased = false;

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.asset('assets/carga.mp4');
    _initializeVideo = _videoController.initialize().then((_) {
      _videoController
        ..setLooping(true)
        ..setVolume(0)
        ..play();
      if (mounted) setState(() {});
    });

    // Espera 5 segundos antes de ir a la siguiente pantalla
    Timer(const Duration(seconds: 5), () {
      if (mounted) {
        _releaseVideoController();
        setState(() => _showNext = true);
      }
    });
  }

  @override
  void dispose() {
    _releaseVideoController();
    super.dispose();
  }

  void _releaseVideoController() {
    if (_videoReleased) return;
    _videoReleased = true;
    if (_videoController.value.isInitialized) {
      _videoController.pause();
    }
    _videoController.dispose();
  }

  Widget _buildVideoLoader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_videoReleased) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<void>(
      future: _initializeVideo,
      builder: (context, snapshot) {
        final initialized =
            snapshot.connectionState == ConnectionState.done &&
            _videoController.value.isInitialized;

        Widget inner;
        if (initialized) {
          inner = AspectRatio(
            aspectRatio: _videoController.value.aspectRatio,
            child: VideoPlayer(_videoController),
          );
        } else {
          inner = const AspectRatio(
            aspectRatio: 16 / 9,
            child: Center(child: _SplashLoaderFallback()),
          );
        }

        return Container(
          width: 260,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: cs.onPrimary.withValues(alpha: 0.6),
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: inner,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final splash = Scaffold(
      backgroundColor: cs.primary,
      body: Center(child: _buildVideoLoader(context)),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        TickerMode(
          enabled: _showNext,
          child: Offstage(offstage: !_showNext, child: widget.nextPage),
        ),
        Offstage(offstage: _showNext, child: splash),
      ],
    );
  }
}

class _SplashLoaderFallback extends StatelessWidget {
  const _SplashLoaderFallback();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 42,
      height: 42,
      child: CircularProgressIndicator(
        strokeWidth: 3,
        valueColor: AlwaysStoppedAnimation<Color>(cs.onPrimary),
      ),
    );
  }
}
