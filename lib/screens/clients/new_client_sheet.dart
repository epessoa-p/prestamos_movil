import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../controllers/create_client_controller.dart';
import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/upper_case.dart';
import '../widgets/client_rating.dart' show hexColor;

class NewClientSheet extends StatefulWidget {
  const NewClientSheet({
    super.key,
    required this.api,
    required this.logger,
    required this.permissions,
    this.isCashOpen = false,
    this.initialClient,
  });

  final ApiService api;
  final ErrorLogService logger;
  final List<String> permissions;
  final bool isCashOpen;
  /// Cliente a editar (respuesta de GET /clients/{id}); null = alta de un cliente nuevo.
  final Map<String, dynamic>? initialClient;

  @override
  State<NewClientSheet> createState() => _NewClientSheetState();
}

class _DocEntry {
  _DocEntry({required this.path}) : labelCtrl = TextEditingController();
  final String path;
  final TextEditingController labelCtrl;
  void dispose() => labelCtrl.dispose();
}

class _NewClientSheetState extends State<NewClientSheet> {
  late final CreateClientController _ctrl;
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();

  final _nameCtrl        = TextEditingController();
  final _idNumberCtrl    = TextEditingController();
  final _phoneCtrl       = TextEditingController();
  final _emailCtrl       = TextEditingController();
  final _addressCtrl     = TextEditingController();
  final _notesCtrl       = TextEditingController();
  final _locationUrlCtrl = TextEditingController();

  LatLng? _selectedLatLng;
  String? _photoPath;
  final List<_DocEntry> _docEntries = [];

  // Etiqueta (solo con permiso "Etiquetar clientes"); catálogo de la empresa.
  List<Map<String, dynamic>> _tagOptions = [];
  String? _tag;

  // Solo en edición: foto y documentos que ya tiene el cliente.
  String? _existingPhotoUrl;
  bool _removePhoto = false;
  List<Map<String, dynamic>> _existingDocs = [];
  int? _deletingDocId;

  bool get _isEdit => widget.initialClient != null;
  int? get _clientId => int.tryParse('${widget.initialClient?['id']}');

  @override
  void initState() {
    super.initState();
    _ctrl = CreateClientController(api: widget.api, logger: widget.logger);
    final c = widget.initialClient;
    if (c != null) {
      String text(String key) => (c[key] ?? '').toString();
      _nameCtrl.text = text('name');
      _idNumberCtrl.text = text('id_number');
      _phoneCtrl.text = text('phone');
      _emailCtrl.text = text('email');
      _addressCtrl.text = text('address');
      _notesCtrl.text = text('notes');
      _locationUrlCtrl.text = text('location_url');
      final lat = double.tryParse(text('location_lat'));
      final lng = double.tryParse(text('location_lng'));
      if (lat != null && lng != null) _selectedLatLng = LatLng(lat, lng);
      _tag = text('tag').isEmpty ? null : text('tag');
      _existingPhotoUrl = c['photo_url']?.toString();
      _existingDocs = ((c['documents'] as List?) ?? const [])
          .whereType<Map>()
          .map((d) => d.cast<String, dynamic>())
          .toList();
    }
    if (widget.permissions.contains('clients.tag')) _loadTags();
  }

