import 'package:flutter/material.dart';

class AIBackdrop extends StatelessWidget {
  final Widget child;

  const AIBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF6F8FF), Color(0xFFF5FBFF), Color(0xFFF8FAFC)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned(
            top: -120,
            right: -32,
            child: _GlowOrb(
              size: 260,
              colors: [
                Color(0x553B82F6),
                Color(0x2238BDF8),
                Colors.transparent,
              ],
            ),
          ),
          const Positioned(
            top: 180,
            left: -72,
            child: _GlowOrb(
              size: 220,
              colors: [
                Color(0x445EEAD4),
                Color(0x223B82F6),
                Colors.transparent,
              ],
            ),
          ),
          const Positioned(
            bottom: -60,
            right: -20,
            child: _GlowOrb(
              size: 220,
              colors: [
                Color(0x33A78BFA),
                Color(0x11F8FAFC),
                Colors.transparent,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class AIPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadiusGeometry borderRadius;

  const AIPanel({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xF7FFFFFF), Color(0xEAF6FBFF)],
        ),
        border: Border.all(color: const Color(0xFFDAE7FF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final List<Color> colors;

  const _GlowOrb({required this.size, required this.colors});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }
}
