import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/color_utils.dart';

class AppHeader extends StatelessWidget {
  const AppHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppPalette.ink)),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(subtitle!, style: const TextStyle(color: Color(0xFF4E6070))),
            ),
        ],
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.wide = false,
    this.hint,
  });

  final String label;
  final String value;
  final Color color;
  final bool wide;

  /// Explicación corta debajo del valor (qué incluye la cifra).
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: wide ? MediaQuery.of(context).size.width - 52 : (MediaQuery.of(context).size.width - 64) / 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [color, color.withValues(alpha: 0.8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 7),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700)),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(hint!, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final upper = status.toUpperCase();

    final color = switch (upper) {
      'ACTIVO' || 'ACTIVE' => const Color(0xFF2A9D8F),
      'FINALIZADO' || 'FINISHED' => const Color(0xFF264653),
      'EN_MORA' || 'OVERDUE' => const Color(0xFFE76F51),
      'INCUMPLIDO' || 'DEFAULTED' => const Color(0xFFD62828),
      'CANCELADO' || 'CANCELLED' => const Color(0xFF6C757D),
      'PENDIENTE' || 'PENDING' => const Color(0xFFF4A261),
      'APROBADO' || 'APPROVED' => const Color(0xFF457B9D),
      _ => const Color(0xFF6C757D),
    };

    final label = switch (upper) {
      'ACTIVE' => 'Activo',
      'FINISHED' => 'Finalizado',
      'OVERDUE' => 'En mora',
      'DEFAULTED' => 'Incumplido',
      'CANCELLED' => 'Cancelado',
      'PENDING' => 'Pendiente',
      'APPROVED' => 'Aprobado',
      _ => status,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

class DrawerItem extends StatelessWidget {
  const DrawerItem({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppPalette.deepBlue),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}

/// Sucursal en una "pill" con su color (branches.color). [branch] puede ser un Map {name, color}
/// o null; también acepta [name]/[color] sueltos.
class BranchPill extends StatelessWidget {
  const BranchPill({super.key, this.name, this.color, this.dense = false});

  factory BranchPill.from(dynamic branch, {Key? key, bool dense = false}) {
    final map = branch is Map ? branch : const {};
    return BranchPill(key: key, name: map['name']?.toString(), color: map['color']?.toString(), dense: dense);
  }

  final String? name;
  final String? color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final label = (name ?? '').trim();
    if (label.isEmpty) return const SizedBox.shrink();
    final c = parseHexColor(color) ?? const Color(0xFF6A8299);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 9, vertical: dense ? 2 : 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: dense ? 10 : 11, fontWeight: FontWeight.w700, color: _darken(c)),
            ),
          ),
        ],
      ),
    );
  }

  static Color _darken(Color c) => Color.lerp(c, Colors.black, 0.35)!;
}

/// Tipo de pago de préstamo en español con su color.
class PaymentTypeChip extends StatelessWidget {
  const PaymentTypeChip({super.key, required this.type, this.label});

  final String type;
  final String? label;

  static const labels = {
    'interest': 'Interés',
    'penalty': 'Multa',
    'capital': 'Amortización',
    'mixed': 'Liquidación',
  };

  static Color colorFor(String type) => switch (type) {
        'interest' => const Color(0xFFE08A3C),
        'capital' => AppPalette.deepBlue,
        'mixed' => const Color(0xFF2A9D8F),
        'penalty' => AppPalette.rose,
        _ => AppPalette.ink,
      };

  @override
  Widget build(BuildContext context) {
    final color = colorFor(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(
        label ?? labels[type] ?? type,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11),
      ),
    );
  }
}

/// Código del producto (PD-00001) en una pill índigo, como en la web (`.code-pill`).
class CodePill extends StatelessWidget {
  const CodePill(this.code, {super.key});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFC7D2FE)),
      ),
      child: Text(
        code,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: .3,
          color: Color(0xFF4338CA),
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
