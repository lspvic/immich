import 'dart:async';
import 'dart:math';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/entities/asset.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/cast.provider.dart';
import 'package:immich_mobile/widgets/asset_grid/asset_grid_data_structure.dart';
import 'package:immich_mobile/widgets/asset_viewer/cast_dialog.dart';
import 'package:immich_mobile/widgets/common/immich_image.dart';

/// Playback order for slideshow
enum SlideshowOrder { sequential, random, reverse }

/// Transition effect used at slide boundary (affects the flash opacity)
enum SlideshowTransition { fade, slideLeft, slideRight, slideUp, scale, cube }

/// Ken Burns motion effect applied to each slide
enum _KenBurnsEffect { zoomIn, zoomOut, panLeft, panRight, panUp, panDown }

/// Speed preset durations in seconds
const Map<String, int> _speedPresets = {'slow': 8, 'medium': 5, 'fast': 3};

/// Scale factor applied for Ken Burns zoom/pan effects
const double _kenBurnsScaleAmount = 0.12;

/// Fractional pan amount (relative to screen size) for Ken Burns pan effects
const double _kenBurnsPanAmount = 0.06;

/// Progress threshold at which the transition flash starts
const double _flashStartThreshold = 0.92;

@RoutePage()
class SlideshowPage extends HookConsumerWidget {
  final RenderList renderList;

  const SlideshowPage({super.key, required this.renderList});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ────────────────────────── load image-only assets ──────────────────────────
    final assets = useMemoized(
      () {
        if (renderList.totalAssets == 0) return <Asset>[];
        return renderList.loadAssets(0, renderList.totalAssets).where((a) => a.type == AssetType.image).toList();
      },
      [renderList],
    );

    // ────────────────────────── state ──────────────────────────
    final currentIndex = useState(0);
    final order = useState(SlideshowOrder.sequential);
    final speedKey = useState('medium');
    final transition = useState(SlideshowTransition.fade);
    final showControls = useState(false);
    final isPlaying = useState(true);
    final isCasting = ref.watch(castProvider.select((c) => c.isCasting));

    // Random order support
    final randomQueue = useState(<int>[]);
    final randomIndex = useState(0);

    // Ken Burns effect for current slide
    final currentEffect = useState(_KenBurnsEffect.zoomIn);

    // Slide progress (0..1) driven by animation
    final slideProgress = useState(0.0);

    // ────────────────────────── helpers ──────────────────────────
    _KenBurnsEffect randomEffect() {
      final values = _KenBurnsEffect.values;
      return values[Random().nextInt(values.length)];
    }

    List<int> buildRandomQueue(int count) {
      final q = List<int>.generate(count, (i) => i)..shuffle(Random());
      return q;
    }

    int computeNextIndex(int current) {
      if (assets.isEmpty) return 0;
      switch (order.value) {
        case SlideshowOrder.sequential:
          return (current + 1) % assets.length;
        case SlideshowOrder.reverse:
          return (current - 1 + assets.length) % assets.length;
        case SlideshowOrder.random:
          if (randomQueue.value.isEmpty) {
            randomQueue.value = buildRandomQueue(assets.length);
            randomIndex.value = 0;
          }
          final nextRndIdx = (randomIndex.value + 1) % randomQueue.value.length;
          randomIndex.value = nextRndIdx;
          return randomQueue.value[nextRndIdx];
      }
    }

    // ────────────────────────── animation controller for slide timer ──────────────
    final slideDurationSeconds = _speedPresets[speedKey.value]!;
    final progressController = useAnimationController(
      duration: Duration(seconds: slideDurationSeconds),
    );

    // Update duration and (re)start when speed key changes
    useEffect(() {
      progressController.duration = Duration(seconds: _speedPresets[speedKey.value]!);
      if (isPlaying.value && assets.isNotEmpty) {
        progressController.forward(from: 0);
      } else {
        progressController.stop();
      }
      return null;
    }, [speedKey.value]);

    // Start / stop when playing state changes
    useEffect(() {
      if (isPlaying.value && assets.isNotEmpty) {
        progressController.forward();
      } else {
        progressController.stop();
      }
      return null;
    }, [isPlaying.value]);

