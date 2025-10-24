import 'package:flutter_seguridad_en_casa/data/local/app_db.dart';

class FamilyRepository {
  FamilyRepository._();

  static final FamilyRepository instance = FamilyRepository._();

  final AppDb _db = AppDb.instance;

  Future<List<FamilyMember>> listMembers() async {
    final db = await _db.database;
    final rows = await db.query(
      FamilyMember.tableName,
      orderBy: 'created_at DESC',
    );
    if (rows.isEmpty) return const <FamilyMember>[];
    return rows.map(FamilyMember.fromMap).toList();
  }

  Future<FamilyMember> insertMember(FamilyMember member) async {
    final id = await _db.insertMember(member);
    return member.copyWith(id: id);
  }

  Future<FamilyMember?> getMember(int id) async {
    final db = await _db.database;
    final rows = await db.query(
      FamilyMember.tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return FamilyMember.fromMap(rows.first);
  }

  Future<List<Event>> recentPresenceEvents(
    int memberId, {
    int limit = 4,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      Event.tableName,
      where: 'member_id = ? AND (type = ? OR type = ? OR type = ?)',
      whereArgs: [memberId, 'entry', 'exit', 'entry_out_of_schedule'],
      orderBy: 'ts DESC',
      limit: limit,
    );
    if (rows.isEmpty) return const <Event>[];
    return rows.map(Event.fromMap).toList();
  }

  Future<void> recordPresenceEvent({
    required int memberId,
    required int deviceId,
    required String type,
    required int timestamp,
    String? imagePath,
  }) async {
    final event = Event(
      memberId: memberId,
      deviceId: deviceId,
      poiId: null,
      type: type,
      ts: timestamp,
      imagePath: imagePath,
    );
    await _db.insertEvent(event);
  }
}
