import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../controllers/create_loan_controller.dart';
import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/upper_case.dart';
import '../../utils/currency.dart';

class NewLoanSheet extends StatefulWidget {
  const NewLoanSheet({
    super.key,
    required this.api,
    required this.logger,
    required this.permissions,
    this.cashBranch,
    this.preselectedClient,
  });

  final ApiService api;
  final ErrorLogService logger;
  final List<String> permissions;
  final Map<String, dynamic>? cashBranch;
  final Map<String, dynamic>? preselectedClient;

  @override
  State<NewLoanSheet> createState() => _NewLoanSheetState();
}

class _NewLoanSheetState extends State<NewLoanSheet> {
  late final CreateLoanController _ctrl;
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();

  // Client search
  final _clientSearchCtrl = TextEditingController();
  Map<String, dynamic>? _selectedClient;
  Timer? _debounce;

  // Category
  int? _selectedCategory;
  Map<String, dynamic>? _selectedCategoryMap;
  Map<String, dynamic>? _selectedRule;

  // Product fields — Vehículo
  final _productNameCtrl = TextEditingController();
  final _productBrandCtrl = TextEditingController();
  int? _productModelYear;
  final _productPlateCtrl = TextEditingController();
  final _productChassisCtrl = TextEditingController();

  // Product fields — Joyas
  final _productItemTypeCtrl = TextEditingController();
  String? _productKarat;
  String? _productMaterialType;

  // Product fields — Artículos
  final _productSerialCtrl = TextEditingController();
  final _productItemModelCtrl = TextEditingController();

  // Shared product fields
  final _productDetailsCtrl = TextEditingController();

  // Loan fields
  final _amountCtrl = TextEditingController();
  final _interestRateCtrl = TextEditingController();
  final _startDateCtrl = TextEditingController();
  DateTime? _startDate;
  final _productPriceCtrl = TextEditingController();

  // Images
  final List<String> _imagePaths = [];

  // Saldo disponible en la caja abierta (null = aún no se sabe); el préstamo no puede superarlo.
  double? _cashAvailable;

  final _money = Currency.formatter();

  /// Formulario de producto según la categoría (como la web): 1 Vehículo, 2 Joyas,
  /// 3 Garrafas y cualquier otra categoría usa el de Artículos.
  int? get _productLayout {
    final id = _selectedCategory;
    if (id == null) return null;
    return const {1, 2, 3}.contains(id) ? id : 4;
  }

