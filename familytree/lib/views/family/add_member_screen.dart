import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/app_colors.dart';
import '../../core/services/firebase_service.dart';
import '../../core/utils/helpers.dart';
import '../../models/member_model.dart';
import '../../providers/family_provider.dart';
import '../widgets/custom_text_field.dart';

const _absent = Object();

class AddMemberScreen extends StatefulWidget {
  final String       familyId;
  final String?      familyName;
  final MemberModel? existingMember;
  /// When true a Role dropdown is shown (Master only).
  final bool         canEditRole;

  const AddMemberScreen({
    super.key,
    required this.familyId,
    this.familyName,
    this.existingMember,
    this.canEditRole = false,
  });

  @override
  State<AddMemberScreen> createState() => _AddMemberScreenState();
}

class _AddMemberScreenState extends State<AddMemberScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _saving   = false;

  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _middleNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _mobileCtrl;
  late final TextEditingController _educationCtrl;
  late final TextEditingController _nativePlaceCtrl;
  late final TextEditingController _addressCtrl;

  Gender      _gender      = Gender.male;
  Designation _designation = Designation.other;
  String      _role        = 'member';
  late _RelField _fatherId;
  late _RelField _motherId;
  late _RelField _spouseId;
  File?   _pickedImage;
  String? _existingImageUrl;

  bool get _isEditing => widget.existingMember != null;

  @override
  void initState() {
    super.initState();
    final m = widget.existingMember;
    _firstNameCtrl   = TextEditingController(text: m?.firstName   ?? '');
    _middleNameCtrl  = TextEditingController(text: m?.middleName  ?? '');
    _lastNameCtrl    = TextEditingController(text: m?.lastName    ?? '');
    _mobileCtrl      = TextEditingController(text: m?.mobileNumber ?? '');
    _educationCtrl   = TextEditingController(text: m?.education   ?? '');
    _nativePlaceCtrl = TextEditingController(text: m?.nativePlace ?? '');
    _addressCtrl     = TextEditingController(text: m?.currentAddress ?? '');
    if (m != null) {
      _gender           = m.gender;
      _designation      = m.designation;
      _role             = m.role;
      _fatherId         = _RelField(m.fatherId);
      _motherId         = _RelField(m.motherId);
      _spouseId         = _RelField(m.spouseId);
      _existingImageUrl = m.profileImageUrl;
    } else {
      _fatherId = _RelField(null);
      _motherId = _RelField(null);
      _spouseId = _RelField(null);
    }
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose(); _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();  _mobileCtrl.dispose();
    _educationCtrl.dispose(); _nativePlaceCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 800, maxHeight: 800, imageQuality: 85);
    if (file != null) setState(() => _pickedImage = File(file.path));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    try {
      final family = context.read<FamilyProvider>();

      if (_isEditing) {
        String? imageUrl = _existingImageUrl;
        if (_pickedImage != null) {
          try {
            imageUrl = await FirebaseService.instance.uploadProfileImage(
                memberId: widget.existingMember!.id, imageFile: _pickedImage!);
          } catch (e) {
            debugPrint('Error uploading profile image in edit flow offline: $e');
          }
        }

        // ── Build a safe patch — only fields the caller may write ──
        // Never include password, id, or familyId in a member-originated update.
        // Role is only included when canEditRole == true (Master only).
        final safePatch = <String, dynamic>{
          'firstName':      _firstNameCtrl.text.trim(),
          'middleName':     _middleNameCtrl.text.trim(),
          'lastName':       _lastNameCtrl.text.trim(),
          'gender':         _gender.name,
          'education':      _educationCtrl.text.trim(),
          'nativePlace':    _nativePlaceCtrl.text.trim(),
          'currentAddress': _addressCtrl.text.trim(),
          'designation':    _designation.name,
          'profileImageUrl': imageUrl,
          'fatherId':       _fatherId.value,
          'motherId':       _motherId.value,
          'spouseId':       _spouseId.value,
          // mobile is read-only in edit mode — never patched
          if (widget.canEditRole) 'role': _role,
        };

        await family.updateMemberMap(
            id: widget.existingMember!.id, data: safePatch);
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Member updated'), backgroundColor: AppColors.success));
      } else {
        final newMember = MemberModel(
          id: '', familyId: widget.familyId,
          firstName: _firstNameCtrl.text.trim(),
          middleName: _middleNameCtrl.text.trim(),
          lastName: _lastNameCtrl.text.trim(),
          mobileNumber: _mobileCtrl.text.trim(),
          password: '', gender: _gender,
          education: _educationCtrl.text.trim(),
          nativePlace: _nativePlaceCtrl.text.trim(),
          currentAddress: _addressCtrl.text.trim(),
          designation: _designation,
          fatherId: _fatherId.value, motherId: _motherId.value,
          spouseId: _spouseId.value, role: 'member',
        );
        final generatedPassword = await family.addMember(
            member: newMember, profileImage: _pickedImage);
        if (!mounted) return;
        setState(() => _saving = false);
        if (generatedPassword != null) {
          _showPasswordDialog(
              name: '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}',
              mobile: _mobileCtrl.text.trim(), password: generatedPassword);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(family.errorMessage ?? 'Failed to add member'),
              backgroundColor: AppColors.error));
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showPasswordDialog({required String name, required String mobile, required String password}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.check_circle, color: AppColors.success),
          SizedBox(width: 8),
          Text('Member Added!'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$name added successfully.',
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            const Text('Share these login credentials:',
                style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            _credRow(context, Icons.phone, 'Mobile', mobile),
            const SizedBox(height: 8),
            _credRow(context, Icons.lock, 'Password', password),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200)),
              child: const Row(children: [
                Icon(Icons.warning_amber, size: 16, color: Colors.orange),
                SizedBox(width: 6),
                Expanded(child: Text('Save this password — it cannot be retrieved later.',
                    style: TextStyle(fontSize: 12, color: Colors.orange))),
              ]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: password));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password copied to clipboard')));
            },
            child: const Text('Copy Password'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () { Navigator.of(context).pop(); Navigator.of(context).pop(); },
            child: const Text('Done', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _credRow(BuildContext ctx, IconData icon, String label, String value) =>
      InkWell(
        onTap: () {
          Clipboard.setData(ClipboardData(text: value));
          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$label copied')));
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              color: AppColors.background, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.divider)),
          child: Row(children: [
            Icon(icon, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text('$label: ', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const Spacer(),
            const Icon(Icons.copy, size: 14, color: AppColors.textSecondary),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final members = context.watch<FamilyProvider>().members;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Member' : 'Add Member'),
        actions: [
          if (_saving)
            const Padding(padding: EdgeInsets.all(16),
                child: SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
          else
            TextButton(onPressed: _save,
                child: const Text('Save', style: TextStyle(color: Colors.white, fontSize: 16))),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.familyName != null && widget.familyName!.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.family_restroom, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text('Adding to: ', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  Text(widget.familyName!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                ]),
              ),

            Center(
              child: GestureDetector(
                onTap: _pickImage,
                child: Stack(children: [
                  CircleAvatar(
                    radius: 52,
                    backgroundColor: AppColors.divider,
                    backgroundImage: _pickedImage != null
                        ? FileImage(_pickedImage!) as ImageProvider
                        : (_existingImageUrl != null ? CachedNetworkImageProvider(_existingImageUrl!) : null),
                    child: (_pickedImage == null && _existingImageUrl == null)
                        ? const Icon(Icons.person, size: 52, color: AppColors.textSecondary)
                        : null,
                  ),
                  Positioned(bottom: 0, right: 0,
                      child: Container(
                        width: 30, height: 30,
                        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                        child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                      )),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            const Center(child: Text('Tap to add photo (optional)', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
            const SizedBox(height: 24),

            _sectionHeader('Personal Information'),
            const SizedBox(height: 12),
            CustomTextField(controller: _firstNameCtrl, label: 'First Name *',
                prefixIcon: const Icon(Icons.person_outline),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
            const SizedBox(height: 12),
            CustomTextField(controller: _middleNameCtrl, label: 'Middle Name',
                prefixIcon: const Icon(Icons.person_outline)),
            const SizedBox(height: 12),
            CustomTextField(controller: _lastNameCtrl, label: 'Last Name *',
                prefixIcon: const Icon(Icons.person_outline),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
            const SizedBox(height: 12),
            _buildDropdown(label: 'Gender *', icon: Icons.wc_outlined,
                value: _gender.name,
                items: Gender.values.map((g) => DropdownMenuItem(
                    value: g.name, child: Text(Helpers.capitalise(g.name)))).toList(),
                onChanged: (v) => setState(() => _gender = Gender.values.firstWhere((g) => g.name == v))),
            const SizedBox(height: 12),
            CustomTextField(controller: _educationCtrl, label: 'Education', prefixIcon: const Icon(Icons.school_outlined)),
            const SizedBox(height: 24),

            _sectionHeader('Contact & Location'),
            const SizedBox(height: 12),
            CustomTextField(
                controller: _mobileCtrl, label: 'Mobile Number *',
                hint: '10-digit number', keyboardType: TextInputType.phone,
                prefixIcon: const Icon(Icons.phone_outlined),
                readOnly: _isEditing,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (v.trim().length != 10) return 'Enter 10-digit number';
                  return null;
                }),
            const SizedBox(height: 12),

            CustomTextField(
              controller: _nativePlaceCtrl,
              label: 'Native Place',
              prefixIcon: const Icon(Icons.location_city_outlined),
              readOnly: true,
              onTap: _showNativePlaceSearchBottomSheet,
            ),

            const SizedBox(height: 12),
            CustomTextField(controller: _addressCtrl, label: 'Current Address',
                prefixIcon: const Icon(Icons.home_outlined), maxLines: 2),
            const SizedBox(height: 24),

            _sectionHeader('Profession'),
            const SizedBox(height: 12),
            _buildDropdown(label: 'Designation *', icon: Icons.work_outline,
                value: _designation.name,
                items: Designation.values.map((d) => DropdownMenuItem(
                    value: d.name, child: Text(Helpers.capitalise(d.name)))).toList(),
                onChanged: (v) => setState(() => _designation = Designation.values.firstWhere((d) => d.name == v))),
            const SizedBox(height: 24),

            // ── Role — visible only to Master when editing ──────
            if (widget.canEditRole && _isEditing) ...[
              _sectionHeader('Role & Permissions'),
              const SizedBox(height: 12),
              _buildDropdown(
                label: 'Role *',
                icon: Icons.admin_panel_settings_outlined,
                value: ['member', 'admin'].contains(_role) ? _role : 'member',
                items: const [
                  DropdownMenuItem(value: 'member', child: Text('Member')),
                  DropdownMenuItem(value: 'admin',  child: Text('Family Admin')),
                ],
                onChanged: (v) => setState(() => _role = v ?? 'member'),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.orange),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Family Admin can add, edit and delete members in their family.',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 24),
            ],

            _sectionHeader('Family Relationships'),
            const SizedBox(height: 4),
            const Text('Optional — links this member in the tree', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            _buildMemberDropdown(label: 'Father', icon: Icons.man_outlined,
                selectedId: _fatherId.value,
                members: members.where((m) => m.gender == Gender.male && m.id != widget.existingMember?.id).toList(),
                onChanged: (v) => setState(() => _fatherId = _RelField(v))),
            const SizedBox(height: 12),
            _buildMemberDropdown(label: 'Mother', icon: Icons.woman_outlined,
                selectedId: _motherId.value,
                members: members.where((m) => m.gender == Gender.female && m.id != widget.existingMember?.id).toList(),
                onChanged: (v) => setState(() => _motherId = _RelField(v))),
            const SizedBox(height: 12),
            _buildMemberDropdown(label: 'Spouse', icon: Icons.favorite_outline,
                selectedId: _spouseId.value,
                members: members.where((m) => m.id != widget.existingMember?.id).toList(),
                onChanged: (v) => setState(() => _spouseId = _RelField(v))),
            const SizedBox(height: 32),

            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: _saving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_isEditing ? 'Update Member' : 'Add Member', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary, letterSpacing: 0.5)),
      const SizedBox(height: 4),
      const Divider(height: 1),
    ],
  );

  Widget _buildDropdown({
    required String label, required IconData icon, required String value,
    required List<DropdownMenuItem<String>> items,
    required void Function(String?) onChanged,
  }) => DropdownButtonFormField<String>(
    value: value, items: items, onChanged: onChanged,
    decoration: InputDecoration(
        labelText: label, prefixIcon: Icon(icon),
        filled: true, fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.divider)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary, width: 1.8))),
  );

  Widget _buildMemberDropdown({
    required String label, required IconData icon,
    required String? selectedId, required List<MemberModel> members,
    required void Function(String?) onChanged,
  }) {
    final bool hasSelected = selectedId == null || members.any((m) => m.id == selectedId);
    final String? safeValue = hasSelected ? selectedId : null;

    return DropdownButtonFormField<String>(
      value: safeValue,
      hint: Text('Select $label (optional)'),
      items: [
        const DropdownMenuItem(value: null, child: Text('None')),
        ...members.map((m) => DropdownMenuItem(value: m.id, child: Text(m.fullName))),
      ],
      onChanged: onChanged,
      decoration: InputDecoration(
          labelText: label, prefixIcon: Icon(icon),
          filled: true, fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.divider)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.divider)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary, width: 1.8))),
    );
  }

  void _showNativePlaceSearchBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return _NativePlaceSearchBottomSheet(
          apiKey: "AIzaSyABNOR5Y5RBkep9P-1xh0U245dHMMdKl1g",
          onSelect: (val) {
            setState(() {
              _nativePlaceCtrl.text = val;
            });
          },
        );
      },
    );
  }
}

