import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:get/get.dart';

import 'package:flutter_seguridad_en_casa/controllers/family_controller.dart';
import 'package:flutter_seguridad_en_casa/data/local/app_db.dart';
import 'package:flutter_seguridad_en_casa/repositories/family_repository.dart';

class AddFamilyMemberPage extends StatefulWidget {
  final FamilyMember? existingMember;

  const AddFamilyMemberPage({super.key, this.existingMember});

  @override
  State<AddFamilyMemberPage> createState() => _AddFamilyMemberPageState();
}

class _AddFamilyMemberPageState extends State<AddFamilyMemberPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _relationCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  bool _saving = false;
  String? _photoPath;
  final ImagePicker _picker = ImagePicker();

  late final FamilyController _controller;

  @override
  void initState() {
    super.initState();
    _controller = Get.find<FamilyController>();

    if (widget.existingMember != null) {
      _nameCtrl.text = widget.existingMember!.name;
      _relationCtrl.text = widget.existingMember!.relation;
      _phoneCtrl.text = widget.existingMember!.phone ?? '';
      _emailCtrl.text = widget.existingMember!.email ?? '';
      _photoPath = widget.existingMember!.profileImagePath;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _relationCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      FamilyMember? member;

      if (widget.existingMember == null) {
        // ✅ Nuevo registro
        member = await _controller.addMember(
          name: _nameCtrl.text.trim(),
          relation: _relationCtrl.text.trim(),
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
          profileImagePath: _photoPath,
          schedules: const [],
        );
      } else {
        // ✅ Edición
        member = widget.existingMember!.copyWith(
          name: _nameCtrl.text.trim(),
          relation: _relationCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          profileImagePath: _photoPath,
        );

        await FamilyRepository.instance.updateFamilyMember(member);
      }

      if (!mounted) return;
      if (member != null) Get.back(result: member);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('known.add.error'.trParams({'error': '$e'}))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 75,
        maxWidth: 1280,
      );
      if (picked == null) return;

      final docs = await getApplicationDocumentsDirectory();
      final folder = Directory(p.join(docs.path, 'known_people_profiles'));

      if (!await folder.exists()) await folder.create(recursive: true);

      final newFile = File(
        p.join(folder.path, 'person_${DateTime.now().millisecondsSinceEpoch}.jpg'),
      );
      await File(picked.path).copy(newFile.path);

      if (_photoPath != null && _photoPath != newFile.path) {
        final previous = File(_photoPath!);
        if (await previous.exists()) await previous.delete();
      }

      if (!mounted) return;
      setState(() => _photoPath = newFile.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('known.add.photoError'.trParams({'error': '$e'}))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final photoFile = _photoPath != null ? File(_photoPath!) : null;
    final isEditing = widget.existingMember != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'known.add.editTitle'.tr : 'known.add.title'.tr),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isEditing ? 'known.add.editSubtitle'.tr : 'known.add.subtitle'.tr,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),

              /// Nombre
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: 'known.add.name'.tr,
                  hintText: 'known.add.nameHint'.tr,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'known.add.nameRequired'.tr : null,
              ),
              const SizedBox(height: 16),

              /// Relación
              TextFormField(
                controller: _relationCtrl,
                decoration: InputDecoration(
                  labelText: 'known.add.relation'.tr,
                  hintText: 'known.add.relationHint'.tr,
                ),
              ),
              const SizedBox(height: 16),

              /// Teléfono
              TextFormField(
                controller: _phoneCtrl,
                decoration: InputDecoration(
                  labelText: 'known.add.phone'.tr,
                  hintText: 'known.add.phoneHint'.tr,
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),

              /// Correo
              TextFormField(
                controller: _emailCtrl,
                decoration: InputDecoration(
                  labelText: 'known.add.email'.tr,
                  hintText: 'known.add.emailHint'.tr,
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 24),

              /// Foto
              Center(
                child: GestureDetector(
                  onTap: _pickPhoto,
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: cs.surfaceContainerHighest,
                    backgroundImage: (photoFile != null && photoFile.existsSync())
                        ? FileImage(photoFile)
                        : null,
                    child: (photoFile == null || !photoFile.existsSync())
                        ? Icon(Icons.camera_alt, size: 32, color: cs.onSurfaceVariant)
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              TextButton.icon(
                onPressed: _pickPhoto,
                icon: const Icon(Icons.photo_camera),
                label: Text('known.add.photoButton'.tr),
              ),
              const SizedBox(height: 32),

              _saving
                  ? const Center(child: CircularProgressIndicator())
                  : FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.save),
                      label: Text(isEditing
                          ? 'known.add.save'.tr
                          : 'known.add.submit'.tr),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
