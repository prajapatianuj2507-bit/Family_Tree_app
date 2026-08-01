import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/constants/app_colors.dart';
import '../../models/family_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/family_group_provider.dart';
import '../widgets/custom_text_field.dart';

class CreateFamilyScreen extends StatefulWidget {
  final FamilyModel? existingFamily;
  const CreateFamilyScreen({super.key, this.existingFamily});

  @override
  State<CreateFamilyScreen> createState() => _CreateFamilyScreenState();
}

class _CreateFamilyScreenState extends State<CreateFamilyScreen> {
  final _formKey  = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;

  File?   _pickedPhoto;
  String? _existingPhotoUrl;
  bool    _saving = false;
  String? _error;

  bool get _isEditing => widget.existingFamily != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
        text: widget.existingFamily?.familyName ?? '');
    _descCtrl = TextEditingController(
        text: widget.existingFamily?.description ?? '');
    _existingPhotoUrl = widget.existingFamily?.photoUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final XFile? file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85);
    if (file != null) setState(() => _pickedPhoto = File(file.path));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() { _saving = true; _error = null; });

    final provider = context.read<FamilyGroupProvider>();
    final masterId = context.read<AuthProvider>().currentUser?.id ?? '';

    try {
      print('=== SAVE START ===');
      print('pickedPhoto: $_pickedPhoto');
      print('pickedPhoto exists: ${_pickedPhoto?.existsSync()}');
      print('pickedPhoto path: ${_pickedPhoto?.path}');
      print('isEditing: $_isEditing');

      if (_isEditing) {
        print('--- EDITING ---');
        final ok = await provider.updateFamily(
          widget.existingFamily!.copyWith(
            familyName:  _nameCtrl.text.trim(),
            description: _descCtrl.text.trim(),
          ),
          photoFile: _pickedPhoto,
        );
        print('updateFamily result: $ok');
        print('error: ${provider.errorMessage}');
      } else {
        print('--- CREATING ---');
        final family = await provider.createFamily(
          masterId:    masterId,
          familyName:  _nameCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          photoFile:   _pickedPhoto,
        );
        print('created family: $family');
        print('family photoUrl: ${family?.photoUrl}');
        print('error: ${provider.errorMessage}');
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isEditing ? 'Family updated' : 'Family created'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      print('=== ERROR: $e ===');
      print('stack: ${StackTrace.current}');
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Family' : 'Create Family'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)),
            )
          else
            TextButton(
                onPressed: _save,
                child: const Text('Save',
                    style: TextStyle(
                        color: Colors.white, fontSize: 16))),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Family photo picker
            Center(
              child: GestureDetector(
                onTap: _pickPhoto,
                child: Stack(children: [
                  Container(
                    width: 110, height: 110,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: AppColors.primary.withOpacity(0.08),
                      border: Border.all(
                          color: AppColors.primary.withOpacity(0.3),
                          width: 2),
                      image: _pickedPhoto != null
                          ? DecorationImage(
                          image: FileImage(_pickedPhoto!),
                          fit: BoxFit.cover)
                          : (_existingPhotoUrl != null
                          ? DecorationImage(
                          image:
                          CachedNetworkImageProvider(_existingPhotoUrl!),
                          fit: BoxFit.cover)
                          : null),
                    ),
                    child: (_pickedPhoto == null &&
                        _existingPhotoUrl == null)
                        ? const Icon(Icons.family_restroom,
                        size: 52, color: AppColors.primary)
                        : null,
                  ),
                  Positioned(
                    bottom: 0, right: 0,
                    child: Container(
                      width: 30, height: 30,
                      decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle),
                      child: const Icon(Icons.camera_alt,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            const Center(
                child: Text('Tap to add family photo (optional)',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary))),
            const SizedBox(height: 28),

            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(_error!,
                    style:
                    const TextStyle(color: AppColors.error)),
              ),
              const SizedBox(height: 16),
            ],

            CustomTextField(
              controller: _nameCtrl,
              label: 'Family Name *',
              hint: 'e.g. Prajapati Family',
              prefixIcon: const Icon(Icons.people_alt_outlined),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Family name is required'
                  : null,
            ),
            const SizedBox(height: 16),
            CustomTextField(
              controller: _descCtrl,
              label: 'Description (optional)',
              hint: 'e.g. From Kansa village',
              prefixIcon: const Icon(Icons.info_outline),
              maxLines: 2,
            ),
            const SizedBox(height: 32),

            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white))
                    : Text(
                    _isEditing
                        ? 'Update Family'
                        : 'Create Family',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}