class _RelField {
  final String? value;
  const _RelField(this.value);
}

class _NativePlaceSearchBottomSheet extends StatefulWidget {
  final String apiKey;
  final ValueChanged<String> onSelect;

  const _NativePlaceSearchBottomSheet({
    required this.apiKey,
    required this.onSelect,
  });

  @override
  State<_NativePlaceSearchBottomSheet> createState() =>
      __NativePlaceSearchBottomSheetState();
}

class __NativePlaceSearchBottomSheetState
    extends State<_NativePlaceSearchBottomSheet> {
  final _searchCtrl = TextEditingController();
  List<String> _predictions = [];
  bool _searching = false;

  Future<void> _search(String input) async {
    if (input.trim().isEmpty) {
      setState(() => _predictions = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/autocomplete/json'
          '?input=${Uri.encodeComponent(input)}'
          '&key=${widget.apiKey}'
          '&components=country:in');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final preds = data['predictions'] as List<dynamic>?;
        if (preds != null) {
          setState(() {
            _predictions = preds
                .map((p) => p['description'] as String? ?? '')
                .where((s) => s.isNotEmpty)
                .toList();
          });
        }
      }
    } catch (_) {}
    setState(() => _searching = false);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: 20,
        left: 16,
        right: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Search Native Place',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Type village, city name...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.grey.shade100,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (val) => _search(val),
          ),
          const SizedBox(height: 16),
          if (_searching)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_predictions.isEmpty && _searchCtrl.text.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('No places found',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _predictions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final prediction = _predictions[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.location_on_outlined,
                        color: AppColors.textSecondary),
                    title: Text(
                      prediction,
                      style: const TextStyle(fontSize: 14),
                    ),
                    onTap: () {
                      widget.onSelect(prediction);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}