  /// Elimina en el momento un documento que ya estaba guardado (con confirmación).
  Future<void> _deleteExistingDoc(Map<String, dynamic> doc) async {
    final id = int.tryParse('${doc['id']}');
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar documento'),
        content: Text('¿Eliminar "${doc['label'] ?? doc['original_name'] ?? 'documento'}"? No se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppPalette.rose),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _deletingDocId = id);
    try {
      await widget.api.deleteClientDocument(id);
      if (mounted) setState(() => _existingDocs.removeWhere((d) => '${d['id']}' == '$id'));
    } catch (e, st) {
      await widget.logger.logError(module: 'edit_client', error: e, stackTrace: st, endpoint: '/clients/documents/$id');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo eliminar el documento.'), backgroundColor: AppPalette.rose),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingDocId = null);
    }
  }

  Future<void> _loadTags() async {
    try {
      final data = await widget.api.clientTags();
      if (!mounted || data['can_tag'] != true) return;
      setState(() {
        _tagOptions = ((data['tags'] as List?) ?? const [])
            .whereType<Map>()
            .map((t) => t.cast<String, dynamic>())
            .toList();
        // La etiqueta actual se conserva aunque ya no esté en el catálogo (igual que la web).
        if (_tag != null && !_tagOptions.any((t) => t['name'] == _tag)) {
          _tagOptions.add({'name': _tag, 'color': widget.initialClient?['tag_color']});
        }
      });
    } catch (e, st) {
      // Sin catálogo simplemente no se muestra el selector.
      await widget.logger.logError(module: 'client_tags', error: e, stackTrace: st, endpoint: '/clients/tags');
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _nameCtrl.dispose();
    _idNumberCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    _locationUrlCtrl.dispose();
    for (final e in _docEntries) {
      e.dispose();
    }
    super.dispose();
  }

  Future<void> _openMapPicker() async {
    final result = await Navigator.of(context).push<LatLng?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _MapPickerScreen(initialLocation: _selectedLatLng),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _selectedLatLng = result;
        _locationUrlCtrl.text =
            'https://maps.google.com/?q=${result.latitude},${result.longitude}';
      });
    }
  }

  void _clearLocation() {
    setState(() {
      _selectedLatLng = null;
      _locationUrlCtrl.clear();
    });
  }

  Future<void> _pickPhoto() async {
    final source = await _showSourceSheet();
    if (source == null) return;
    final picked = await _imagePicker.pickImage(source: source, imageQuality: 80, maxWidth: 800);
    if (picked != null && mounted) {
      setState(() {
        _photoPath = picked.path;
        _removePhoto = false;
      });
    }
  }

  Future<void> _pickDocument() async {
    if (_docEntries.length >= 10) return;
    final source = await _showSourceSheet(forDocument: true);
    if (source == null) return;
    final picked =
        await _imagePicker.pickImage(source: source, imageQuality: 85, maxWidth: 1200);
    if (picked != null && mounted) {
      setState(() => _docEntries.add(_DocEntry(path: picked.path)));
    }
  }

  Future<ImageSource?> _showSourceSheet({bool forDocument = false}) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (forDocument)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: const Text('Agregar documento',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: Text(forDocument ? 'Cámara (escanear documento)' : 'Cámara'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
  }

  void _removeDoc(int index) {
    setState(() {
      _docEntries[index].dispose();
      _docEntries.removeAt(index);
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final ok = await _ctrl.submitClient(
      clientId: _clientId,
      locationLat: _selectedLatLng?.latitude,
      locationLng: _selectedLatLng?.longitude,
      removePhoto: _removePhoto,
      name: _nameCtrl.text.trim(),
      idNumber: _idNumberCtrl.text.trim().isNotEmpty ? _idNumberCtrl.text.trim() : null,
      phone: _phoneCtrl.text.trim().isNotEmpty ? _phoneCtrl.text.trim() : null,
      email: _emailCtrl.text.trim().isNotEmpty ? _emailCtrl.text.trim() : null,
      address: _addressCtrl.text.trim().isNotEmpty ? _addressCtrl.text.trim() : null,
      notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
      locationUrl: _locationUrlCtrl.text.trim().isNotEmpty
          ? _locationUrlCtrl.text.trim()
          : null,
      photoPath: _photoPath,
      docPaths: _docEntries.map((e) => e.path).toList(),
      docLabels: _docEntries.map((e) => e.labelCtrl.text.trim()).toList(),
      tag: _tag,
    );
    if (!ok || !mounted) return;
    if (_isEdit) {
      Navigator.of(context).pop({'client': _ctrl.createdClient, 'updated': true});
    } else {
      setState(() {});
    }
  }

  String? _fieldErr(String key) => _ctrl.validationErrors[key];

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF4F8FC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFFCDD8E3),
                    borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 10),
                child: Row(
                  children: [
                    Text(_isEdit ? 'Editar cliente' : 'Nuevo Cliente',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.ink)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: _ctrl.createdClient != null && !_isEdit
                    ? _buildSuccess(_ctrl.createdClient!)
                    : _buildForm(),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Success state ─────────────────────────────────────────────────────────

  Widget _buildSuccess(Map<String, dynamic> client) {
    final name = client['name']?.toString() ?? '';
    final photoUrl = client['photo_url']?.toString();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'C';
    final canLoan = widget.permissions.contains('loans.create') && widget.isCashOpen;
    final docs = (client['documents'] as List?)?.cast<Map>() ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration:
                      const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 32),
                ),
                const SizedBox(height: 14),
                const Text('¡Cliente registrado!',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF15803D))),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    photoUrl != null && photoUrl.isNotEmpty
                        ? CircleAvatar(
                            radius: 22,
                            backgroundColor: AppPalette.deepBlue.withValues(alpha: 0.12),
                            backgroundImage: NetworkImage(photoUrl),
                            onBackgroundImageError: (_, _) {},
                          )
                        : CircleAvatar(
                            radius: 22,
                            backgroundColor: AppPalette.deepBlue,
                            child: Text(initial,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18)),
                          ),
                    const SizedBox(width: 12),
                    Text(name,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.ink)),
                  ],
                ),
                if (docs.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${docs.length} documento${docs.length > 1 ? 's' : ''} adjunto${docs.length > 1 ? 's' : ''}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF15803D)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () =>
                Navigator.of(context).pop({'client': client, 'createLoan': false}),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Cerrar'),
          ),
          if (canLoan) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop({'client': client, 'createLoan': true}),
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.deepBlue,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.account_balance_wallet_rounded, size: 18),
              label: const Text('Crear préstamo'),
            ),
          ],
        ],
      ),
    );
  }

  // ── Form ──────────────────────────────────────────────────────────────────

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            if (_ctrl.submitError != null) _ErrorBanner(message: _ctrl.submitError!),

            // ── Datos personales ──────────────────────────────────────────
            _FormCard(
              icon: Icons.person_rounded,
              iconColor: AppPalette.deepBlue,
              title: 'Datos personales',
              child: Column(
                children: [
                  _field(_nameCtrl, 'Nombre completo *',
                      errorKey: 'name',
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Requerido' : null),
                  const SizedBox(height: 10),
                  _field(_idNumberCtrl, 'Nº documento / CI / RUC', errorKey: 'id_number'),
                  const SizedBox(height: 10),
                  _field(_phoneCtrl, 'Teléfono',
                      errorKey: 'phone', keyboardType: TextInputType.phone),
                  const SizedBox(height: 10),
                  _field(_emailCtrl, 'Email',
                      errorKey: 'email', keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 10),
                  _field(_addressCtrl, 'Dirección', errorKey: 'address'),
                  const SizedBox(height: 10),
                  _field(_notesCtrl, 'Observaciones', errorKey: 'notes', maxLines: 3),
                  if (_tagOptions.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _tag ?? '',
                      decoration: InputDecoration(labelText: 'Etiqueta', errorText: _fieldErr('tag')),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Sin etiqueta')),
                        for (final t in _tagOptions)
                          DropdownMenuItem(
                            value: t['name']?.toString() ?? '',
                            child: Row(
                              children: [
                                CircleAvatar(radius: 6, backgroundColor: hexColor(t['color']?.toString())),
                                const SizedBox(width: 8),
                                Text(t['name']?.toString() ?? ''),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _tag = (v == null || v.isEmpty) ? null : v),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Ubicación ─────────────────────────────────────────────────
            _FormCard(
              icon: Icons.location_on_rounded,
              iconColor: const Color(0xFF10B981),
              title: 'Ubicación (opcional)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_selectedLatLng == null)
                    OutlinedButton.icon(
                      onPressed: _openMapPicker,
                      icon: const Icon(Icons.map_rounded, size: 18),
                      label: const Text('Seleccionar en mapa'),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 44)),
                    )
                  else
                    _LocationChip(
                      lat: _selectedLatLng!.latitude,
                      lng: _selectedLatLng!.longitude,
                      onTapChange: _openMapPicker,
                      onClear: _clearLocation,
                    ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _locationUrlCtrl,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'O pega un link de Google Maps',
                      errorText: _fieldErr('location_url'),
                      prefixIcon: const Icon(Icons.link_rounded, size: 18),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Foto ──────────────────────────────────────────────────────
            _FormCard(
              icon: Icons.photo_camera_rounded,
              iconColor: const Color(0xFF8B5CF6),
              title: 'Foto (opcional)',
              child: _photoPath != null
                  ? Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(File(_photoPath!),
                              width: 72, height: 72, fit: BoxFit.cover),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => setState(() => _photoPath = null),
                            icon: const Icon(Icons.delete_rounded, size: 16),
                            label: const Text('Quitar foto'),
                          ),
                        ),
                      ],
                    )
                  : (_existingPhotoUrl != null && _existingPhotoUrl!.isNotEmpty && !_removePhoto)
                  ? Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(_existingPhotoUrl!,
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox(width: 72, height: 72, child: Icon(Icons.broken_image_rounded))),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _pickPhoto,
                                icon: const Icon(Icons.photo_camera_rounded, size: 16),
                                label: const Text('Cambiar'),
                              ),
                              TextButton.icon(
                                onPressed: () => setState(() => _removePhoto = true),
                                icon: const Icon(Icons.delete_rounded, size: 16),
                                label: const Text('Quitar foto'),
                                style: TextButton.styleFrom(foregroundColor: AppPalette.rose),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : OutlinedButton.icon(
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.add_photo_alternate_rounded),
                      label: const Text('Agregar foto'),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 44)),
                    ),
            ),

            const SizedBox(height: 12),

            // ── Documentos ────────────────────────────────────────────────
            _FormCard(
              icon: Icons.folder_rounded,
              iconColor: const Color(0xFFF59E0B),
              title: 'Documentos (opcional)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final doc in _existingDocs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(
                            (doc['mime_type']?.toString() ?? '').contains('pdf')
                                ? Icons.picture_as_pdf_rounded
                                : Icons.image_rounded,
                            color: const Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              (doc['label'] ?? doc['original_name'] ?? 'Documento').toString(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_deletingDocId == int.tryParse('${doc['id']}'))
                            const SizedBox(
                                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          else
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 18),
                              color: AppPalette.rose,
                              tooltip: 'Eliminar documento',
                              onPressed: _deletingDocId == null ? () => _deleteExistingDoc(doc) : null,
                            ),
                        ],
                      ),
                    ),
                  ..._docEntries.asMap().entries.map((entry) {
                    final i = entry.key;
                    final doc = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(File(doc.path),
                                width: 46, height: 46, fit: BoxFit.cover),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: doc.labelCtrl,
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: upperCaseFormatters,
                              decoration: const InputDecoration(
                                hintText: 'Etiqueta (ej. DNI Frontal)',
                                hintStyle: TextStyle(fontSize: 12),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () => _removeDoc(i),
                            color: const Color(0xFF94A3B8),
                            padding: EdgeInsets.zero,
                            constraints:
                                const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (_docEntries.length < 10)
                    OutlinedButton.icon(
                      onPressed: _pickDocument,
                      icon: const Icon(Icons.attach_file_rounded, size: 18),
                      label: Text(
                          _docEntries.isEmpty ? 'Agregar documento' : 'Agregar otro'),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 44)),
                    )
                  else
                    const Text('Máximo 10 documentos',
                        style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                        textAlign: TextAlign.center),
                ],
              ),
            ),

            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _ctrl.submitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.deepBlue,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: _ctrl.submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(_isEdit ? Icons.save_rounded : Icons.person_add_rounded),
              label: Text(_isEdit
                  ? (_ctrl.submitting ? 'Guardando...' : 'Guardar cambios')
                  : (_ctrl.submitting ? 'Registrando...' : 'Registrar cliente')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    String? errorKey,
    String? Function(String?)? validator,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    final err = errorKey != null ? _fieldErr(errorKey) : null;
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textCapitalization: upperCaseFor(keyboardType) ? TextCapitalization.characters : TextCapitalization.none,
      inputFormatters: upperCaseFor(keyboardType) ? upperCaseFormatters : null,
      decoration: InputDecoration(labelText: label, errorText: err),
      validator: validator,
    );
  }
}

