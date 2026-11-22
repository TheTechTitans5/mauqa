import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings/app_settings.dart';
import '../core/theme/app_colors.dart';

/// Slowly drifting gradient used behind hero sections. Pauses when "reduce motion" or low-data is on.
class AnimatedGradientBackground extends ConsumerStatefulWidget {
  const AnimatedGradientBackground({super.key, required this.child, this.colors = AppColors.heroGradient, this.borderRadius});
  final Widget child;
  final List<Color> colors;
  final BorderRadius? borderRadius;
  @override
  ConsumerState<AnimatedGradientBackground> createState() => _AnimatedGradientBackgroundState();
}

class _AnimatedGradientBackgroundState extends ConsumerState<AnimatedGradientBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 12));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final on = ref.read(appSettingsProvider).animationsOn;
    if (on && !_c.isAnimating) _c.repeat(reverse: true);
    if (!on) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment(-1 + t, -1),
              end: Alignment(1, 1 - t),
              colors: widget.colors,
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Frosted glass surface with a soft layered shadow.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 22, this.onTap, this.tint});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final br = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: [
          BoxShadow(color: fade(AppColors.navy, dark ? 0.45 : 0.08), blurRadius: 24, offset: const Offset(0, 12)),
          BoxShadow(color: fade(AppColors.navy, dark ? 0.25 : 0.04), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: br,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Material(
            color: tint ?? (dark ? fade(Colors.white, 0.07) : fade(Colors.white, 0.82)),
            child: InkWell(
              onTap: onTap,
              child: Container(
                padding: padding,
                decoration: BoxDecoration(
                  borderRadius: br,
                  border: Border.all(color: dark ? fade(Colors.white, 0.10) : fade(Colors.white, 0.9)),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A card that gently tilts in 3D when pressed/dragged — the "floating card" effect.
class TiltCard extends ConsumerStatefulWidget {
  const TiltCard({super.key, required this.child, this.maxTilt = 0.06});
  final Widget child;
  final double maxTilt;
  @override
  ConsumerState<TiltCard> createState() => _TiltCardState();
}

class _TiltCardState extends ConsumerState<TiltCard> {
  Offset _tilt = Offset.zero;
  bool _pressed = false;

  void _update(Offset local, Size size) {
    final dx = (local.dx / size.width - 0.5) * 2;
    final dy = (local.dy / size.height - 0.5) * 2;
    setState(() => _tilt = Offset(dx.clamp(-1, 1), dy.clamp(-1, 1)));
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(appSettingsProvider).animationsOn) return widget.child;
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth.isFinite ? c.maxWidth : 300, 160);
      return Listener(
        onPointerDown: (e) { _pressed = true; _update(e.localPosition, size); },
        onPointerMove: (e) => _update(e.localPosition, size),
        onPointerUp: (_) => setState(() { _pressed = false; _tilt = Offset.zero; }),
        onPointerCancel: (_) => setState(() { _pressed = false; _tilt = Offset.zero; }),
        child: TweenAnimationBuilder<Offset>(
          tween: Tween(end: _tilt),
          duration: const Duration(milliseconds: 180),
          builder: (context, t, child) => Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateX(-t.dy * widget.maxTilt)
              ..rotateY(t.dx * widget.maxTilt)
              ..scale(_pressed ? 0.985 : 1.0),
            child: child,
          ),
          child: widget.child,
        ),
      );
    });
  }
}

/// Lightweight "3D" orb illustration drawn with radial gradients (no image assets, no 3D engine).
class Orb3D extends StatelessWidget {
  const Orb3D({super.key, this.size = 120, this.colors = const [AppColors.teal, AppColors.lavender], this.icon});
  final double size;
  final List<Color> colors;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _OrbPainter(colors),
        child: icon == null ? null : Center(child: Icon(icon, size: size * 0.36, color: Colors.white)),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.colors);
  final List<Color> colors;
  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    final r = s.width / 2 * 0.86;
    // soft floor shadow
    canvas.drawOval(Rect.fromCenter(center: c.translate(0, r * 1.02), width: r * 1.5, height: r * 0.28),
        Paint()..color = fade(AppColors.navy, 0.18)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    // body
    canvas.drawCircle(c, r, Paint()..shader = RadialGradient(
      center: const Alignment(-0.35, -0.45), radius: 1.05,
      colors: [Color.lerp(colors.first, Colors.white, 0.35)!, colors.first, colors.last],
      stops: const [0.0, 0.45, 1.0],
    ).createShader(Rect.fromCircle(center: c, radius: r)));
    // rim light
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = r * 0.04..color = fade(Colors.white, 0.25));
    // specular highlight
    canvas.drawOval(Rect.fromCenter(center: c.translate(-r * 0.32, -r * 0.42), width: r * 0.55, height: r * 0.32),
        Paint()..color = fade(Colors.white, 0.55)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    // orbit ring
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-math.pi / 9);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: r * 2.5, height: r * 0.7),
        Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = fade(AppColors.amber, 0.8));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) => old.colors != colors;
}

/// Animated circular progress with gradient stroke.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, this.size = 64, this.stroke = 7, this.label});
  final double value;
  final double size;
  final double stroke;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0, 1)),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(v, stroke, Theme.of(context).colorScheme.surfaceContainerHighest),
          child: Center(
            child: Text(label ?? '${(v * 100).round()}%',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * 0.24, color: Theme.of(context).colorScheme.onSurface)),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.stroke, this.track);
  final double v;
  final double stroke;
  final Color track;
  @override
  void paint(Canvas canvas, Size s) {
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, s.width - stroke, s.height - stroke);
    canvas.drawArc(rect, 0, math.pi * 2, false, Paint()..style = PaintingStyle.stroke..strokeWidth = stroke..color = track);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * v, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(colors: [AppColors.teal, AppColors.lavender, AppColors.amber, AppColors.teal]).createShader(rect));
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.v != v;
}

/// Shimmering placeholder used while content loads.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 16, this.width = double.infinity, this.radius = 12});
  final double height;
  final double width;
  final double radius;
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment(-1.5 + _c.value * 3, 0),
            end: Alignment(-0.5 + _c.value * 3, 0),
            colors: [base, Color.lerp(base, Colors.white, 0.35)!, base],
          ),
        ),
      ),
    );
  }
}

/// Fades + slides children in, staggered by [index].
class EntranceFade extends ConsumerWidget {
  const EntranceFade({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(appSettingsProvider).animationsOn) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + math.min(index, 8) * 60),
      curve: Curves.easeOutCubic,
      builder: (context, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 18), child: c)),
      child: child,
    );
  }
}
