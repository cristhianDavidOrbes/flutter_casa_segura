import 'package:get/get.dart';

import 'package:flutter_seguridad_en_casa/data/local/app_db.dart';
import 'package:flutter_seguridad_en_casa/repositories/family_repository.dart';

class FamilyController extends GetxController {
  FamilyController({FamilyRepository? repository})
      : _repository = repository ?? FamilyRepository.instance;

  final FamilyRepository _repository;

  final RxList<FamilyMember> members = <FamilyMember>[].obs;
  final RxBool loading = false.obs;
  final RxnString error = RxnString();

  @override
  void onInit() {
    super.onInit();
    loadMembers();
  }

  Future<void> loadMembers() async {
    loading.value = true;
    error.value = null;
    try {
      final data = await _repository.listMembers();
      members.assignAll(data);
    } catch (e) {
      error.value = e.toString();
    } finally {
      loading.value = false;
    }
  }

  Future<FamilyMember?> addMember({
    required String name,
    required String relation,
    String? phone,
    String? email,
    String? profileImagePath,
    String? entryStart,
    String? entryEnd,
  }) async {
    try {
      final member = FamilyMember(
        name: name,
        relation: relation,
        phone: phone,
        email: email,
        profileImagePath: profileImagePath,
        entryStart: entryStart,
        entryEnd: entryEnd,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      final inserted = await _repository.insertMember(member);
      members.insert(0, inserted);
      return inserted;
    } catch (e) {
      error.value = e.toString();
      rethrow;
    }
  }
}