// ── Location chip ─────────────────────────────────────────────────────────────

class _LocationChip extends StatelessWidget {
  const _LocationChip({
    required this.lat,
    required this.lng,
    required this.onTapChange,
    required this.onClear,
  });

  final double lat;
  final double lng;
  final VoidCallback onTapChange;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_rounded, color: Color(0xFF16A34A), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ubicación seleccionada',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF15803D))),
                Text(
                  '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF166534)),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onTapChange,
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero),
            child: const Text('Cambiar', style: TextStyle(fontSize: 12)),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 16),
            onPressed: onClear,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}

// ── Map picker screen ─────────────────────────────────────────────────────────

class _MapPickerScreen extends StatefulWidget {
  const _MapPickerScreen({this.initialLocation});
  final LatLng? initialLocation;

  @override
  State<_MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<_MapPickerScreen> {
  final _mapController = MapController();
  LatLng? _selected;
  bool _loadingGps = false;

  // Default center: Santa Cruz de la Sierra, Bolivia
  static const _defaultCenter = LatLng(-17.7863, -63.1812);

  @override
  void initState() {
    super.initState();
    _selected = widget.initialLocation;
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _goToGps() async {
    setState(() => _loadingGps = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) { return; }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final latLng = LatLng(pos.latitude, pos.longitude);
      setState(() => _selected = latLng);
      _mapController.move(latLng, 16);
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seleccionar ubicación'),
        backgroundColor: AppPalette.deepBlue,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _selected == null
                ? null
                : () => Navigator.of(context).pop(_selected),
            child: Text(
              'Confirmar',
              style: TextStyle(
                color: _selected == null ? Colors.white38 : Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selected ?? _defaultCenter,
              initialZoom: _selected != null ? 15 : 12,
              onTap: (_, latLng) => setState(() => _selected = latLng),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.santaana2.prestamos_movil_app',
              ),
              if (_selected != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selected!,
                      width: 40,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: const Icon(Icons.location_pin,
                          color: Color(0xFFEF4444), size: 40),
                    ),
                  ],
                ),
            ],
          ),

          // Instruction banner
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 6)
                  ],
                ),
                child: Text(
                  _selected == null
                      ? 'Toca el mapa para fijar la ubicación'
                      : 'Toca para mover el pin',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),

          // GPS button
          Positioned(
            right: 16,
            bottom: 24,
            child: FloatingActionButton(
              onPressed: _loadingGps ? null : _goToGps,
              backgroundColor: Colors.white,
              foregroundColor: AppPalette.deepBlue,
              tooltip: 'Ir a mi ubicación',
              child: _loadingGps
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared form widgets ───────────────────────────────────────────────────────

class _FormCard extends StatelessWidget {
  const _FormCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6EEF5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 16, color: iconColor),
                ),
                const SizedBox(width: 10),
                Text(title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.ink)),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFB3B3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFD32F2F), size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: const TextStyle(
                      color: Color(0xFFD32F2F), fontSize: 13))),
        ],
      ),
    );
  }
}
