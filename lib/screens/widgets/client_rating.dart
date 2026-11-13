import 'package:flutter/material.dart';

/// Categorías de cliente, en el mismo orden y con los mismos colores que la web
/// (App\Services\ClientRating::CATEGORIES).
const clientRatingCategories = <String, ({String label, IconData icon, Color color, Color bg})>{
  'fiel': (label: 'Cliente fiel', icon: Icons.star_rounded, color: Color(0xFFB45309), bg: Color(0xFFFEF3C7)),
  'puntual': (label: 'Puntual', icon: Icons.check_circle_rounded, color: Color(0xFF15803D), bg: Color(0xFFDCFCE7)),
  'regular': (label: 'Regular', icon: Icons.remove_circle_rounded, color: Color(0xFF475569), bg: Color(0xFFF1F5F9)),
  'riesgo': (label: 'Riesgo', icon: Icons.report_rounded, color: Color(0xFFB91C1C), bg: Color(0xFFFEE2E2)),
  'nuevo': (label: 'Nuevo', icon: Icons.auto_awesome_rounded, color: Color(0xFF1D4ED8), bg: Color(0xFFDBEAFE)),
};

/// Color '#rrggbb' de la API; [fallback] si no es válido.
Color hexColor(String? hex, {Color fallback = const Color(0xFF4F46E5)}) {
  final value = int.tryParse((hex ?? '').replaceFirst('#', ''), radix: 16);
  return value == null ? fallback : Color(0xFF000000 | value);
}

/// Etiqueta manual del cliente (ej. VIP) con el color del catálogo de la empresa.
class ClientTagChip extends StatelessWidget {
  const ClientTagChip({super.key, required this.name, this.color});

  final String name;
  final String? color;

  @override
  Widget build(BuildContext context) {
    final c = hexColor(color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sell_rounded, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
        ],
      ),
    );
  }
}

/// Chip con la categoría del cliente. [rating] es el objeto `rating` de la API.
class ClientRatingChip extends StatelessWidget {
  const ClientRatingChip({super.key, required this.rating, this.showPunctuality = false});

  final Map<String, dynamic> rating;
  final bool showPunctuality;

  @override
  Widget build(BuildContext context) {
    final key = rating['key']?.toString() ?? 'nuevo';
    final meta = clientRatingCategories[key] ?? clientRatingCategories['nuevo']!;
    final punctuality = rating['punctuality'];
    final label = rating['label']?.toString() ?? meta.label;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: meta.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: meta.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meta.icon, size: 13, color: meta.color),
          const SizedBox(width: 4),
          Text(
            showPunctuality && punctuality != null ? '$label · $punctuality%' : label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: meta.color),
          ),
        ],
      ),
    );
  }
}
