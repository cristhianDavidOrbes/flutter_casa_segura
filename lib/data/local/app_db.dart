import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();

  static const _dbName = 'casa_segura.db';
  static const _dbVersion = 4;

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _openDatabase();
    return _database!;
  }

  Future<Database> _openDatabase() async {
    final dbDir = await getDatabasesPath();
    final dbPath = p.join(dbDir, _dbName);

    return openDatabase(
      dbPath,
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE ${FamilyMember.tableName} (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            relation TEXT NOT NULL,
            phone TEXT,
            email TEXT,
            profile_image_path TEXT,
            entry_start TEXT,
            entry_end TEXT,
            schedules_json TEXT,
            created_at INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE ${Device.tableName} (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            ip TEXT,
            owner_id INTEGER,
            added_at INTEGER NOT NULL,
            last_seen_at INTEGER,
            home_active INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY(owner_id) REFERENCES ${FamilyMember.tableName}(id)
              ON DELETE SET NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE ${PersonOfInterest.tableName} (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            label TEXT NOT NULL,
            note TEXT,
            is_suspect INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE ${Event.tableName} (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id INTEGER NOT NULL,
            member_id INTEGER,
            poi_id INTEGER,
            type TEXT NOT NULL,
            ts INTEGER NOT NULL,
            image_path TEXT,
            FOREIGN KEY(device_id) REFERENCES ${Device.tableName}(id)
              ON DELETE CASCADE,
            FOREIGN KEY(member_id) REFERENCES ${FamilyMember.tableName}(id)
              ON DELETE SET NULL,
            FOREIGN KEY(poi_id) REFERENCES ${PersonOfInterest.tableName}(id)
              ON DELETE SET NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE ${Device.tableName} ADD COLUMN home_active INTEGER NOT NULL DEFAULT 0',
          );
        }
          if (oldVersion < 3) {
            await db.execute(
              'ALTER TABLE ${FamilyMember.tableName} ADD COLUMN profile_image_path TEXT',
            );
            await db.execute(
              'ALTER TABLE ${FamilyMember.tableName} ADD COLUMN entry_start TEXT',
            );
            await db.execute(
              'ALTER TABLE ${FamilyMember.tableName} ADD COLUMN entry_end TEXT',
            );
          }
          if (oldVersion < 4) {
            await db.execute(
              'ALTER TABLE ${FamilyMember.tableName} ADD COLUMN schedules_json TEXT',
            );

            final rows = await db.query(FamilyMember.tableName);
            for (final row in rows) {
              final start = (row['entry_start'] as String?)?.trim() ?? '';
              final end = (row['entry_end'] as String?)?.trim() ?? '';
              final schedules = (start.isNotEmpty && end.isNotEmpty)
                  ? jsonEncode([
                      {'start': start, 'end': end},
                    ])
                  : '[]';
              await db.update(
                FamilyMember.tableName,
                {'schedules_json': schedules},
                where: 'id = ?',
                whereArgs: [row['id']],
              );
            }
          }
        },
      );
    }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  // -------- CRUDs b!sicos --------
  Future<int> insertMember(FamilyMember member) async {
    final db = await database;
    return db.insert(
      FamilyMember.tableName,
      member.toMap(includeId: false),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<int> insertDevice(Device device) async {
    final db = await database;
    return db.insert(
      Device.tableName,
      device.toMap(includeId: false),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int> insertPoi(PersonOfInterest poi) async {
    final db = await database;
    return db.insert(
      PersonOfInterest.tableName,
      poi.toMap(includeId: false),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<int> insertEvent(Event event) async {
    final db = await database;
    return db.insert(
      Event.tableName,
      event.toMap(includeId: false),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<List<EventWithJoins>> lastEvents({int limit = 50}) async {
    final db = await database;
    final rows = await db.query(
      Event.tableName,
      orderBy: 'ts DESC',
      limit: limit,
    );

    final events = rows.map(Event.fromMap).toList();

    final deviceIds = <int>{
      for (final e in events)
        if (e.deviceId != null) e.deviceId!,
    };
    final poiIds = <int>{
      for (final e in events)
        if (e.poiId != null) e.poiId!,
    };

    final devicesById = await _fetchDevicesByIds(db, deviceIds);
    final poisById = await _fetchPoisByIds(db, poiIds);

    return [
      for (final e in events)
        EventWithJoins(
          e,
          e.deviceId != null ? devicesById[e.deviceId!] : null,
          e.poiId != null ? poisById[e.poiId!] : null,
        ),
    ];
  }

  Future<Map<int, Device>> _fetchDevicesByIds(Database db, Set<int> ids) async {
    if (ids.isEmpty) return const {};
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.query(
      Device.tableName,
      where: 'id IN ($placeholders)',
      whereArgs: ids.toList(),
    );
    return {for (final r in rows) Device.fromMap(r).id!: Device.fromMap(r)};
  }

  Future<Map<int, PersonOfInterest>> _fetchPoisByIds(
    Database db,
    Set<int> ids,
  ) async {
    if (ids.isEmpty) return const {};
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.query(
      PersonOfInterest.tableName,
      where: 'id IN ($placeholders)',
      whereArgs: ids.toList(),
    );
    return {
      for (final r in rows)
        PersonOfInterest.fromMap(r).id!: PersonOfInterest.fromMap(r),
    };
  }

  // -------- Helpers de dispositivos --------

  /// Inserta o actualiza por `device_id` (único).
  /// Devuelve el rowId si insertó (0 si solo actualizó).
  Future<int> upsertDeviceByDeviceId({
    required String deviceId,
    required String name,
    required String type,
    String? ip,
    required int addedAt,
    int? lastSeenAt,
  }) async {
    final db = await database;

    // insert IGNORE
    final inserted = await db.insert(Device.tableName, {
      'device_id': deviceId,
      'name': name,
      'type': type,
      'ip': ip,
      'owner_id': null,
      'added_at': addedAt,
      'last_seen_at': lastSeenAt ?? addedAt,
      'home_active': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    if (inserted != 0) return inserted;

    // update si ya existía
    await db.update(
      Device.tableName,
      {
        'name': name,
        'type': type,
        'ip': ip,
        'last_seen_at': lastSeenAt ?? DateTime.now().millisecondsSinceEpoch,
      },
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
    return 0;
  }

  /// Marca como visto (y actualiza ip/name/type si se pasan).
  Future<void> touchDeviceSeen(
    String deviceId, {
    String? ip,
    String? name,
    String? type,
    int? whenMs,
  }) async {
    final db = await database;
    final now = whenMs ?? DateTime.now().millisecondsSinceEpoch;
    final values = <String, Object?>{'last_seen_at': now};
    if (ip != null) values['ip'] = ip;
    if (name != null) values['name'] = name;
    if (type != null) values['type'] = type;

    await db.update(
      Device.tableName,
      values,
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
  }

  /// Borra por `device_id`.
  Future<void> deleteDeviceByDeviceId(String deviceId) async {
    final db = await database;
    await db.delete(
      Device.tableName,
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
  }

  Future<void> setDeviceHomeActive(String deviceId, bool active) async {
    final db = await database;
    await db.update(
      Device.tableName,
      {'home_active': active ? 1 : 0},
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
  }

  /// Lista todos.
  Future<List<Device>> fetchAllDevices() async {
    final db = await database;
    final rows = await db.query(
      Device.tableName,
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(Device.fromMap).toList();
  }

  /// Obtiene uno por `device_id`.
  Future<Device?> getDeviceByDeviceId(String deviceId) async {
    final db = await database;
    final rows = await db.query(
      Device.tableName,
      where: 'device_id = ?',
      whereArgs: [deviceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Device.fromMap(rows.first);
  }
}

// ========================= Modelos =========================

class FamilySchedule {
  const FamilySchedule({required this.start, required this.end});

  final String start;
  final String end;

  Map<String, dynamic> toJson() => {'start': start, 'end': end};

  factory FamilySchedule.fromJson(Map<String, dynamic> json) => FamilySchedule(
        start: (json['start'] as String? ?? '').trim(),
        end: (json['end'] as String? ?? '').trim(),
      );
}

class FamilyMember {
  const FamilyMember({
    this.id,
    required this.name,
    required this.relation,
    this.phone,
    this.email,
    this.profileImagePath,
    this.schedules = const <FamilySchedule>[],
    required this.createdAt,
  });

  static const tableName = 'family_members';

  final int? id;
  final String name;
  final String relation;
  final String? phone;
  final String? email;
  final String? profileImagePath;
  final List<FamilySchedule> schedules;
  final int createdAt;

  FamilySchedule? get primarySchedule =>
      schedules.isNotEmpty ? schedules.first : null;

  String? get entryStart {
    final value = primarySchedule?.start.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  String? get entryEnd {
    final value = primarySchedule?.end.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  FamilyMember copyWith({
    int? id,
    String? name,
    String? relation,
    String? phone,
    String? email,
    String? profileImagePath,
    List<FamilySchedule>? schedules,
    int? createdAt,
  }) {
    return FamilyMember(
      id: id ?? this.id,
      name: name ?? this.name,
      relation: relation ?? this.relation,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      profileImagePath: profileImagePath ?? this.profileImagePath,
      schedules: schedules ?? this.schedules,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap({bool includeId = true}) {
    final primary = primarySchedule;
    final map = <String, Object?>{
      'name': name,
      'relation': relation,
      'phone': phone,
      'email': email,
      'profile_image_path': profileImagePath,
      'entry_start': primary?.start,
      'entry_end': primary?.end,
      'schedules_json': schedules.isEmpty
          ? '[]'
          : jsonEncode(
              schedules
                  .map((schedule) => schedule.toJson())
                  .toList(growable: false),
            ),
      'created_at': createdAt,
    };
    if (includeId && id != null) map['id'] = id;
    return map;
  }

  static FamilyMember fromMap(Map<String, Object?> map) {
    final jsonRaw = map['schedules_json'] as String?;
    List<FamilySchedule> parsedSchedules = const [];
    if (jsonRaw != null && jsonRaw.trim().isNotEmpty) {
      try {
        final data = jsonDecode(jsonRaw) as List<dynamic>;
        parsedSchedules = data
            .whereType<Map<String, dynamic>>()
            .map(FamilySchedule.fromJson)
            .where((schedule) =>
                schedule.start.isNotEmpty && schedule.end.isNotEmpty)
            .toList();
      } catch (_) {
        parsedSchedules = const [];
      }
    }

    if (parsedSchedules.isEmpty) {
      final legacyStart = (map['entry_start'] as String?)?.trim() ?? '';
      final legacyEnd = (map['entry_end'] as String?)?.trim() ?? '';
      if (legacyStart.isNotEmpty && legacyEnd.isNotEmpty) {
        parsedSchedules = [
          FamilySchedule(start: legacyStart, end: legacyEnd),
        ];
      }
    }

    return FamilyMember(
      id: map['id'] as int?,
      name: map['name'] as String,
      relation: map['relation'] as String,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      profileImagePath: map['profile_image_path'] as String?,
      schedules: parsedSchedules,
      createdAt: map['created_at'] as int,
    );
  }
}

class Device {
  const Device({
    this.id,
    required this.deviceId,
    required this.name,
    required this.type,
    this.ip,
    this.ownerId,
    required this.addedAt,
    this.lastSeenAt,
    this.homeActive = false,
  });

  static const tableName = 'devices';

  final int? id;
  final String deviceId;
  final String name;
  final String type;
  final String? ip;
  final int? ownerId;
  final int addedAt;
  final int? lastSeenAt;
  final bool homeActive;

  Device copyWith({
    int? id,
    String? deviceId,
    String? name,
    String? type,
    String? ip,
    int? ownerId,
    int? addedAt,
    int? lastSeenAt,
    bool? homeActive,
  }) {
    return Device(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      name: name ?? this.name,
      type: type ?? this.type,
      ip: ip ?? this.ip,
      ownerId: ownerId ?? this.ownerId,
      addedAt: addedAt ?? this.addedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      homeActive: homeActive ?? this.homeActive,
    );
  }

  Map<String, Object?> toMap({bool includeId = true}) {
    final map = <String, Object?>{
      'device_id': deviceId,
      'name': name,
      'type': type,
      'ip': ip,
      'owner_id': ownerId,
      'added_at': addedAt,
      'last_seen_at': lastSeenAt,
      'home_active': homeActive ? 1 : 0,
    };
    if (includeId && id != null) map['id'] = id;
    return map;
  }

  static Device fromMap(Map<String, Object?> map) => Device(
    id: map['id'] as int?,
    deviceId: map['device_id'] as String,
    name: map['name'] as String,
    type: map['type'] as String,
    ip: map['ip'] as String?,
    ownerId: map['owner_id'] as int?,
    addedAt: map['added_at'] as int,
    lastSeenAt: map['last_seen_at'] as int?,
    homeActive: (map['home_active'] as int? ?? 0) != 0,
  );
}

class PersonOfInterest {
  const PersonOfInterest({
    this.id,
    required this.label,
    this.note,
    this.isSuspect = true,
    required this.createdAt,
  });

  static const tableName = 'persons_of_interest';

  final int? id;
  final String label;
  final String? note;
  final bool isSuspect;
  final int createdAt;

  PersonOfInterest copyWith({
    int? id,
    String? label,
    String? note,
    bool? isSuspect,
    int? createdAt,
  }) {
    return PersonOfInterest(
      id: id ?? this.id,
      label: label ?? this.label,
      note: note ?? this.note,
      isSuspect: isSuspect ?? this.isSuspect,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap({bool includeId = true}) {
    final map = <String, Object?>{
      'label': label,
      'note': note,
      'is_suspect': isSuspect ? 1 : 0,
      'created_at': createdAt,
    };
    if (includeId && id != null) map['id'] = id;
    return map;
  }

  static PersonOfInterest fromMap(Map<String, Object?> map) => PersonOfInterest(
    id: map['id'] as int?,
    label: map['label'] as String,
    note: map['note'] as String?,
    isSuspect: (map['is_suspect'] as int? ?? 1) == 1,
    createdAt: map['created_at'] as int,
  );
}

class Event {
  const Event({
    this.id,
    required this.deviceId,
    this.memberId,
    this.poiId,
    required this.type,
    required this.ts,
    this.imagePath,
  });

  static const tableName = 'events';

  final int? id;
  final int? deviceId;
  final int? memberId;
  final int? poiId;
  final String type;
  final int ts;
  final String? imagePath;

  Event copyWith({
    int? id,
    int? deviceId,
    int? memberId,
    int? poiId,
    String? type,
    int? ts,
    String? imagePath,
  }) {
    return Event(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      memberId: memberId ?? this.memberId,
      poiId: poiId ?? this.poiId,
      type: type ?? this.type,
      ts: ts ?? this.ts,
      imagePath: imagePath ?? this.imagePath,
    );
  }

  Map<String, Object?> toMap({bool includeId = true}) {
    final map = <String, Object?>{
      'device_id': deviceId,
      'member_id': memberId,
      'poi_id': poiId,
      'type': type,
      'ts': ts,
      'image_path': imagePath,
    };
    if (includeId && id != null) map['id'] = id;
    return map;
  }

  static Event fromMap(Map<String, Object?> map) => Event(
    id: map['id'] as int?,
    deviceId: map['device_id'] as int?,
    memberId: map['member_id'] as int?,
    poiId: map['poi_id'] as int?,
    type: map['type'] as String,
    ts: map['ts'] as int,
    imagePath: map['image_path'] as String?,
  );
}

class EventWithJoins {
  const EventWithJoins(this.event, this.device, this.poi);
  final Event event;
  final Device? device;
  final PersonOfInterest? poi;
}
