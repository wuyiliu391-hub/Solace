import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'https://solace-sync.2425638815.workers.dev';

  // 测试1: 健康检查
  print('=== 健康检查 ===');
  final health = await http.get(Uri.parse('$baseUrl/api/v1/health'));
  print('Status: ${health.statusCode}');
  print('Body: ${health.body}');

  // 测试2: 用 QQ 号注册
  const testQq = '99999888';
  const testPassword = 'Test1234';
  print('\n=== QQ号注册 ===');
  final register = await http.post(
    Uri.parse('$baseUrl/api/v1/auth/register'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'qq': testQq, 'password': testPassword}),
  );
  print('Status: ${register.statusCode}');
  print('Body: ${register.body}');

  final registerData = jsonDecode(register.body) as Map<String, dynamic>;
  final token = registerData['token'] as String?;
  final userId = registerData['userId'] as String?;
  print('Token: $token');
  print('UserId: $userId');

  if (token == null) {
    print('注册失败，退出');
    return;
  }

  // 测试3: 重复注册（等同于登录）
  print('\n=== 重复注册（等同于登录） ===');
  final login = await http.post(
    Uri.parse('$baseUrl/api/v1/auth/register'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'qq': testQq, 'password': testPassword}),
  );
  print('Status: ${login.statusCode}');
  print('Body: ${login.body}');

  // 测试4: 密码错误
  print('\n=== 密码错误测试 ===');
  final wrongPw = await http.post(
    Uri.parse('$baseUrl/api/v1/auth/register'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'qq': testQq, 'password': 'wrongpassword'}),
  );
  print('Status: ${wrongPw.statusCode} (期望 401)');
  print('Body: ${wrongPw.body}');

  // 测试5: 推送大量变更（模拟老用户首次全量同步）
  print('\n=== 推送大量变更（模拟老用户首次同步） ===');
  final bigChanges = <String, List<Map<String, dynamic>>>{};

  // 10条 users
  bigChanges['users'] = [
    {
      'id': testQq,
      'data': {'nickname': 'QQ用户9888', 'coins': 100, 'totalCoinsEarned': 100, 'totalCoinsSpent': 0},
      'deleted': false,
    },
  ];

  // 50条 chat_messages（测试 D1 大批量）
  final messages = <Map<String, dynamic>>[];
  for (var i = 0; i < 50; i++) {
    messages.add({
      'id': 'msg_${i.toString().padLeft(3, '0')}',
      'data': {
        'chatId': 'session_001',
        'senderId': i % 2 == 0 ? testQq : 'char_001',
        'content': '这是第${i + 1}条聊天消息，测试D1存储能力',
        'type': 0,
        'status': 1,
      },
      'deleted': false,
    });
  }
  bigChanges['chat_messages'] = messages;

  // 3条 ai_characters
  bigChanges['ai_characters'] = [
    {'id': 'char_001', 'data': {'name': '小月', 'personality': '温柔'}, 'deleted': false},
    {'id': 'char_002', 'data': {'name': '阿星', 'personality': '开朗'}, 'deleted': false},
    {'id': 'char_003', 'data': {'name': '雨薇', 'personality': '文静'}, 'deleted': false},
  ];

  final sync1 = await http.post(
    Uri.parse('$baseUrl/api/v1/user/data/sync'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    },
    body: jsonEncode({'lastSeq': 0, 'changes': bigChanges}),
  );
  print('Status: ${sync1.statusCode}');
  final sync1Data = jsonDecode(sync1.body) as Map<String, dynamic>;
  print('maxSeq: ${sync1Data['maxSeq']}');
  final sync1Changes = sync1Data['changes'] as Map<String, dynamic>;
  for (final entry in sync1Changes.entries) {
    print('  ${entry.key}: ${(entry.value as List).length} 条记录');
  }

  // 测试6: 增量拉取（lastSeq > 0）
  final maxSeq = sync1Data['maxSeq'] as int;
  print('\n=== 增量拉取 (lastSeq=$maxSeq) ===');
  final sync2 = await http.post(
    Uri.parse('$baseUrl/api/v1/user/data/sync'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    },
    body: jsonEncode({'lastSeq': maxSeq, 'changes': {}}),
  );
  print('Status: ${sync2.statusCode}');
  final sync2Data = jsonDecode(sync2.body) as Map<String, dynamic>;
  print('maxSeq: ${sync2Data['maxSeq']} (期望 $maxSeq)');
  final sync2Changes = sync2Data['changes'] as Map<String, dynamic>;
  print('changes: ${sync2Changes.length} 张表 (期望 0)');

  // 测试7: 再推送一条变更 + 拉取
  print('\n=== 追加变更 + 增量拉取 ===');
  final sync3 = await http.post(
    Uri.parse('$baseUrl/api/v1/user/data/sync'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    },
    body: jsonEncode({
      'lastSeq': maxSeq,
      'changes': {
        'memories': [
          {'id': 'mem_001', 'data': {'content': '用户喜欢猫咪', 'importance': 5}, 'deleted': false},
        ],
      },
    }),
  );
  print('Status: ${sync3.statusCode}');
  final sync3Data = jsonDecode(sync3.body) as Map<String, dynamic>;
  print('maxSeq: ${sync3Data['maxSeq']}');
  final sync3Changes = sync3Data['changes'] as Map<String, dynamic>;
  for (final entry in sync3Changes.entries) {
    print('  ${entry.key}: ${(entry.value as List).length} 条记录');
  }

  // 测试8: 覆盖已有记录（更新同一 id）
  print('\n=== 覆盖更新（同一 record_id） ===');
  final sync4 = await http.post(
    Uri.parse('$baseUrl/api/v1/user/data/sync'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    },
    body: jsonEncode({
      'lastSeq': maxSeq,
      'changes': {
        'users': [
          {'id': testQq, 'data': {'nickname': '改名后的用户', 'coins': 200}, 'deleted': false},
        ],
      },
    }),
  );
  print('Status: ${sync4.statusCode}');
  final sync4Data = jsonDecode(sync4.body) as Map<String, dynamic>;
  print('maxSeq: ${sync4Data['maxSeq']}');

  // 测试9: 获取同步状态
  print('\n=== 获取同步状态 ===');
  final status = await http.get(
    Uri.parse('$baseUrl/api/v1/user/data/status'),
    headers: {'Authorization': 'Bearer $token'},
  );
  print('Status: ${status.statusCode}');
  print('Body: ${jsonDecode(status.body)}');

  print('\n✅ 所有 D1 测试完成！');
}
