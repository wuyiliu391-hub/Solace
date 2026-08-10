import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace/repositories/local_storage_repository.dart';
import 'package:solace/services/workspace_service.dart';

void main() {
  late Directory tempDir;
  late LocalStorageRepository storage;
  late WorkspaceService workspace;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('solace-workspace-test-');
    SharedPreferences.setMockInitialValues({
      'workspace_path_chat-1': tempDir.path,
    });
    storage = LocalStorageRepository(isWeb: true);
    await storage.initialize();
    workspace = WorkspaceService(storage);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('lists workspace root directories before files', () async {
    await Directory('${tempDir.path}/lib').create();
    await File('${tempDir.path}/README.md').writeAsString('# Solace');
    await File('${tempDir.path}/pubspec.yaml').writeAsString('name: solace');

    final entries = await workspace.listDirectory('chat-1', '');

    expect(entries.map((entry) => entry['name']),
        containsAllInOrder(<String>['lib', 'README.md', 'pubspec.yaml']));
    expect(entries.first['type'], 'directory');
  });

  test('rejects directory traversal outside the workspace', () async {
    expect(
      () => workspace.listDirectory('chat-1', '../'),
      throwsA(isA<StateError>()),
    );
  });

  test('rejects rollback backups outside the workspace', () async {
    final outside = await Directory.systemTemp.createTemp('solace-outside-');
    addTearDown(() async {
      if (await outside.exists()) await outside.delete(recursive: true);
    });
    final backup = File('${outside.path}/outside.solace-backup-test');
    await backup.writeAsString('do not touch');

    await expectLater(
      workspace.rollback('chat-1', 'README.md', backup.path),
      throwsA(isA<StateError>()),
    );
    expect(await backup.readAsString(), 'do not touch');
  });

  test('reads no more than the requested byte limit', () async {
    final file = File('${tempDir.path}/large.txt');
    await file.writeAsString('0123456789');

    final content = await workspace.read('chat-1', 'large.txt', maxBytes: 4);

    expect(content, '0123');
  });

  test('returns an opaque snapshot ID that can roll back an edit', () async {
    final file = File('${tempDir.path}/README.md');
    await file.writeAsString('before');

    final result =
        await workspace.edit('chat-1', 'README.md', 'before', 'after');
    final snapshotId = result['snapshotId'] as String?;

    expect(snapshotId, isNotNull);
    expect(snapshotId, startsWith('snap-'));
    expect(result.containsKey('backupPath'), isFalse);
    await workspace.rollback('chat-1', 'README.md', snapshotId!);
    expect(await file.readAsString(), 'before');
  });

  test('rejects an existing symlink instead of following it', () async {
    final outside =
        await Directory.systemTemp.createTemp('solace-link-target-');
    addTearDown(() async {
      if (await outside.exists()) await outside.delete(recursive: true);
    });
    final target = File('${outside.path}/secret.txt');
    await target.writeAsString('outside');
    final link = Link('${tempDir.path}/linked.txt');
    try {
      await link.create(target.path);
    } on FileSystemException {
      return;
    }

    await expectLater(
      workspace.read('chat-1', 'linked.txt'),
      throwsA(isA<StateError>()),
    );
  });
}
