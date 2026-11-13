import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/error_log_service.dart';

class ErrorLogsScreen extends StatefulWidget {
  const ErrorLogsScreen({super.key, required this.logger});

  final ErrorLogService logger;

  @override
  State<ErrorLogsScreen> createState() => _ErrorLogsScreenState();
}

class _ErrorLogsScreenState extends State<ErrorLogsScreen> {
  List<Map<String, dynamic>> _logs = <Map<String, dynamic>>[];
  bool _loading = true;
  final _date = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await widget.logger.logsByDate(_date);
    if (!mounted) return;
    setState(() {
      _logs = rows.reversed.toList(growable: false);
      _loading = false;
    });
  }

  Future<void> _clear() async {
    await widget.logger.clearDate(_date);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final dateText = DateFormat('yyyy-MM-dd').format(_date);

    return Scaffold(
      appBar: AppBar(
        title: Text('Errores $dateText'),
        actions: [
          IconButton(
            onPressed: _clear,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Limpiar logs del día',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? const Center(child: Text('No hay errores registrados hoy'))
              : ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final item = _logs[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['timestamp']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            Text('Módulo: ${item['module'] ?? '-'}'),
                            Text('Endpoint: ${item['endpoint'] ?? '-'}'),
                            const SizedBox(height: 6),
                            Text(item['error']?.toString() ?? '-'),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