  static Color _hexColor(String? hex) {
    if (hex == null) return AppPalette.deepBlue;
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return AppPalette.deepBlue;
    }
  }

  bool get _canSetStartDate => widget.permissions.contains('loans.set_start_date');
  bool get _interestRateEditable {
    if (_selectedCategory == null) return false;
    // interest_rate_editable viene en el objeto categoría, no en la regla
    if (_selectedCategoryMap != null) return _selectedCategoryMap!['interest_rate_editable'] == true;
    // Fallback si las categorías aún no cargaron
    return _selectedCategory == 1 || _selectedCategory == 2;
  }

  static const _karats = ['10K', '14K', '18K', '21K', '22K', '24K'];
  static const _materials = ['Oro', 'Plata', 'Platino', 'Acero', 'Otro'];

  @override
  void initState() {
    super.initState();
    _ctrl = CreateLoanController(api: widget.api, logger: widget.logger);
    _ctrl.loadCategories();
    if (widget.preselectedClient != null) {
      _selectedClient = widget.preselectedClient;
    }
    _startDate = DateTime.now();
    _startDateCtrl.text = DateFormat('yyyy-MM-dd').format(_startDate!);
    _amountCtrl.addListener(_refresh);
    _interestRateCtrl.addListener(_refresh);
    _loadCashAvailable();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCashAvailable() async {
    try {
      final data = await widget.api.cashSession();
      final summary = (data['session'] as Map?)?['summary'];
      if (!mounted || summary is! Map) return;
      setState(() => _cashAvailable = (summary['expected'] as num?)?.toDouble());
    } catch (e, st) {
      // Sin el dato el servidor igual valida el saldo; solo no se muestra el aviso.
      await widget.logger.logError(module: 'create_loan', error: e, stackTrace: st, endpoint: '/cash-session');
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    _clientSearchCtrl.dispose();
    _productNameCtrl.dispose();
    _productBrandCtrl.dispose();
    _productPlateCtrl.dispose();
    _productChassisCtrl.dispose();
    _productItemTypeCtrl.dispose();
    _productSerialCtrl.dispose();
    _productItemModelCtrl.dispose();
    _productDetailsCtrl.dispose();
    _amountCtrl.dispose();
    _interestRateCtrl.dispose();
    _startDateCtrl.dispose();
    _productPriceCtrl.dispose();
    super.dispose();
  }

  void _onClientSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _ctrl.searchClients(value);
    });
  }

  void _selectClient(Map<String, dynamic> client) {
    setState(() {
      _selectedClient = client;
      _clientSearchCtrl.clear();
    });
    _ctrl.clearClientResults();
  }

  void _clearClient() {
    setState(() => _selectedClient = null);
  }

  void _onCategoryChanged(int? value) {
    final catMap = value != null ? _ctrl.categoryById(value) : null;
    final rule = value != null ? _ctrl.ruleForCategory(value) : null;
    setState(() {
      _selectedCategory = value;
      _selectedCategoryMap = catMap;
      _selectedRule = rule;
      _productModelYear = null;
      _productKarat = null;
      _productMaterialType = null;
      _productNameCtrl.clear();
      _productBrandCtrl.clear();
      _productPlateCtrl.clear();
      _productChassisCtrl.clear();
      _productItemTypeCtrl.clear();
      _productSerialCtrl.clear();
      _productItemModelCtrl.clear();
      _productDetailsCtrl.clear();
      final rateVal = rule?['interest_rate'];
      _interestRateCtrl.text = rateVal != null ? rateVal.toString() : '';
    });
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        _startDateCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _addImage() async {
    if (_imagePaths.length >= 10) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Cámara'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await _imagePicker.pickImage(source: source, imageQuality: 80, maxWidth: 1200);
    if (picked != null) {
      setState(() => _imagePaths.add(picked.path));
    }
  }

  Future<void> _submit() async {
    if (_selectedClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un cliente para continuar')),
      );
      return;
    }
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una categoría')),
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final clientId = (_selectedClient!['id'] as num).toInt();
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '.')) ?? 0;

    final interestRate = _interestRateEditable ? int.tryParse(_interestRateCtrl.text) : null;
    final productPrice = _productPriceCtrl.text.trim().isNotEmpty
        ? double.tryParse(_productPriceCtrl.text.replaceAll(',', '.'))
        : null;

    final ok = await _ctrl.submitLoan(
      clientId: clientId,
      creditCategoryId: _selectedCategory!,
      amount: amount,
      interestRate: interestRate,
      startDate: _canSetStartDate ? _startDateCtrl.text.trim() : null,
      productPrice: productPrice,
      productDetails: _productDetailsCtrl.text.trim().isNotEmpty ? _productDetailsCtrl.text.trim() : null,
      productName: _productNameCtrl.text.trim().isNotEmpty ? _productNameCtrl.text.trim() : null,
      productBrand: _productBrandCtrl.text.trim().isNotEmpty ? _productBrandCtrl.text.trim() : null,
      productModelYear: _productModelYear,
      productPlate: _productPlateCtrl.text.trim().isNotEmpty ? _productPlateCtrl.text.trim() : null,
      productChassis: _productChassisCtrl.text.trim().isNotEmpty ? _productChassisCtrl.text.trim() : null,
      productItemType: _productItemTypeCtrl.text.trim().isNotEmpty ? _productItemTypeCtrl.text.trim() : null,
      productKarat: _productKarat,
      productMaterialType: _productMaterialType,
      productSerialNumber: _productSerialCtrl.text.trim().isNotEmpty ? _productSerialCtrl.text.trim() : null,
      productItemModel: _productItemModelCtrl.text.trim().isNotEmpty ? _productItemModelCtrl.text.trim() : null,
      imagePaths: List.unmodifiable(_imagePaths),
    );

    if (ok && mounted) {
      Navigator.of(context).pop(_ctrl.submitCode);
    }
  }

  String? _fieldError(String key) => _ctrl.validationErrors[key];

  Widget _clientAvatar(Map<String, dynamic> map, {double radius = 18}) {
    final url = map['photo_url']?.toString();
    final initial = (map['name']?.toString().isNotEmpty ?? false)
        ? map['name'].toString().substring(0, 1).toUpperCase()
        : 'C';
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppPalette.deepBlue.withValues(alpha: 0.15),
        backgroundImage: NetworkImage(url),
        onBackgroundImageError: (_, _) {},
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppPalette.deepBlue,
      child: Text(initial, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: radius * 0.8)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF4F8FC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // drag handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCDD8E3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Nuevo Préstamo',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppPalette.ink)),
                          if (widget.cashBranch != null) ...[
                            const SizedBox(height: 5),
                            _BranchBadge(branch: widget.cashBranch!, hexColor: _hexColor),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              if (_ctrl.cashError != null)
                _ErrorBanner(message: _ctrl.cashError!)
              else if (_ctrl.submitError != null)
                _ErrorBanner(message: _ctrl.submitError!),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildClientSection(),
                        const SizedBox(height: 12),
                        _buildCategorySection(),
                        if (_selectedCategory != null) ...[
                          const SizedBox(height: 12),
                          _buildProductSection(),
                        ],
                        const SizedBox(height: 12),
                        _buildLoanSection(),
                        const SizedBox(height: 12),
                        _buildImagesSection(),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _ctrl.submitting ? null : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppPalette.deepBlue,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: _ctrl.submitting
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check_rounded),
                          label: Text(_ctrl.submitting ? 'Registrando...' : 'Registrar préstamo'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Sección A: Cliente ────────────────────────────────────────────────────

  Widget _buildClientSection() {
    return _FormCard(
      icon: Icons.person_rounded,
      iconColor: AppPalette.deepBlue,
      title: 'Cliente',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selectedClient != null)
            _SelectedChip(
              label: _selectedClient!['name']?.toString() ?? '',
              avatar: _clientAvatar(_selectedClient!, radius: 16),
              onRemove: _clearClient,
            )
          else ...[
            TextField(
              controller: _clientSearchCtrl,
              onChanged: _onClientSearchChanged,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o documento...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _ctrl.clientSearchLoading
                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                    : null,
              ),
            ),
            if (_ctrl.clientResults.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE0ECF5)),
                ),
                child: Column(
                  children: _ctrl.clientResults.take(6).map((c) {
                    final map = (c as Map).cast<String, dynamic>();
                    return InkWell(
                      onTap: () => _selectClient(map),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            _clientAvatar(map, radius: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(map['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                  if (map['id_number'] != null)
                                    Text(map['id_number'].toString(), style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299))),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: Color(0xFF6A8299)),
                          ],
                        ),
                      ),
                    );
                  }).toList(growable: false),
                ),
              ),
            ],
          ],
          if (_fieldError('client_id') != null)
            _FieldError(_fieldError('client_id')!),
        ],
      ),
    );
  }

  // ── Sección B: Categoría ─────────────────────────────────────────────────

  Widget _buildCategorySection() {
    return _FormCard(
      icon: Icons.category_rounded,
      iconColor: const Color(0xFF8E6BBF),
      title: 'Categoría',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Categorías activas de la empresa (las mismas que en la web).
          if (_ctrl.categoriesLoading)
            const LinearProgressIndicator(minHeight: 3)
          else if (_ctrl.categories.isEmpty)
            Row(
              children: [
                Expanded(
                  child: Text(
                    _ctrl.categoriesError ?? 'La empresa no tiene categorías de crédito activas.',
                    style: const TextStyle(color: AppPalette.rose, fontSize: 13),
                  ),
                ),
                TextButton(onPressed: _ctrl.loadCategories, child: const Text('Reintentar')),
              ],
            )
          else
            DropdownButtonFormField<int>(
              initialValue: _selectedCategory,
              isExpanded: true,
              decoration: const InputDecoration(hintText: 'Selecciona una categoría'),
              items: [
                for (final cat in _ctrl.categories.whereType<Map>())
                  if ((cat['id'] as num?) != null)
                    DropdownMenuItem(
                      value: (cat['id'] as num).toInt(),
                      child: Text(cat['name']?.toString() ?? 'Categoría ${cat['id']}'),
                    ),
              ],
              onChanged: _onCategoryChanged,
              validator: (v) => v == null ? 'Selecciona una categoría' : null,
            ),
          if (_fieldError('credit_category_id') != null)
            _FieldError(_fieldError('credit_category_id')!),
        ],
      ),
    );
  }

  // ── Sección C: Producto ───────────────────────────────────────────────────

  Widget _buildProductSection() {
    switch (_productLayout) {
      case 1:
        return _buildProductVehicle();
      case 2:
        return _buildProductJewelry();
      case 3:
        return _buildProductGarrafas();
      case 4:
        return _buildProductArticulo();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildProductVehicle() {
    final currentYear = DateTime.now().year;
    return _FormCard(
      icon: Icons.directions_car_rounded,
      iconColor: const Color(0xFF19C5B6),
      title: 'Datos del vehículo',
      child: Column(
        children: [
          _field(_productNameCtrl, 'Nombre / Modelo *', errorKey: 'product_name',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null),
          const SizedBox(height: 10),
          _field(_productBrandCtrl, 'Marca *', errorKey: 'product_brand',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: _productModelYear,
            decoration: InputDecoration(
              labelText: 'Año del modelo *',
              errorText: _fieldError('product_model_year'),
            ),
            items: List.generate(
              currentYear + 2 - 1990,
              (i) => DropdownMenuItem(value: currentYear + 1 - i, child: Text('${currentYear + 1 - i}')),
            ),
            onChanged: (v) => setState(() => _productModelYear = v),
            validator: (v) => v == null ? 'Requerido' : null,
          ),
          const SizedBox(height: 10),
          _field(_productPlateCtrl, 'Placa *', errorKey: 'product_plate',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null),
          const SizedBox(height: 10),
          _field(_productChassisCtrl, 'Chasis *', errorKey: 'product_chassis',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null),
          const SizedBox(height: 10),
          _field(_productDetailsCtrl, 'Observaciones', maxLines: 2, errorKey: 'product_details'),
        ],
      ),
    );
  }

  Widget _buildProductJewelry() {
    return _FormCard(
      icon: Icons.diamond_rounded,
      iconColor: const Color(0xFFFFB347),
      title: 'Datos de la joya',
      child: Column(
        children: [
          _field(_productItemTypeCtrl, 'Tipo de joya * (ej. Collar, Anillo)', errorKey: 'product_item_type',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _productKarat,
            decoration: InputDecoration(
              labelText: 'Kilates *',
              errorText: _fieldError('product_karat'),
            ),
            items: _karats.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
            onChanged: (v) => setState(() => _productKarat = v),
            validator: (v) => v == null ? 'Requerido' : null,
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _productMaterialType,
            decoration: InputDecoration(
              labelText: 'Material',
              errorText: _fieldError('product_material_type'),
            ),
            items: _materials.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
            onChanged: (v) => setState(() => _productMaterialType = v),
          ),
          const SizedBox(height: 10),
          _field(_productDetailsCtrl, 'Observaciones', maxLines: 2, errorKey: 'product_details'),
        ],
      ),
    );
  }

  Widget _buildProductGarrafas() {
    return _FormCard(
      icon: Icons.water_drop_rounded,
      iconColor: const Color(0xFF4EA8DE),
      title: 'Producto (Garrafas)',
      child: _field(_productDetailsCtrl, 'Observaciones (opcional)', maxLines: 2, errorKey: 'product_details'),
    );
  }

  Widget _buildProductArticulo() {
    return _FormCard(
      icon: Icons.devices_rounded,
      iconColor: const Color(0xFF6A8299),
      title: 'Datos del artículo',
      child: Column(
        children: [
          _field(_productNameCtrl, 'Nombre *', errorKey: 'product_name',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null),
          const SizedBox(height: 10),
          _field(_productBrandCtrl, 'Marca *', errorKey: 'product_brand',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null),
          const SizedBox(height: 10),
          _field(_productSerialCtrl, 'Número de serie *', errorKey: 'product_serial_number',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null),
          const SizedBox(height: 10),
          _field(_productItemModelCtrl, 'Modelo (ej. ThinkPad E15)', errorKey: 'product_item_model'),
          const SizedBox(height: 10),
          _field(_productDetailsCtrl, 'Observaciones', maxLines: 2, errorKey: 'product_details'),
        ],
      ),
    );
  }

  // ── Sección D: Datos del préstamo ─────────────────────────────────────────

  Widget _buildLoanSection() {
    return _FormCard(
      icon: Icons.account_balance_wallet_rounded,
      iconColor: AppPalette.deepBlue,
      title: 'Datos del préstamo',
      child: Column(
        children: [
          TextFormField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(
              labelText: 'Monto *',
              prefixText: Currency.prefix,
              errorText: _fieldError('amount'),
              helperText: _cashAvailable == null ? null : 'Máximo disponible en caja: ${_money.format(_cashAvailable)}',
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Requerido';
              final amount = double.tryParse(v.replaceAll(',', '.')) ?? 0;
              if (amount <= 0) return 'Ingresa un monto válido';
              if (_cashAvailable != null && amount > _cashAvailable! + 0.001) {
                return 'Supera el saldo disponible en caja (${_money.format(_cashAvailable)})';
              }
              return null;
            },
          ),
          const SizedBox(height: 10),
          if (_interestRateEditable)
            TextFormField(
              controller: _interestRateCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Tasa de interés (%)',
                suffixText: '%',
                errorText: _fieldError('interest_rate'),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Requerido';
                // Igual que la web: cualquier tasa entera entre 1% y 100%.
                final entered = int.tryParse(v.trim());
                if (entered == null || entered < 1 || entered > 100) return 'Ingresa un valor entre 1 y 100';
                return null;
              },
            )
          else if (_selectedRule != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4F8),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFD0DEE8)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 16, color: Color(0xFF6A8299)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Tasa de interés', style: TextStyle(fontSize: 11, color: Color(0xFF6A8299))),
                        Text(
                          '${_selectedRule!['interest_rate'] ?? '-'} % — definida por la regla de la categoría',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppPalette.ink),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          _buildPreview(),
          if (_canSetStartDate) ...[
            const SizedBox(height: 10),
            TextFormField(
              controller: _startDateCtrl,
              readOnly: true,
              onTap: _pickStartDate,
              decoration: InputDecoration(
                labelText: 'Fecha de inicio',
                hintText: 'Hoy por defecto',
                suffixIcon: const Icon(Icons.calendar_today_rounded),
                errorText: _fieldError('start_date'),
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextFormField(
            controller: _productPriceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(
              labelText: 'Precio referencial del producto',
              prefixText: Currency.prefix,
              errorText: _fieldError('product_price'),
            ),
          ),
        ],
      ),
    );
  }

  /// Vista previa como en la web: interés del primer periodo y capital + primer interés.
  Widget _buildPreview() {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '.')) ?? 0;
    final rate = _interestRateEditable
        ? (double.tryParse(_interestRateCtrl.text) ?? 0)
        : ((_selectedRule?['interest_rate'] as num?)?.toDouble() ?? 0);
    if (amount <= 0 || rate <= 0 || _selectedRule == null) return const SizedBox.shrink();

    final interest = amount * rate / 100;
    final period = switch (_selectedRule!['interest_period']?.toString()) {
      'quarterly' => 'trimestral',
      'semiannual' => 'semestral',
      'annual' => 'anual',
      _ => 'mensual',
    };
    final months = (_selectedRule!['term_months'] as num?)?.toInt();

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.deepBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.deepBlue.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Interés del primer periodo', style: TextStyle(fontSize: 11, color: Color(0xFF6A8299))),
                Text(_money.format(interest),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppPalette.deepBlue)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Capital + primer interés', style: TextStyle(fontSize: 11, color: Color(0xFF6A8299))),
                Text(_money.format(amount + interest),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppPalette.ink)),
                Text(
                  'Interés $period${months != null ? ' · plazo $months ${months == 1 ? 'mes' : 'meses'}' : ''}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF6A8299)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Sección E: Imágenes ───────────────────────────────────────────────────

  Widget _buildImagesSection() {
    return _FormCard(
      icon: Icons.photo_camera_rounded,
      iconColor: const Color(0xFF4CAF50),
      title: 'Fotos del producto (opcional)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_imagePaths.isNotEmpty) ...[
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _imagePaths.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(File(_imagePaths[i]), width: 80, height: 80, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () => setState(() => _imagePaths.removeAt(i)),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (_imagePaths.length < 10)
            OutlinedButton.icon(
              onPressed: _addImage,
              icon: const Icon(Icons.add_photo_alternate_rounded),
              label: Text(_imagePaths.isEmpty ? 'Agregar foto' : 'Agregar otra foto'),
            ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _field(
    TextEditingController ctrl,
    String label, {
    String? errorKey,
    String? Function(String?)? validator,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    final err = errorKey != null ? _fieldError(errorKey) : null;
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

// ── Subwidgets ────────────────────────────────────────────────────────────────

class _FormCard extends StatelessWidget {
  const _FormCard({required this.icon, required this.iconColor, required this.title, required this.child});

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
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 18),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppPalette.ink)),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.all(14), child: child),
        ],
      ),
    );
  }
}

class _SelectedChip extends StatelessWidget {
  const _SelectedChip({required this.label, required this.onRemove, this.avatar});

  final String label;
  final VoidCallback onRemove;
  final Widget? avatar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppPalette.deepBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.deepBlue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          if (avatar != null) ...[
            avatar!,
            const SizedBox(width: 8),
          ] else ...[
            const Icon(Icons.person_rounded, size: 16, color: AppPalette.deepBlue),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: AppPalette.deepBlue))),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded, size: 18, color: AppPalette.deepBlue),
          ),
        ],
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
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFB3B3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFD32F2F), size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(color: Color(0xFFD32F2F), fontSize: 13))),
        ],
      ),
    );
  }
}

class _BranchBadge extends StatelessWidget {
  const _BranchBadge({required this.branch, required this.hexColor});

  final Map<String, dynamic> branch;
  final Color Function(String?) hexColor;

  @override
  Widget build(BuildContext context) {
    final name  = branch['name']?.toString() ?? '';
    final color = hexColor(branch['color']?.toString());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(
            name,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 12),
      child: Text(message, style: const TextStyle(color: Color(0xFFD32F2F), fontSize: 12)),
    );
  }
}
