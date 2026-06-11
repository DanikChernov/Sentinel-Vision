import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile_sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../models/bounding_box.dart';
import '../../models/learning_models.dart';
import '../../models/video_source.dart';

class UsageMemoryStore {
  UsageMemoryStore({this.storageRootPath});

  final String? storageRootPath;

  Database? _database;
  Directory? _rootDirectory;
  Directory? _cropDirectory;
  Directory? _exportDirectory;
  String? _databasePath;

  String? get databasePath => _databasePath;

  Future<void> initialize() async {
    if (_database != null) {
      return;
    }

    final rootPath = storageRootPath ?? await _resolveDefaultRootPath();
    // Keep all learning artifacts on-device under app support storage.
    _rootDirectory = Directory(p.join(rootPath, 'sentinel_learning_core'));
    await _rootDirectory!.create(recursive: true);

    _cropDirectory = Directory(p.join(_rootDirectory!.path, 'training_crops'));
    await _cropDirectory!.create(recursive: true);

    _exportDirectory = Directory(p.join(_rootDirectory!.path, 'exports'));
    await _exportDirectory!.create(recursive: true);

    _databasePath = p.join(_rootDirectory!.path, 'sentinel_learning.db');
    _database = await _openDatabase(_databasePath!);
  }

  Future<void> dispose() async {
    await _database?.close();
    _database = null;
  }

  Future<Directory> get cropDirectory async {
    await initialize();
    return _cropDirectory!;
  }

  Future<Directory> get exportDirectory async {
    await initialize();
    return _exportDirectory!;
  }

  Future<void> saveObservation({
    required String trackId,
    required String stableLabel,
    required String classLabel,
    required String detectorLabel,
    required String? learnedLabel,
    required double detectorConfidence,
    required double adaptiveConfidence,
    required double? identityConfidence,
    required VisionSourceType sourceType,
    required DateTime observedAt,
    required BoundingBox boundingBox,
    required bool recoveredInFrame,
    required bool falsePositive,
  }) async {
    final db = await _db;
    await db.insert('observations', <String, Object?>{
      'track_id': trackId,
      'stable_label': stableLabel,
      'class_label': classLabel,
      'detector_label': detectorLabel,
      'learned_label': learnedLabel,
      'detector_confidence': detectorConfidence,
      'adaptive_confidence': adaptiveConfidence,
      'identity_confidence': identityConfidence,
      'source_type': sourceType.name,
      'observed_at': observedAt.toIso8601String(),
      'bbox_left': boundingBox.left,
      'bbox_top': boundingBox.top,
      'bbox_width': boundingBox.width,
      'bbox_height': boundingBox.height,
      'identity_recovered': recoveredInFrame ? 1 : 0,
      'false_positive': falsePositive ? 1 : 0,
    });
  }

  Future<void> saveCorrection({
    required String stableLabel,
    required String classLabel,
    required String originalLabel,
    required String? correctedLabel,
    required bool falsePositive,
    required VisionSourceType sourceType,
    required DateTime correctedAt,
    required BoundingBox boundingBox,
    required double confidence,
  }) async {
    final db = await _db;
    await db.insert('corrections', <String, Object?>{
      'stable_label': stableLabel,
      'class_label': classLabel,
      'original_label': originalLabel,
      'corrected_label': correctedLabel,
      'false_positive': falsePositive ? 1 : 0,
      'source_type': sourceType.name,
      'corrected_at': correctedAt.toIso8601String(),
      'bbox_left': boundingBox.left,
      'bbox_top': boundingBox.top,
      'bbox_width': boundingBox.width,
      'bbox_height': boundingBox.height,
      'confidence': confidence,
    });
  }

