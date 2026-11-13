import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ErrorLogService {
  static const _maxEntriesPerDay = 200;
  static const _keyPrefix = 'error_logs_';

  String _dateKey(DateTime date) {
    final day = DateFormat('yyyy-MM-dd').format(date);
    return '$_keyPrefix$day';
  }

  Future<void> logError({
    required String module,
    required Object error,
    StackTrace? stackTrace,
    String? endpoint,
  }) async {
    final now = DateTime.now();
    final item = {
      'timestamp': now.toIso8601String(),
      'module': module,
      'endpoint': endpoint,
      'error': error.toString(),
      'stack': stackTrace?.toString(),
    };

    final prefs = await SharedPreferences.getInstance();
    final key = _dateKey(now);
    final current = prefs.getStringList(key) ?? <String>[];
    current.add(jsonEncode(item));

    if (current.length > _maxEntriesPerDay) {
      current.removeRange(0, current.length - _maxEntriesPerDay);
    }

    await prefs.setStringList(key, current);

    debugPrint('[ERROR][$module] ${item['error']}');
  }

  Future<List<Map<String, dynamic>>> logsByDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _dateKey(date);
    final rows = prefs.getStringList(key) ?? <String>[];

    return rows
        .map((row) {
          try {
            final decoded = jsonDecode(row);
            if (decoded is Map<String, dynamic>) {
              return decoded;
            }
            if (decoded is Map) {
              return Map<String, dynamic>.from(decoded);
            }
            return <String, dynamic>{};
          } catch (_) {
            return <String, dynamic>{};
          }
        })
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> clearDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dateKey(date));
  }
}
