import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mynotes/extensions/list/filter.dart';
import 'package:mynotes/services/crud/crud_exceptions.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
class NoteService {
  Database? _db;
  List<DatabaseNote> _notes = [];
  DatabaseUser? _user;
  static final NoteService _shared = NoteService._sharedInstance();
  NoteService._sharedInstance(){
    _notesStreamController = StreamController<List<DatabaseNote>>.broadcast(
      onListen : () {
      _notesStreamController.sink.add(_notes);
      },
    );
  }
  factory NoteService() =>  _shared;
  late final StreamController<List<DatabaseNote>> _notesStreamController;

  Future<void> _cacheNotes() async {
    await _ensureDbIsOpen();
    final allNotes = await getAllNote();
    _notes = allNotes.toList();
    _notesStreamController.add(_notes);
  }

  Stream<List<DatabaseNote>> get allNotes =>
    _notesStreamController.stream.filter((note){
      final currentUser = _user;
      if(currentUser != null){
        return note.userId == currentUser.id;
      }
      else{
        throw UserShouldBeSetBeforeReadingAllNotes();
      }
    });

  Future<DatabaseUser> getOrCreateUser({required String email,bool setAsCurrentUser = true}) async {
    try{
      final user = await getUser(email: email);
      if(setAsCurrentUser){
        _user = user;
      }
      return user;
    } on UserNotFound{
      final user = await createUser(email: email);
      if(setAsCurrentUser){
        _user = user;
      }
      return user;
    }catch (e){
      rethrow;
    }
  }

  Future<DatabaseNote> updateNote({required DatabaseNote note,required String text} )async{
    await _ensureDbIsOpen();
    final db = _getDataBaseOrThrow();
    await getNote(id:note.id);
    final upDateCount = await db.update(noteTable,{textColumn:text,
    isSyncedWithCloudColumn:0},where: 'id = ?',whereArgs:[note.id]);
    if (upDateCount == 0){
      throw CouldNotUpdateNote();
    }else{
      final updatedNote = await getNote(id: note.id);
      _notes.removeWhere((note) => note.id == updatedNote.id);
      _notes.add(updatedNote);
      _notesStreamController.add(_notes);
      return updatedNote;
    }
  }
  
  Future<DatabaseNote> createNote({required DatabaseUser owner}) async {
    await _ensureDbIsOpen();
    final db = _getDataBaseOrThrow();
    final dbUser = await getUser(email: owner.email);
    if (dbUser != owner) {
      throw UserNotFound();
    }
    const text = '';
    final noteId = await db.insert(noteTable, {
      userIdColumn: owner.id,
      textColumn: text,
      isSyncedWithCloudColumn: 1,
    });
    final note = DatabaseNote(
      id: noteId,
      userId: owner.id,
      text: '',
      isSyncWithCloud: true,
    );
    _notes.add(note);
    _notesStreamController.add(_notes);
    return note;
  }

