import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/contracts/account_deletion.dart';
import '../../../core/utils/client_uuid.dart';

class AccountDeletionPendingStore {
  const AccountDeletionPendingStore();

  static Future<void> _writeTail = Future<void>.value();

  static const _contractKey = 'account_deletion_pending_contract';
  static const _userKey = 'account_deletion_pending_user_id';
  static const _deletionKey = 'account_deletion_pending_deletion_id';

  Future<String> getOrCreate({required String userId}) async {
    return _serialized(() async {
      final preferences = await SharedPreferences.getInstance();
      final existing = await _read(preferences, userId: userId);
      if (existing != null) return existing;
      final deletionId = newClientUuid();
      await _clear(preferences);
      await _requireWrite(preferences.setString(_userKey, userId));
      await _requireWrite(
        preferences.setString(
          _contractKey,
          accountDeletionContractVersion,
        ),
      );
      // Commit the retry identity last so a partial preference write is never
      // interpreted as an actionable deletion.
      await _requireWrite(preferences.setString(_deletionKey, deletionId));
      if (await _read(preferences, userId: userId) != deletionId) {
        await _clear(preferences);
        throw StateError('Account deletion retry identity was not persisted.');
      }
      return deletionId;
    });
  }

  Future<String?> read({required String userId}) async {
    return _serialized(() async {
      final preferences = await SharedPreferences.getInstance();
      return _read(preferences, userId: userId);
    });
  }

  Future<void> record({
    required String userId,
    required String deletionId,
  }) async {
    if (!isClientUuid(deletionId)) {
      throw StateError('Account deletion retry identity is invalid.');
    }
    await _serialized(() async {
      final preferences = await SharedPreferences.getInstance();
      await _clear(preferences);
      await _requireWrite(preferences.setString(_userKey, userId));
      await _requireWrite(
        preferences.setString(
          _contractKey,
          accountDeletionContractVersion,
        ),
      );
      await _requireWrite(preferences.setString(_deletionKey, deletionId));
      if (await _read(preferences, userId: userId) != deletionId) {
        await _clear(preferences);
        throw StateError('Account deletion retry identity was not persisted.');
      }
    });
  }

  Future<String?> _read(
    SharedPreferences preferences, {
    required String userId,
  }) async {
    final contract = preferences.getString(_contractKey);
    final storedUserId = preferences.getString(_userKey);
    final deletionId = preferences.getString(_deletionKey);
    if (contract == accountDeletionContractVersion &&
        storedUserId == userId &&
        deletionId != null &&
        isClientUuid(deletionId)) {
      return deletionId;
    }
    if (contract != null || storedUserId != null || deletionId != null) {
      await _clear(preferences);
    }
    return null;
  }

  Future<void> clearForUser({required String userId}) async {
    await _serialized(() async {
      final preferences = await SharedPreferences.getInstance();
      if (preferences.getString(_userKey) == userId) {
        await _clear(preferences);
      }
    });
  }

  Future<void> clear() async {
    await _serialized(() async {
      final preferences = await SharedPreferences.getInstance();
      await _clear(preferences);
    });
  }

  Future<void> _clear(SharedPreferences preferences) async {
    final results = await Future.wait([
      preferences.remove(_contractKey),
      preferences.remove(_userKey),
      preferences.remove(_deletionKey),
    ]);
    if (results.any((success) => !success)) {
      throw StateError('Account deletion retry identity could not be cleared.');
    }
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _writeTail = _writeTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _requireWrite(Future<bool> write) async {
    if (!await write) {
      throw StateError('Account deletion retry identity was not persisted.');
    }
  }
}
