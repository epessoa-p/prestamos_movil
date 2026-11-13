import 'package:flutter/material.dart';

/// Color "#RRGGBB" (o "#RGB"), o null si no es válido.
Color? parseHexColor(String? hex) {
  var h = (hex ?? '').replaceAll('#', '').trim();
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length != 6) return null;
  final value = int.tryParse(h, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}