  Future<void> upsertIdentityPattern(LearnedIdentitySummary summary) async {
    final db = await _db;
    await db.insert('identity_patterns', <String, Object?>{
      'stable_label': summary.stableLabel,
      'class_label': summary.classLabel,
      'preferred_alias': summary.preferredAlias,
      'sightings': summary.sightings,
      'recoveries': summary.recoveries,
      'correction_count': summary.correctionCount,
      'average_detector_confidence': summary.averageDetectorConfidence,
      'learned_confidence': summary.learnedConfidence,
      'average_width': summary.averageWidth,
      'average_height': summary.averageHeight,
      'average_center_x': summary.averageCenterX,
      'average_center_y': summary.averageCenterY,
      'average_motion': summary.averageMotion,
      'last_seen_at': summary.lastSeenAt.toIso8601String(),
      'last_source_type': summary.lastSourceType.name,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> upsertLabelMapping(CorrectedLabelSummary summary) async {
    final db = await _db;
    await db.insert('label_mappings', <String, Object?>{
      'mapping_key': summary.key,
      'original_label': summary.originalLabel,
      'corrected_label': summary.correctedLabel,
      'usage_count': summary.usageCount,
      'false_positive_count': summary.falsePositiveCount,
      'average_learning_confidence': summary.averageLearningConfidence,
      'last_updated_at': summary.lastUpdatedAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<TrainingSampleRecord> saveTrainingSample(
    TrainingSampleRecord sample,
  ) async {
    final db = await _db;
    final id = await db.insert('training_samples', <String, Object?>{
      'crop_path': sample.cropPath,
      'original_label': sample.originalLabel,
      'corrected_label': sample.correctedLabel,
      'stable_label': sample.stableLabel,
      'confidence': sample.confidence,
      'captured_at': sample.timestamp.toIso8601String(),
      'source_type': sample.sourceType.name,
      'bbox_left': sample.boundingBox.left,
      'bbox_top': sample.boundingBox.top,
      'bbox_width': sample.boundingBox.width,
      'bbox_height': sample.boundingBox.height,
      'exported': sample.exported ? 1 : 0,
      'feedback_applied': sample.feedbackApplied ? 1 : 0,
    });
    return sample.copyWith(id: id);
  }

  Future<void> applyCorrectionToLatestTrainingSample({
    required String stableLabel,
    required String correctedLabel,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'training_samples',
      columns: <String>['id'],
      where: 'stable_label = ? AND feedback_applied = 0',
      whereArgs: <Object?>[stableLabel],
      orderBy: 'captured_at DESC',
      limit: 1,
    );

    if (rows.isEmpty) {
      return;
    }

    final id = rows.first['id'] as int;
    await db.update(
      'training_samples',
      <String, Object?>{
        'corrected_label': correctedLabel,
        'feedback_applied': 1,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> markTrainingSamplesExported(Iterable<int> ids) async {
    final db = await _db;
    for (final id in ids) {
      await db.update(
        'training_samples',
        <String, Object?>{'exported': 1},
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
    }
  }

  Future<LearningSnapshot> loadSnapshot({int sampleLimit = 24}) async {
    final db = await _db;
    final identityRows = await db.query(
      'identity_patterns',
      orderBy: 'last_seen_at DESC',
    );
    final mappingRows = await db.query(
      'label_mappings',
      orderBy: 'usage_count DESC, last_updated_at DESC',
    );
    final observationCount = await _countTableRows(db, 'observations');
    final correctionCount = await _countTableRows(db, 'corrections');
    final falsePositiveCount = await _countMatchingRows(
      db,
      'corrections',
      'false_positive = 1',
    );
    final trainingSampleCount = await _countTableRows(db, 'training_samples');
    final storageBytes = await approximateStorageBytes();

    final identities = identityRows
        .map(_identityFromRow)
        .toList(growable: false);
    final mappings = mappingRows.map(_mappingFromRow).toList(growable: false);
    final samples = await loadTrainingSamples(limit: sampleLimit);
    final averageConfidenceGain = identities.isEmpty
        ? 0.0
        : identities
                  .map((identity) {
                    return identity.learnedConfidence -
                        identity.averageDetectorConfidence;
                  })
                  .reduce((a, b) => a + b) /
              identities.length;

    return LearningSnapshot(
      metrics: LearningMetrics(
        observationCount: observationCount,
        correctionCount: correctionCount,
        falsePositiveCount: falsePositiveCount,
        trainingSampleCount: trainingSampleCount,
        identityCount: identities.length,
        correctedLabelCount: mappings.length,
        averageConfidenceGain: averageConfidenceGain,
        approximateStorageBytes: storageBytes,
      ),
      identities: identities,
      correctedLabels: mappings,
      recentSamples: samples,
    );
  }

  Future<List<TrainingSampleRecord>> loadTrainingSamples({
    int? limit = 24,
  }) async {
    final db = await _db;
    final sampleRows = await db.query(
      'training_samples',
      orderBy: 'captured_at DESC',
      limit: limit,
    );
    return sampleRows.map(_sampleFromRow).toList(growable: false);
  }

  Future<void> clearAll() async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('observations');
      await txn.delete('corrections');
      await txn.delete('identity_patterns');
      await txn.delete('label_mappings');
      await txn.delete('training_samples');
    });

    await _clearDirectory(await cropDirectory);
    await _clearDirectory(await exportDirectory);
  }

  Future<int> approximateStorageBytes() async {
    await initialize();
    var totalBytes = 0;
    final dbPath = _databasePath;
    if (dbPath != null) {
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        totalBytes += await dbFile.length();
      }
    }
    totalBytes += await _directorySize(await cropDirectory);
    totalBytes += await _directorySize(await exportDirectory);
    return totalBytes;
  }

  Future<Database> get _db async {
    await initialize();
    return _database!;
  }

  Future<String> _resolveDefaultRootPath() async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Sentinel Learning Core is not configured for web.',
      );
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
          onConfigure: _configureDatabase,
          onCreate: _createDatabase,
        ),
      );
    }

    return mobile_sqflite.openDatabase(
      path,
      version: 1,
      onConfigure: _configureDatabase,
      onCreate: _createDatabase,
    );
  }

  Future<void> _configureDatabase(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE observations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        track_id TEXT NOT NULL,
        stable_label TEXT NOT NULL,
        class_label TEXT NOT NULL,
        detector_label TEXT NOT NULL,
        learned_label TEXT,
        detector_confidence REAL NOT NULL,
        adaptive_confidence REAL NOT NULL,
        identity_confidence REAL,
        source_type TEXT NOT NULL,
        observed_at TEXT NOT NULL,
        bbox_left REAL NOT NULL,
        bbox_top REAL NOT NULL,
        bbox_width REAL NOT NULL,
        bbox_height REAL NOT NULL,
        identity_recovered INTEGER NOT NULL,
        false_positive INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE corrections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        stable_label TEXT NOT NULL,
        class_label TEXT NOT NULL,
        original_label TEXT NOT NULL,
        corrected_label TEXT,
        false_positive INTEGER NOT NULL,
        source_type TEXT NOT NULL,
        corrected_at TEXT NOT NULL,
        bbox_left REAL NOT NULL,
        bbox_top REAL NOT NULL,
        bbox_width REAL NOT NULL,
        bbox_height REAL NOT NULL,
        confidence REAL NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE identity_patterns (
        stable_label TEXT PRIMARY KEY,
        class_label TEXT NOT NULL,
        preferred_alias TEXT,
        sightings INTEGER NOT NULL,
        recoveries INTEGER NOT NULL,
        correction_count INTEGER NOT NULL,
        average_detector_confidence REAL NOT NULL,
        learned_confidence REAL NOT NULL,
        average_width REAL NOT NULL,
        average_height REAL NOT NULL,
        average_center_x REAL NOT NULL,
        average_center_y REAL NOT NULL,
        average_motion REAL NOT NULL,
        last_seen_at TEXT NOT NULL,
        last_source_type TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE label_mappings (
        mapping_key TEXT PRIMARY KEY,
        original_label TEXT NOT NULL,
        corrected_label TEXT NOT NULL,
        usage_count INTEGER NOT NULL,
        false_positive_count INTEGER NOT NULL,
        average_learning_confidence REAL NOT NULL,
        last_updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE training_samples (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        crop_path TEXT NOT NULL,
        original_label TEXT NOT NULL,
        corrected_label TEXT,
        stable_label TEXT NOT NULL,
        confidence REAL NOT NULL,
        captured_at TEXT NOT NULL,
        source_type TEXT NOT NULL,
        bbox_left REAL NOT NULL,
        bbox_top REAL NOT NULL,
        bbox_width REAL NOT NULL,
        bbox_height REAL NOT NULL,
        exported INTEGER NOT NULL,
        feedback_applied INTEGER NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX observations_stable_label_idx ON observations(stable_label)',
    );
    await db.execute(
      'CREATE INDEX corrections_stable_label_idx ON corrections(stable_label)',
    );
    await db.execute(
      'CREATE INDEX training_samples_stable_label_idx ON training_samples(stable_label)',
    );
  }

  LearnedIdentitySummary _identityFromRow(Map<String, Object?> row) {
    return LearnedIdentitySummary(
      stableLabel: row['stable_label'] as String? ?? 'unknown',
      classLabel: row['class_label'] as String? ?? 'object',
      preferredAlias: row['preferred_alias'] as String?,
      sightings: (row['sightings'] as num?)?.toInt() ?? 0,
      recoveries: (row['recoveries'] as num?)?.toInt() ?? 0,
      correctionCount: (row['correction_count'] as num?)?.toInt() ?? 0,
      averageDetectorConfidence:
          (row['average_detector_confidence'] as num?)?.toDouble() ?? 0,
      learnedConfidence: (row['learned_confidence'] as num?)?.toDouble() ?? 0,
      averageWidth: (row['average_width'] as num?)?.toDouble() ?? 0,
      averageHeight: (row['average_height'] as num?)?.toDouble() ?? 0,
      averageCenterX: (row['average_center_x'] as num?)?.toDouble() ?? 0,
      averageCenterY: (row['average_center_y'] as num?)?.toDouble() ?? 0,
      averageMotion: (row['average_motion'] as num?)?.toDouble() ?? 0,
      lastSeenAt:
          DateTime.tryParse(row['last_seen_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastSourceType: _sourceTypeFromName(
        row['last_source_type'] as String? ?? 'camera',
      ),
    );
  }

  CorrectedLabelSummary _mappingFromRow(Map<String, Object?> row) {
    return CorrectedLabelSummary(
      key: row['mapping_key'] as String? ?? 'unknown',
      originalLabel: row['original_label'] as String? ?? 'object',
      correctedLabel: row['corrected_label'] as String? ?? 'object',
      usageCount: (row['usage_count'] as num?)?.toInt() ?? 0,
      falsePositiveCount: (row['false_positive_count'] as num?)?.toInt() ?? 0,
      averageLearningConfidence:
          (row['average_learning_confidence'] as num?)?.toDouble() ?? 0,
      lastUpdatedAt:
          DateTime.tryParse(row['last_updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  TrainingSampleRecord _sampleFromRow(Map<String, Object?> row) {
    return TrainingSampleRecord(
      id: (row['id'] as num?)?.toInt(),
      cropPath: row['crop_path'] as String? ?? '',
      originalLabel: row['original_label'] as String? ?? 'object',
      correctedLabel: row['corrected_label'] as String?,
      stableLabel: row['stable_label'] as String? ?? 'unknown',
      confidence: (row['confidence'] as num?)?.toDouble() ?? 0,
      timestamp:
          DateTime.tryParse(row['captured_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      boundingBox: BoundingBox(
        left: (row['bbox_left'] as num?)?.toDouble() ?? 0,
        top: (row['bbox_top'] as num?)?.toDouble() ?? 0,
        width: (row['bbox_width'] as num?)?.toDouble() ?? 0,
        height: (row['bbox_height'] as num?)?.toDouble() ?? 0,
      ),
      sourceType: _sourceTypeFromName(
        row['source_type'] as String? ?? 'camera',
      ),
      exported: ((row['exported'] as num?)?.toInt() ?? 0) == 1,
      feedbackApplied: ((row['feedback_applied'] as num?)?.toInt() ?? 0) == 1,
    );
  }

  VisionSourceType _sourceTypeFromName(String sourceName) {
    return VisionSourceType.values.firstWhere(
      (value) => value.name == sourceName,
      orElse: () => VisionSourceType.camera,
    );
  }

  Future<int> _countTableRows(Database db, String tableName) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM $tableName');
    return (rows.first['count'] as num?)?.toInt() ?? 0;
  }

  Future<int> _countMatchingRows(
    Database db,
    String tableName,
    String whereClause,
  ) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM $tableName WHERE $whereClause',
    );
    return (rows.first['count'] as num?)?.toInt() ?? 0;
  }

  Future<void> _clearDirectory(Directory directory) async {
    if (!await directory.exists()) {
      return;
    }
    await for (final entity in directory.list()) {
      await entity.delete(recursive: true);
    }
  }

  Future<int> _directorySize(Directory directory) async {
    if (!await directory.exists()) {
      return 0;
    }

    var total = 0;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        try {
          total += await entity.length();
        } on FileSystemException {
          // Files may be created, moved, or deleted while metrics are refreshing.
        }
      }
    }
    return total;
  }
}
