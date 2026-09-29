// ignore_for_file: avoid_print
//
// Solace 版本号一键同步脚本
//
// 用法：
//   dart run scripts/bump_version.dart 20.0.0 8400
//   dart run scripts/bump_version.dart 20.0.0 8400 --dry-run
//
// 会同步更新以下 5 处版本号，并保持格式一致：
//   1. pubspec.yaml                                version: x.x.x+build
//   2. lib/config/constants.dart                   AppVersion.version / AppVersion.build
//   3. lib/config/constants.dart                   DbDefaults.dbVersion （可选，用 --db 指定）
//   4. solace/version.json                         version / build
//   5. solace/_worker.js                           VERSION_DATA.latestVersion / buildNumber
//
// 说明：solace/*.html 的页脚版本号需要人工检查，脚本会提示。

import 'dart:io';

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  final dbArgIdx = args.indexOf('--db');
  final newDbVersion = dbArgIdx >= 0 && dbArgIdx + 1 < args.length
      ? int.tryParse(args[dbArgIdx + 1])
      : null;

  final positional =
      args.where((a) => !a.startsWith('--')).toList(growable: false);

  if (positional.length < 2) {
    print('用法: dart run scripts/bump_version.dart <version> <build> [--db <dbVersion>] [--dry-run]');
    print('例:   dart run scripts/bump_version.dart 20.0.0 8400');
    exit(1);
  }

  final newVersion = positional[0];
  final newBuild = int.tryParse(positional[1]);
  if (newBuild == null) {
    print('错误: build 必须是整数');
    exit(1);
  }

  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(newVersion)) {
    print('警告: 版本号 ' + newVersion + ' 不是 x.y.z 格式，继续执行');
  }

  final root = Directory.current;

  _updatePubspec(root, newVersion, newBuild, dryRun);
  _updateConstants(root, newVersion, newBuild, newDbVersion, dryRun);
  _updateVersionJson(root, newVersion, newBuild, dryRun);
  _updateWorkerJs(root, newVersion, newBuild, dryRun);

  print('');
  print('完成' + (dryRun ? '（dry-run 未写入）' : ''));
  print('提醒: 请人工检查 solace/*.html 页脚版本号是否需同步。');
}

void _updatePubspec(Directory root, String v, int b, bool dryRun) {
  final f = File(root.path + '/pubspec.yaml');
  if (!f.existsSync()) {
    print('[SKIP] pubspec.yaml 不存在');
    return;
  }
  final content = f.readAsStringSync();
  final re = RegExp(r'^version:\s*[^\s]+', multiLine: true);
  if (!re.hasMatch(content)) {
    print('[WARN] pubspec.yaml 未找到 version 字段');
    return;
  }
  final updated = content.replaceFirstMapped(re, (m) => 'version: ' + v + '+' + b.toString());
  _write(f, content, updated, dryRun, 'pubspec.yaml');
}

void _updateConstants(Directory root, String v, int b, int? db, bool dryRun) {
  final f = File(root.path + '/lib/config/constants.dart');
  if (!f.existsSync()) {
    print('[SKIP] lib/config/constants.dart 不存在');
    return;
  }
  var content = f.readAsStringSync();
  final orig = content;

  content = content.replaceFirstMapped(
    RegExp(r"static const String version = '[^']*';"),
    (m) => "static const String version = '" + v + "';",
  );
  content = content.replaceFirstMapped(
    RegExp(r'static const int build = \d+;'),
    (m) => 'static const int build = ' + b.toString() + ';',
  );

  if (db != null) {
    content = content.replaceFirstMapped(
      RegExp(r'static const int dbVersion = \d+;'),
      (m) => 'static const int dbVersion = ' + db.toString() + ';',
    );
  }

  final label = 'lib/config/constants.dart' + (db != null ? ' (含 dbVersion=' + db.toString() + ')' : '');
  _write(f, orig, content, dryRun, label);
}

void _updateVersionJson(Directory root, String v, int b, bool dryRun) {
  final f = File(root.path + '/solace/version.json');
  if (!f.existsSync()) {
    print('[SKIP] solace/version.json 不存在');
    return;
  }
  var content = f.readAsStringSync();
  final orig = content;
  content = content.replaceFirstMapped(
    RegExp(r'"version":\s*"[^"]*"'),
    (m) => '"version": "' + v + '"',
  );
  content = content.replaceFirstMapped(
    RegExp(r'"build":\s*\d+'),
    (m) => '"build": ' + b.toString(),
  );
  content = content.replaceFirstMapped(
    RegExp(r'"downloadUrl":\s*"[^"]*"'),
    (m) => '"downloadUrl": "https://solace-auth-v2.pages.dev/api/v1/download?v=' + v + '"',
  );
  _write(f, orig, content, dryRun, 'solace/version.json');
}

void _updateWorkerJs(Directory root, String v, int b, bool dryRun) {
  final f = File(root.path + '/solace/_worker.js');
  if (!f.existsSync()) {
    print('[SKIP] solace/_worker.js 不存在');
    return;
  }
  var content = f.readAsStringSync();
  final orig = content;
  content = content.replaceFirstMapped(
    RegExp(r"latestVersion:\s*'[^']*'"),
    (m) => "latestVersion: '" + v + "'",
  );
  content = content.replaceFirstMapped(
    RegExp(r'buildNumber:\s*\d+'),
    (m) => 'buildNumber: ' + b.toString(),
  );
  content = content.replaceFirstMapped(
    RegExp(r"downloadUrl:\s*'[^']*'"),
    (m) => "downloadUrl: 'https://solace-auth-v2.pages.dev/api/v1/download?v=" + v + "'",
  );
  _write(f, orig, content, dryRun, 'solace/_worker.js');
}

void _write(File f, String oldContent, String newContent, bool dryRun, String label) {
  if (oldContent == newContent) {
    print('[SAME] ' + label + ' 未变化');
    return;
  }
  if (dryRun) {
    print('[DRY ] ' + label + ' 将更新');
    return;
  }
  f.writeAsStringSync(newContent);
  print('[OK  ] ' + label + ' 已更新');
}
