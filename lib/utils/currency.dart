import 'package:intl/intl.dart';

/// Moneda de la empresa (companies.currency_symbol en el sistema web, ej. "Bs").
///
/// La fija [SessionController] al iniciar sesión / actualizar el perfil; las pantallas la usan
/// para mostrar montos ([formatter], [format]) y como prefijo de los campos de monto ([prefix]).
class Currency {
  static const String defaultSymbol = 'Bs';

  static String _symbol = defaultSymbol;

  static String get symbol => _symbol;

  /// Prefijo para campos de monto, ej. "Bs ".
  static String get prefix => '$_symbol ';

  static void setFromCompany(Map<String, dynamic>? company) {
    final value = (company?['currency_symbol'] ?? '').toString().trim();
    _symbol = value.isEmpty ? defaultSymbol : value;
  }

  static NumberFormat formatter({int? decimalDigits}) =>
      NumberFormat.currency(locale: 'es', symbol: prefix, decimalDigits: decimalDigits);

  static String format(num? value, {int? decimalDigits}) =>
      formatter(decimalDigits: decimalDigits).format(value ?? 0);
}