  Future<DatabaseNote> getNote({required int id}) async {
    await _ensureDbIsOpen();
    final db = _getDataBaseOrThrow();
    final notes = await db.query(
      noteTable,
      limit: 1,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (notes.isEmpty){
      throw CouldNotFindNote();
    }else{
      final note = DatabaseNote.fromRow(notes.first);
      _notes.removeWhere((n) => n.id == id);
      _notes.add(note);
      _notesStreamController.add(_notes);
      return note;
    }
  }

  Future<Iterable<DatabaseNote>> getAllNote() async {
    await _ensureDbIsOpen();
    final db = _getDataBaseOrThrow();

    final notes = await db.query(
      noteTable,
    );
    return notes.map((noteRow) => DatabaseNote.fromRow(noteRow));
  }

  Future<void> deleteNote({required int id}) async {
    await _ensureDbIsOpen();
    final db = _getDataBaseOrThrow();
    final deletedCount = await db.delete(
      noteTable,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (deletedCount == 0) {
      throw CouldNotDeleteNote();
    }
    else{
      _notes.removeWhere((note) => note.id == id);
      _notesStreamController.add(_notes);
    }
  }


  Future<int> deleteAllNotes() async {
    await _ensureDbIsOpen();
    final db = _getDataBaseOrThrow();
    final deletedCount = await db.delete(noteTable);
    _notes = [];
    _notesStreamController.add([]);
    return deletedCount;
  }

  Database _getDataBaseOrThrow() {
    final db = _db;
    if (db == null) {
      throw DatabaseNotOpen();
    } else {
      return db;
    }
  }

  
  Future<void> _ensureDbIsOpen() async {
    try {
      await open();
    } on DataBaseAlreadyOpenException {
      // empty
    }
  }
  Future<void> open() async {
    if (_db != null) {
      throw DataBaseAlreadyOpenException();
    }

    try {
      final docsPath = await getApplicationDocumentsDirectory();
      final dbPath = join(docsPath.path, dbName);
      final db = await openDatabase(dbPath);
      _db = db;

      await db.execute(createUserTable);

      await db.execute(createNotesTable);
      await _cacheNotes();
    } on MissingPlatformDirectoryException {
      throw UnableToGetDocumentsDirectory();
    }
  }

  Future<void> close() async {
    final db = _db;
    if (db == null) {
      throw DatabaseNotOpen();
    } else {
      await db.close();
      _db = null;
    }
  }

  Future<void> deleteUser({required String email}) async {
    await _ensureDbIsOpen();
    final db = _getDataBaseOrThrow();
    final deletedCount = await db.delete(
      userTable,
      where: 'email = ?',
      whereArgs: [email.toLowerCase()],
    );
    if (deletedCount != 1) {
      throw CouldNotDeleteUser();
    }
  }

  Future<DatabaseUser> createUser({required String email}) async {
    await _ensureDbIsOpen();
    final db = _getDataBaseOrThrow();
    final result = await db.query(
      userTable,
      limit: 1,
      where: 'email = ?',
      whereArgs: [email.toLowerCase()],
    );
    if (result.isNotEmpty) {
      throw UserAlreadyExists();
    }
    final userId = await db.insert(userTable, {
      emailColumn: email.toLowerCase(),
    });
    return DatabaseUser(id: userId, email: email);
  }

  Future<DatabaseUser> getUser({required String email}) async {
    await _ensureDbIsOpen();
    final db = _getDataBaseOrThrow();
    final result = await db.query(
      userTable,
      limit: 1,
      where: 'email = ?',
      whereArgs: [email.toLowerCase()],
    );
    if (result.isEmpty) {
      throw UserNotFound();
    }
    return DatabaseUser.fromRow(result.first);
  }
}

@immutable
class DatabaseUser {
  final int id;
  final String email;
  const DatabaseUser({required this.id, required this.email});

  DatabaseUser.fromRow(Map<String, Object?> map)
    : id = map[idColumn] as int,
      email = map[emailColumn] as String;

  @override
  String toString() => 'Person, ID = $id, email = $email';

  @override
  bool operator ==(covariant DatabaseUser other) => id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class DatabaseNote {
  final int id;
  final int userId;
  final String text;
  final bool isSyncWithCloud;

  DatabaseNote({
    required this.id,
    required this.userId,
    required this.text,
    required this.isSyncWithCloud,
  });

  DatabaseNote.fromRow(Map<String, Object?> map)
    : id = map[idColumn] as int,
      userId = map[userIdColumn] as int,
      text = map[textColumn] as String,
      isSyncWithCloud = (map[isSyncedWithCloudColumn] as int) == 1
          ? true
          : false;

  @override
  bool operator ==(covariant DatabaseNote other) => id == other.id;
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() =>
      'Note, ID = $id, userID = $userId, isSyncWithCloud = $isSyncWithCloud, text = $text';
}

const dbName = 'notes.db';
const noteTable = 'notes';
const userTable = 'user';
const idColumn = 'id';
const emailColumn = 'email';
const userIdColumn = 'user_id';
const textColumn = 'text';
const isSyncedWithCloudColumn = 'is_sync';

const createUserTable = '''CREATE TABLE IF NOT EXISTS "user" (
  "id"	INTEGER NOT NULL,
  "email"	TEXT NOT NULL UNIQUE,
  PRIMARY KEY("id" AUTOINCREMENT) );''';

const createNotesTable = '''CREATE TABLE IF NOT EXISTS "notes" (
	"id"	INTEGER NOT NULL,
	"is_sync"	INTEGER NOT NULL DEFAULT 0,
	"user_id"	INTEGER NOT NULL,
	"text"	TEXT,
	PRIMARY KEY("id" AUTOINCREMENT),
	FOREIGN KEY("user_id") REFERENCES "user"("id") );''';
