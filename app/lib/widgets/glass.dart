import 'package:flutter/material.dart';

/// Panel oscuro translúcido para los controles sobre el tablero.
///
/// Antes era vidrio esmerilado (BackdropFilter), pero desenfocar el fondo
/// animado en cada frame es caro en Android; un tono oscuro con degradé se ve
/// casi igual.
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.padding = const EdgeInsets.all(12), this.radius = 20});

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.62), Colors.black.withValues(alpha: 0.74)],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: child,
    );
  }
}
