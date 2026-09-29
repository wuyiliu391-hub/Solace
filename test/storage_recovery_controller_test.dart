import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/services/storage/storage_recovery_controller.dart';

void main() {
  late Directory tempDir;
  late String dbPath;
  late StorageRecoveryController controller;
  var initCalls = 0;
  bool initShouldFail = false;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('solace-recovery-test-');
    dbPath = '${tempDir.path}/solace.db';
    await File(dbPath).writeAsString('fake-db-bytes');
    initCalls = 0;
    initShouldFail = false;
    controller = StorageRecoveryController(
      initialize: () async {
        initCalls++;
        if (initShouldFail) throw StateError('simulated db failure');
      },
      databasePath: () async => dbPath,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('retry succeeds and reports ready when initialize passes', () async {
    final ok = await controller.retry();

    expect(ok, isTrue);
    expect(controller.state, StorageRecoveryState.ready);
    expect(initCalls, 1);
  });

  test('retry keeps failed state and exposes error when initialize throws',
      () async {
    initShouldFail = true;

    final ok = await controller.retry();

    expect(ok, isFalse);
    expect(controller.state, StorageRecoveryState.failed);
    expect(controller.errorMessage, contains('simulated db failure'));
  });

  test('exportBackup copies the raw database file and returns its path',
      () async {
    final backupPath = await controller.exportBackup();

    expect(backupPath, isNotNull);
    final backup = File(backupPath!);
    expect(await backup.exists(), isTrue);
    expect(await backup.readAsString(), 'fake-db-bytes');
    // 原始文件未被删除
    expect(await File(dbPath).exists(), isTrue);
  });

  test('resetDatabase backs up first, then deletes the original file',
      () async {
    final backupPath = await controller.resetDatabase();

    expect(backupPath, isNotNull);
    expect(await File(backupPath!).exists(), isTrue);
    expect(await File(dbPath).exists(), isFalse);
  });
}
