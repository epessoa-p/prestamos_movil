import 'package:flutter/services.dart';

/// Escribe en MAYÚSCULAS mientras se tipea (igual que los formularios de la web, `base.blade.php`).
/// Se usa en los campos de texto libre (nombres, marcas, detalles, notas); no en correo, contraseña,
/// teléfono, enlaces, números ni búsquedas.
class UpperCaseTextFormatter extends TextInputFormatter {
  const UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final upper = newValue.text.toUpperCase();
    if (upper == newValue.text) return newValue;
    // Algunas letras cambian de largo al pasar a mayúscula (ß → SS): el cursor va al final.
    final selection = upper.length == newValue.text.length
        ? newValue.selection
        : TextSelection.collapsed(offset: upper.length);
    return newValue.copyWith(text: upper, selection: selection, composing: TextRange.empty);
  }
}

/// `inputFormatters` para un campo en mayúsculas.
const List<TextInputFormatter> upperCaseFormatters = [UpperCaseTextFormatter()];

/// true si un campo con este teclado debe ir en mayúsculas (misma exclusión que la web).
bool upperCaseFor(TextInputType? keyboardType) {
  if (keyboardType == null) return true;
  final name = keyboardType.toJson()['name'];
  return name == 'TextInputType.text' || name == 'TextInputType.multiline';
}
