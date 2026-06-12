import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../core/exceptions.dart';
import '../models/face_template.dart';
import 'face_template_store.dart';

class SqfliteFaceTemplateStore implements FaceTemplateStore {
  SqfliteFaceTemplateStore({this.databaseName = 'offline_face_recognition.db'});

  final String databaseName;
  Database? _database;

  static const _table = 'face_templates';

  @override
  Future<void> initialize() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final databasePath = path.join(directory.path, databaseName);
      _database = await openDatabase(
        databasePath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE $_table (
              id TEXT PRIMARY KEY,
              label TEXT,
              embedding TEXT NOT NULL,
              metadata TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER
            )
          ''');
        },
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        FaceStorageException(
            'Failed to initialize face template store.', error),
        stackTrace,
      );
    }
  }

  @override
  Future<void> save(FaceTemplate template) async {
    final db = _requireDatabase();
    await db.insert(
      _table,
      _toRow(template),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<FaceTemplate?> findById(String id) async {
    final db = _requireDatabase();
    final rows = await db.query(
      _table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  @override
  Future<List<FaceTemplate>> findAll() async {
    final db = _requireDatabase();
    final rows = await db.query(_table, orderBy: 'created_at DESC');
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<void> delete(String id) async {
    final db = _requireDatabase();
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> clear() async {
    final db = _requireDatabase();
    await db.delete(_table);
  }

  @override
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Database _requireDatabase() {
    final db = _database;
    if (db == null) {
      throw const FaceStorageException(
          'Face template store is not initialized.');
    }
    return db;
  }

  Map<String, Object?> _toRow(FaceTemplate template) {
    return {
      'id': template.id,
      'label': template.label,
      'embedding': jsonEncode(template.embedding),
      'metadata': jsonEncode(template.metadata),
      'created_at': template.createdAt.millisecondsSinceEpoch,
      'updated_at': template.updatedAt?.millisecondsSinceEpoch,
    };
  }

  FaceTemplate _fromRow(Map<String, Object?> row) {
    final updatedAt = row['updated_at'] as int?;
    return FaceTemplate(
      id: row['id']! as String,
      label: row['label'] as String?,
      embedding: (jsonDecode(row['embedding']! as String) as List)
          .cast<num>()
          .map((e) => e.toDouble())
          .toList(),
      metadata: (jsonDecode(row['metadata']! as String) as Map)
          .cast<String, Object?>(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      updatedAt: updatedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(updatedAt),
    );
  }
}
