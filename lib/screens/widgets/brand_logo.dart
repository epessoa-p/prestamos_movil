import 'package:flutter/material.dart';

/// Logo de Santa Ana sobre fondo blanco redondeado (login, carga inicial y menú lateral).
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 62});

  static const String asset = 'assets/images/logo-santaana.png';

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFFDFDFD),
        borderRadius: BorderRadius.circular(size * 0.29),
      ),
      clipBehavior: Clip.antiAlias,
      // El PNG tiene mucho margen blanco: se amplía para que el logo llene el recuadro.
      child: Transform.scale(
        scale: 1.45,
        child: Image.asset(asset, fit: BoxFit.contain),
      ),
    );
  }
}