    // Listen for completion to advance slide (registered once)
    useEffect(() {
      void listener() {
        slideProgress.value = progressController.value;
        if (progressController.isCompleted) {
          currentIndex.value = computeNextIndex(currentIndex.value);
          currentEffect.value = randomEffect();
          progressController.forward(from: 0);
        }
      }

      progressController.addListener(listener);
      // Start on first build
      if (assets.isNotEmpty) progressController.forward(from: 0);
      return () => progressController.removeListener(listener);
    }, []);

    // Cast current slide when casting is active
    useEffect(() {
      if (isCasting && assets.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(castProvider.notifier).loadMediaOld(assets[currentIndex.value], true);
        });
      }
      return null;
    }, [currentIndex.value]);

    // ────────────────────────── controls auto-hide ──────────────────────────
    final hideControlsTimerRef = useRef<Timer?>(null);

    void resetHideTimer() {
      hideControlsTimerRef.value?.cancel();
      hideControlsTimerRef.value = Timer(const Duration(seconds: 4), () {
        showControls.value = false;
      });
    }

    void onTap() {
      showControls.value = !showControls.value;
      if (showControls.value) resetHideTimer();
    }

    useEffect(() {
      return () => hideControlsTimerRef.value?.cancel();
    }, []);

    // ────────────────────────── system UI ──────────────────────────
    useEffect(() {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      return () => SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }, []);

    // ────────────────────────── empty state ──────────────────────────
    if (assets.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => context.maybePop(),
          ),
        ),
        body: Center(
          child: Text('no_assets_to_show', style: const TextStyle(color: Colors.white)).tr(),
        ),
      );
    }

    final current = assets[currentIndex.value];

    return GestureDetector(
      onTap: onTap,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // ── Slide with Ken Burns effect ──
            _KenBurnsSlide(
              asset: current,
              effect: currentEffect.value,
              slideDuration: Duration(seconds: slideDurationSeconds),
              isPlaying: isPlaying.value,
              // Restart when asset changes
              key: ValueKey('slide_${currentIndex.value}'),
            ),

            // ── Transition flash overlay at slide boundary ──
            _SlideTransitionFlash(
              progress: slideProgress.value,
              transition: transition.value,
            ),

            // ── Controls overlay ──
            AnimatedOpacity(
              opacity: showControls.value ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: _SlideshowControls(
                isPlaying: isPlaying.value,
                order: order.value,
                speedKey: speedKey.value,
                transition: transition.value,
                isCasting: isCasting,
                onPlayPause: () {
                  isPlaying.value = !isPlaying.value;
                  resetHideTimer();
                },
                onOrderChange: (o) {
                  order.value = o;
                  if (o == SlideshowOrder.random) {
                    randomQueue.value = buildRandomQueue(assets.length);
                    randomIndex.value = 0;
                  }
                  resetHideTimer();
                },
                onSpeedChange: (s) {
                  speedKey.value = s;
                  resetHideTimer();
                },
                onTransitionChange: (t) {
                  transition.value = t;
                  resetHideTimer();
                },
                onCast: () {
                  showDialog(
                    context: context,
                    useRootNavigator: false,
                    builder: (_) => const CastDialog(),
                  );
                  resetHideTimer();
                },
                onClose: () => context.maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Ken Burns animated slide
// ─────────────────────────────────────────────────────────
class _KenBurnsSlide extends HookWidget {
  final Asset asset;
  final _KenBurnsEffect effect;
  final Duration slideDuration;
  final bool isPlaying;

  const _KenBurnsSlide({
    super.key,
    required this.asset,
    required this.effect,
    required this.slideDuration,
    required this.isPlaying,
  });

  @override
  Widget build(BuildContext context) {
    final controller = useAnimationController(duration: slideDuration);

    useEffect(() {
      if (isPlaying) {
        controller.forward(from: 0);
      } else {
        controller.stop();
        controller.reset();
      }
      return null;
    }, [isPlaying]);

    late final Animation<double> scaleAnim;
    late final Animation<Offset> offsetAnim;

    switch (effect) {
      case _KenBurnsEffect.zoomIn:
        scaleAnim = Tween<double>(begin: 1.0, end: 1.0 + _kenBurnsScaleAmount).animate(
          CurvedAnimation(parent: controller, curve: Curves.easeInOut),
        );
        offsetAnim = AlwaysStoppedAnimation(Offset.zero);
        break;
      case _KenBurnsEffect.zoomOut:
        scaleAnim = Tween<double>(begin: 1.0 + _kenBurnsScaleAmount, end: 1.0).animate(
          CurvedAnimation(parent: controller, curve: Curves.easeInOut),
        );
        offsetAnim = AlwaysStoppedAnimation(Offset.zero);
        break;
      case _KenBurnsEffect.panLeft:
        scaleAnim = AlwaysStoppedAnimation(1.0 + _kenBurnsScaleAmount);
        offsetAnim = Tween<Offset>(
          begin: const Offset(_kenBurnsPanAmount, 0),
          end: const Offset(-_kenBurnsPanAmount, 0),
        ).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));
        break;
      case _KenBurnsEffect.panRight:
        scaleAnim = AlwaysStoppedAnimation(1.0 + _kenBurnsScaleAmount);
        offsetAnim = Tween<Offset>(
          begin: const Offset(-_kenBurnsPanAmount, 0),
          end: const Offset(_kenBurnsPanAmount, 0),
        ).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));
        break;
      case _KenBurnsEffect.panUp:
        scaleAnim = AlwaysStoppedAnimation(1.0 + _kenBurnsScaleAmount);
        offsetAnim = Tween<Offset>(
          begin: const Offset(0, _kenBurnsPanAmount),
          end: const Offset(0, -_kenBurnsPanAmount),
        ).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));
        break;
      case _KenBurnsEffect.panDown:
        scaleAnim = AlwaysStoppedAnimation(1.0 + _kenBurnsScaleAmount);
        offsetAnim = Tween<Offset>(
          begin: const Offset(0, -_kenBurnsPanAmount),
          end: const Offset(0, _kenBurnsPanAmount),
        ).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));
        break;
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(
            offsetAnim.value.dx * context.width,
            offsetAnim.value.dy * context.height,
          ),
          child: Transform.scale(scale: scaleAnim.value, child: child),
        );
      },
      child: SizedBox.expand(
        child: Image(
          image: ImmichImage.imageProvider(asset: asset, width: context.width, height: context.height),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: Colors.black,
            child: const Icon(Icons.broken_image, color: Colors.white54, size: 64),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Transition flash overlay shown near end of each slide
// ─────────────────────────────────────────────────────────
class _SlideTransitionFlash extends StatelessWidget {
  final double progress; // 0..1
  final SlideshowTransition transition;

  const _SlideTransitionFlash({required this.progress, required this.transition});

  @override
  Widget build(BuildContext context) {
    if (progress <= _flashStartThreshold) return const SizedBox.shrink();

    final flashDuration = 1.0 - _flashStartThreshold;
    final ratio = ((progress - _flashStartThreshold) / flashDuration).clamp(0.0, 1.0);
    final maxOpacity = switch (transition) {
      SlideshowTransition.fade => 0.7,
      SlideshowTransition.scale => 0.7,
      SlideshowTransition.cube => 0.85,
      _ => 0.5,
    };

    return Opacity(
      opacity: ratio * maxOpacity,
      child: const ColoredBox(color: Colors.black, child: SizedBox.expand()),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Controls overlay (top bar + bottom bar)
// ─────────────────────────────────────────────────────────
class _SlideshowControls extends StatelessWidget {
  final bool isPlaying;
  final SlideshowOrder order;
  final String speedKey;
  final SlideshowTransition transition;
  final bool isCasting;
  final VoidCallback onPlayPause;
  final void Function(SlideshowOrder) onOrderChange;
  final void Function(String) onSpeedChange;
  final void Function(SlideshowTransition) onTransitionChange;
  final VoidCallback onCast;
  final VoidCallback onClose;

  const _SlideshowControls({
    required this.isPlaying,
    required this.order,
    required this.speedKey,
    required this.transition,
    required this.isCasting,
    required this.onPlayPause,
    required this.onOrderChange,
    required this.onSpeedChange,
    required this.onTransitionChange,
    required this.onCast,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Top gradient + close / cast ──
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xCC000000), Colors.transparent],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    _ControlButton(icon: Icons.close, tooltip: 'close', onPressed: onClose),
                    const Spacer(),
                    _ControlButton(
                      icon: isCasting ? Icons.cast_connected : Icons.cast,
                      tooltip: 'cast',
                      highlighted: isCasting,
                      onPressed: onCast,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Bottom gradient + controls ──
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xCC000000), Colors.transparent],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Row 1: Play + Order
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ControlButton(
                          icon: isPlaying ? Icons.pause_circle_outline : Icons.play_circle_outline,
                          tooltip: isPlaying ? 'pause' : 'play',
                          size: 40,
                          onPressed: onPlayPause,
                        ),
                        const SizedBox(width: 12),
                        _ControlButton(
                          icon: Icons.format_list_numbered_rtl,
                          tooltip: 'slideshow_order_sequential',
                          highlighted: order == SlideshowOrder.sequential,
                          onPressed: () => onOrderChange(SlideshowOrder.sequential),
                        ),
                        const SizedBox(width: 4),
                        _ControlButton(
                          icon: Icons.shuffle,
                          tooltip: 'slideshow_order_random',
                          highlighted: order == SlideshowOrder.random,
                          onPressed: () => onOrderChange(SlideshowOrder.random),
                        ),
                        const SizedBox(width: 4),
                        _ControlButton(
                          icon: Icons.swap_vert,
                          tooltip: 'slideshow_order_reverse',
                          highlighted: order == SlideshowOrder.reverse,
                          onPressed: () => onOrderChange(SlideshowOrder.reverse),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Row 2: Speed + Transition
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'slideshow_speed',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ).tr(),
                          const SizedBox(width: 6),
                          for (final s in ['slow', 'medium', 'fast'])
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: _SpeedChip(label: s, selected: speedKey == s, onTap: () => onSpeedChange(s)),
                            ),
                          const SizedBox(width: 14),
                          Text(
                            'slideshow_transition',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ).tr(),
                          const SizedBox(width: 6),
                          for (final t in SlideshowTransition.values)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: _TransitionChip(
                                transition: t,
                                selected: transition == t,
                                onTap: () => onTransitionChange(t),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// Small icon button with optional highlight
// ─────────────────────────────────────────────────────────
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final double size;
  final bool highlighted;
  final VoidCallback onPressed;

  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 28,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = highlighted ? Colors.amber : Colors.white;
    return Tooltip(
      message: tooltip.tr(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(size),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              color: color,
              size: size,
              shadows: const [Shadow(blurRadius: 4)],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Speed chip (Slow / Medium / Fast)
// ─────────────────────────────────────────────────────────
class _SpeedChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SpeedChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.amber.withAlpha(200) : Colors.white.withAlpha(50),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'slideshow_speed_$label'.tr(),
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Transition icon chip
// ─────────────────────────────────────────────────────────
class _TransitionChip extends StatelessWidget {
  final SlideshowTransition transition;
  final bool selected;
  final VoidCallback onTap;

  const _TransitionChip({required this.transition, required this.selected, required this.onTap});

  static IconData _icon(SlideshowTransition t) => switch (t) {
        SlideshowTransition.fade => Icons.gradient,
        SlideshowTransition.slideLeft => Icons.arrow_forward,
        SlideshowTransition.slideRight => Icons.arrow_back,
        SlideshowTransition.slideUp => Icons.arrow_upward,
        SlideshowTransition.scale => Icons.zoom_in,
        SlideshowTransition.cube => Icons.view_in_ar,
      };

  static String _tooltip(SlideshowTransition t) => switch (t) {
        SlideshowTransition.fade => 'slideshow_transition_fade',
        SlideshowTransition.slideLeft => 'slideshow_transition_slide_left',
        SlideshowTransition.slideRight => 'slideshow_transition_slide_right',
        SlideshowTransition.slideUp => 'slideshow_transition_slide_up',
        SlideshowTransition.scale => 'slideshow_transition_scale',
        SlideshowTransition.cube => 'slideshow_transition_cube',
      };

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _tooltip(transition).tr(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: selected ? Colors.amber.withAlpha(200) : Colors.white.withAlpha(50),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(_icon(transition), size: 14, color: selected ? Colors.black : Colors.white),
        ),
      ),
    );
  }
}
