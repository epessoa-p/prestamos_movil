import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

/// Hoja "archivo listo" tras una descarga: abrir el archivo o compartirlo (WhatsApp, correo…).
Future<void> showFileReadySheet(BuildContext context, {required String path, required String title, String? shareText}) {
  final name = path.split(RegExp(r'[\\/]')).last;
  final messenger = ScaffoldMessenger.of(context);

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF2A9D8F), size: 40),
            const SizedBox(height: 6),
            Text(title, textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.titleMedium),
            Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299))),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                final result = await OpenFilex.open(path);
                if (result.type != ResultType.done) {
                  messenger.showSnackBar(SnackBar(
                    content: Text(name.endsWith('.xlsx')
                        ? 'No hay una app para abrir Excel. Usa "Compartir" o instala Excel / Google Sheets.'
                        : 'No se pudo abrir el archivo. Usa "Compartir".'),
                  ));
                }
              },
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Abrir'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                SharePlus.instance.share(ShareParams(files: [XFile(path)], text: shareText));
              },
              icon: const Icon(Icons.share_rounded),
              label: const Text('Compartir'),
            ),
          ],
        ),
      ),
    ),
  );
}
