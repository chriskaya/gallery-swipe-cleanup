/// What a card shows: a photo preview, or a video (poster frame, then the
/// player once the card is on top).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../media/media_item.dart';
import '../l10n.dart';
import '../providers.dart';

class MediaView extends StatelessWidget {
  const MediaView({super.key, required this.item, required this.active});

  final MediaItem item;

  /// Top card: videos play. The card waiting behind only shows its poster.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final photo = PreviewImage(item: item, maxDimension: kPreviewMaxDimension);
    if (!item.isVideo) return photo;
    return active
        ? VideoView(item: item, poster: photo)
        : Stack(
            fit: StackFit.expand,
            children: [
              photo,
              const Center(child: _RoundIcon(icon: Icons.play_arrow_rounded)),
              Positioned(
                left: 12,
                bottom: 12,
                child: DurationChip(duration: item.duration),
              ),
            ],
          );
  }
}

class PreviewImage extends ConsumerWidget {
  const PreviewImage({
    super.key,
    required this.item,
    required this.maxDimension,
    this.fit = BoxFit.contain,
  });

  final MediaItem item;
  final int maxDimension;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(
      previewProvider((item: item, maxDimension: maxDimension)),
    );
    return switch (bytes) {
      AsyncData(value: final Uint8List data) => Image.memory(
        data,
        fit: fit,
        gaplessPlayback: true,
        semanticLabel: item.isVideo
            ? context.l10n.semanticsVideo
            : context.l10n.semanticsPhoto,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
            wasSynchronouslyLoaded
            ? child
            : AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 180),
                child: child,
              ),
      ),
      AsyncData() || AsyncError() => const Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: 48,
          color: Colors.white38,
        ),
      ),
      _ => const Center(
        child: SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    };
  }
}

class VideoView extends ConsumerStatefulWidget {
  const VideoView({super.key, required this.item, required this.poster});

  final MediaItem item;
  final Widget poster;

  @override
  ConsumerState<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends ConsumerState<VideoView> {
  VideoPlayerController? _controller;
  bool _failed = false;

  /// Brief play/pause glyph after a tap, then fades out.
  IconData? _flash;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    VideoPlayerController? controller;
    try {
      final uri = await ref.read(mediaLibraryProvider).contentUri(widget.item);
      if (uri == null || !mounted) return;
      controller = ref.read(videoControllerFactoryProvider)(uri);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      await controller.setVolume(ref.read(videoMutedProvider) ? 0 : 1);
      if (ref.read(settingsProvider).autoplayVideos) await controller.play();
      setState(() => _controller = controller);
    } catch (_) {
      // Unsupported codec, file gone, no player on this platform: the poster
      // stays visible with an error badge, and the card can still be swiped.
      unawaited(controller?.dispose());
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    unawaited(_controller?.dispose());
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null) return;
    final playing = c.value.isPlaying;
    playing ? await c.pause() : await c.play();
    _flashTimer?.cancel();
    setState(
      () => _flash = playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
    );
    _flashTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(videoMutedProvider, (_, muted) {
      unawaited(_controller?.setVolume(muted ? 0 : 1));
    });
    final muted = ref.watch(videoMutedProvider);
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    return GestureDetector(
      onTap: _togglePlay,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.poster,
          if (ready)
            Center(
              child: AspectRatio(
                aspectRatio: c.value.aspectRatio,
                child: VideoPlayer(c),
              ),
            ),
          if (_failed)
            const Center(child: _RoundIcon(icon: Icons.error_outline_rounded)),
          if (ready && !c.value.isPlaying && _flash == null)
            const Center(child: _RoundIcon(icon: Icons.play_arrow_rounded)),
          Center(
            child: AnimatedOpacity(
              opacity: _flash == null ? 0 : 1,
              duration: const Duration(milliseconds: 150),
              child: _RoundIcon(icon: _flash ?? Icons.play_arrow_rounded),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 16,
            child: DurationChip(duration: widget.item.duration),
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: IconButton(
              tooltip: muted ? context.l10n.unmute : context.l10n.mute,
              onPressed: ref.read(videoMutedProvider.notifier).toggle,
              icon: Icon(
                muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: Colors.white,
                shadows: const [Shadow(blurRadius: 8)],
              ),
            ),
          ),
          if (ready)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(
                c,
                allowScrubbing: false,
                padding: EdgeInsets.zero,
                colors: const VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.transparent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DurationChip extends StatelessWidget {
  const DurationChip({super.key, required this.duration});

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final m = duration.inMinutes;
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_rounded, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            '$m:$s',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Colors.black45,
      shape: BoxShape.circle,
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Icon(icon, size: 40, color: Colors.white),
    ),
  );
}
