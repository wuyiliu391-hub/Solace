import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/services/workspace_service.dart';

void main() {
  test('workspace resolves files without allowing traversal', () async {
    final root = await Directory.systemTemp.createTemp('solace_workspace_');
    addTearDown(() => root.delete(recursive: true));
    final service = WorkspaceService(
      null,
      pathResolver: (chatId) => chatId == 'chat' ? root.path : null,
    );
    final file = service.resolveFile('chat', 'lib/main.dart');
    expect(file.path, contains('lib'));
    expect(
        () => service.resolveFile('chat', '../outside.txt'), throwsStateError);
  });
}
