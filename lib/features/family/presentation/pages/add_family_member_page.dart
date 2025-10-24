import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:get/get.dart';

import 'package:flutter_seguridad_en_casa/controllers/family_controller.dart';

class AddFamilyMemberPage extends StatefulWidget {
  const AddFamilyMemberPage({super.key});

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
  String? _scheduleError;
  TimeOfDay? _entryStart;
  TimeOfDay? _entryEnd;
  String? _photoPath;
  final ImagePicker _picker = ImagePicker();

  late final FamilyController _controller;

  @override
  void initState() {
    super.initState();
    if (Get.isRegistered<FamilyController>()) {
      _controller = Get.find<FamilyController>();
    } else {
      _controller = Get.put(FamilyController(), permanent: true);
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

    if (!_validateSchedule()) {
      setState(() {});
      return;
    }

    setState(() {
      _saving = true;
      _scheduleError = null;
    });
    try {
      final member = await _controller.addMember(
        name: _nameCtrl.text.trim(),
        relation: _relationCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        profileImagePath: _photoPath,
        entryStart: _entryStart != null ? _formatTime(_entryStart!) : null,
        entryEnd: _entryEnd != null ? _formatTime(_entryEnd!) : null,
      );
      if (!mounted) return;
      Get.back(result: member);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('family.add.error'.trParams({'error': '$e'}))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _validateSchedule() {
    if (_entryStart == null || _entryEnd == null) {
      _scheduleError = null;
      return true;
    }
    final startMinutes = _entryStart!.hour * 60 + _entryStart!.minute;
    final endMinutes = _entryEnd!.hour * 60 + _entryEnd!.minute;
    if (endMinutes <= startMinutes) {
      _scheduleError = 'family.add.scheduleInvalid'.tr;
      return false;
    }
    _scheduleError = null;
    return true;
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '${hour}:${minute}';
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
      final folder = Directory(p.join(docs.path, 'family_profiles'));
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }
      final newFile = File(
        p.join(
          folder.path,
          'member_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ),
      );
      await File(picked.path).copy(newFile.path);

      if (_photoPath != null && _photoPath != newFile.path) {
        final previous = File(_photoPath!);
        if (await previous.exists()) {
          await previous.delete();
        }
      }

      if (!mounted) return;
      setState(() {
        _photoPath = newFile.path;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('family.add.photoError'.trParams({'error': '$e'}))),
      );
    }
  }

  Future<void> _pickEntryStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _entryStart ?? TimeOfDay.now(),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _entryStart = picked;
      _validateSchedule();
    });
  }

  Future<void> _pickEntryEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _entryEnd ?? (_entryStart ?? TimeOfDay.now()),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _entryEnd = picked;
      _validateSchedule();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final photoFile =
        _photoPath != null && _photoPath!.isNotEmpty ? File(_photoPath!) : null;
    final hasPhoto = photoFile?.existsSync() ?? false;
    return Scaffold(
      appBar: AppBar(title: Text('family.add.title'.tr)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'family.add.subtitle'.tr,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              _buildField(
                controller: _nameCtrl,
                label: 'family.add.name'.tr,
                hint: 'family.add.nameHint'.tr,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'family.add.nameRequired'.tr;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildField(
                controller: _relationCtrl,
                label: 'family.add.relation'.tr,
                hint: 'family.add.relationHint'.tr,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'family.add.relationRequired'.tr;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildField(
                controller: _phoneCtrl,
                label: 'family.add.phone'.tr,
                hint: 'family.add.phoneHint'.tr,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              _buildField(
                controller: _emailCtrl,
                label: 'family.add.email'.tr,
                hint: 'family.add.emailHint'.tr,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return null;
                  final hasAt = text.contains('@');
                  final hasDot = text.contains('.');
                  if (!hasAt || !hasDot) {
                    return 'family.add.emailInvalid'.tr;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _pickPhoto,
                      child: CircleAvatar(
                        radius: 48,
                        backgroundColor: cs.surfaceVariant,
                        backgroundImage:
                            hasPhoto ? FileImage(photoFile!) : null,
                        child: hasPhoto
                            ? null
                            : Icon(
                                Icons.camera_alt_outlined,
                                size: 32,
                                color: cs.onSurfaceVariant,
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.photo_camera_back_outlined),
                      label: Text('family.add.photoButton'.tr),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'family.add.scheduleTitle'.tr,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: cs.onSurface),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pickEntryStart,
                      child: Text(
                        _entryStart != null
                            ? _formatTime(_entryStart!)
                            : 'family.add.scheduleStart'.tr,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pickEntryEnd,
                      child: Text(
                        _entryEnd != null
                            ? _formatTime(_entryEnd!)
                            : 'family.add.scheduleEnd'.tr,
                      ),
                    ),
                  ),
                ],
              ),
              if (_scheduleError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _scheduleError!,
                  style: TextStyle(color: cs.error),
                ),
              ],
              if (_entryStart != null || _entryEnd != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        _entryStart = null;
                        _entryEnd = null;
                        _scheduleError = null;
                      });
                    },
                    child: Text('family.add.scheduleClear'.tr),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              _saving
                  ? const Center(child: CircularProgressIndicator())
                  : FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.save_outlined),
                      label: Text('family.add.submit'.tr),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    TextInputAction? textInputAction,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}




