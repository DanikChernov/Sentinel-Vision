import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile_sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../models/bounding_box.dart';
import '../../models/persistence_models.dart';

class EmbeddingMemoryStore {
  EmbeddingMemoryStore({
    this.storageRootPath,
  });

  final String? storageRootPath;

  Database? _database;
  String? _databasePath;

  Future<void> initialize() async {
    if (_database != null) {
      return;
    }

    final rootPath = storageRootPath ?? await _resolveDefaultRootPath();
    final rootDirectory = Directory(p.join(rootPath, 'sentinel_persistence'));
    await rootDirectory.create(recursive: true);

    _databasePath = p.join(rootDirectory.path, 'embedding_memory.db');
    _database = await _openDatabase(_databasePath!);
  }

  Future<void> dispose() async {
    await _database?.close();
    _database = null;
  }

  Future<List<FaceEmbeddingRecord>> loadRecords() async {
    final db = await _db;
    final rows = await db.query(
      'embedding_profiles',
      orderBy: 'last_seen_at DESC',
    );
    return rows.map(_recordFromRow).toList(growable: false);
  }

  Future<void> upsertRecord(FaceEmbeddingRecord record) async {
    final db = await _db;
    await db.insert(
      'embedding_profiles',
      <String, Object?>{
        'stable_label': record.stableLabel,
        'class_label': record.classLabel,
        'embedding_json': jsonEncode(record.embedding),
        'embedding_count': record.embeddingCount,
        'sightings': record.sightings,
        'recoveries': record.recoveries,
        'correction_count': record.correctionCount,
        'average_similarity': record.averageSimilarity,
        'average_temporal_confidence': record.averageTemporalConfidence,
        'average_face_confidence': record.averageFaceConfidence,
        'bbox_left': record.lastBoundingBox.left,
        'bbox_top': record.lastBoundingBox.top,
        'bbox_width': record.lastBoundingBox.width,
        'bbox_height': record.lastBoundingBox.height,
        'last_seen_at': record.lastSeenAt.toIso8601String(),
        'preferred_alias': record.preferredAlias,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateCorrection({
    required String stableLabel,
    required String alias,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'embedding_profiles',
      where: 'stable_label = ?',
      whereArgs: <Object?>[stableLabel],
      limit: 1,
    );
    if (rows.isEmpty) {
      return;
    }

    final record = _recordFromRow(rows.first);
    await upsertRecord(
      record.copyWith(
        preferredAlias: alias,
        correctionCount: record.correctionCount + 1,
      ),
    );
  }

  Future<void> clear() async {
    final db = await _db;
    await db.delete('embedding_profiles');
  }

  Future<int> approximateStorageBytes() async {
    await initialize();
    final dbPath = _databasePath;
    if (dbPath == null) {
      return 0;
    }
    final file = File(dbPath);
    if (!await file.exists()) {
      return 0;
    }
    return file.length();
  }

  Future<Database> get _db async {
    await initialize();
    return _database!;
  }

  Future<String> _resolveDefaultRootPath() async {
    if (kIsWeb) {
      throw UnsupportedError('Embedding memory is not configured for web.');
    }
    final supportDirectory = await getApplicationSupportDirectory();
    return supportDirectory.path;
  }

  Future<Database> _openDatabase(String path) async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      return databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: _createDatabase,
        ),
      );
    }

    return mobile_sqflite.openDatabase(
      path,
      version: 1,
      onCreate: _createDatabase,
    );
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE embedding_profiles (
        stable_label TEXT PRIMARY KEY,
        class_label TEXT NOT NULL,
        embedding_json TEXT NOT NULL,
        embedding_count INTEGER NOT NULL,
        sightings INTEGER NOT NULL,
        recoveries INTEGER NOT NULL,
        correction_count INTEGER NOT NULL,
        average_similarity REAL NOT NULL,
        average_temporal_confidence REAL NOT NULL,
        average_face_confidence REAL NOT NULL,
        bbox_left REAL NOT NULL,
        bbox_top REAL NOT NULL,
        bbox_width REAL NOT NULL,
        bbox_height REAL NOT NULL,
        last_seen_at TEXT NOT NULL,
        preferred_alias TEXT
      )
    ''');
  }

  FaceEmbeddingRecord _recordFromRow(Map<String, Object?> row) {
    final embeddingJson = row['embedding_json'] as String? ?? '[]';
    final decoded = jsonDecode(embeddingJson) as List<dynamic>;
    final embedding = decoded
        .map((value) => (value as num?)?.toDouble() ?? 0)
        .toList(growable: false);

    return FaceEmbeddingRecord(
      stableLabel: row['stable_label'] as String? ?? 'unknown',
      classLabel: row['class_label'] as String? ?? 'person',
      embedding: embedding,
      embeddingCount: (row['embedding_count'] as num?)?.toInt() ?? 0,
      sightings: (row['sightings'] as num?)?.toInt() ?? 0,
      recoveries: (row['recoveries'] as num?)?.toInt() ?? 0,
      correctionCount: (row['correction_count'] as num?)?.toInt() ?? 0,
      averageSimilarity: (row['average_similarity'] as num?)?.toDouble() ?? 0,
      averageTemporalConfidence:
          (row['average_temporal_confidence'] as num?)?.toDouble() ?? 0,
      averageFaceConfidence:
          (row['average_face_confidence'] as num?)?.toDouble() ?? 0,
      lastBoundingBox: BoundingBox(
        left: (row['bbox_left'] as num?)?.toDouble() ?? 0,
        top: (row['bbox_top'] as num?)?.toDouble() ?? 0,
        width: (row['bbox_width'] as num?)?.toDouble() ?? 0,
        height: (row['bbox_height'] as num?)?.toDouble() ?? 0,
      ),
      lastSeenAt: DateTime.tryParse(row['last_seen_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      preferredAlias: row['preferred_alias'] as String?,
    );
  }
}
