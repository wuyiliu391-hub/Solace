import 'package:flutter_test/flutter_test.dart';
import 'package:solace/utils/message_sanitizer.dart';

/// 输出侧代词纠错回归测试。
///
/// Bug 背景：`fixGenderPronouns` 的规则 2（全文 blanket 替换）会把**正确指代
/// 用户的代词**一起改掉。角色男 + 用户女时，AI 正确写了"她的笑容"，
/// 清洗器因文中有"我"就全改成"他的"——用户看到的就是"性别设了女、实际全是男"。
/// 修复：传入用户性别后，"对角色错、对用户对"的代词不再做全文替换。
void main() {
  group('fixGenderPronouns · 用户性别避让', () {
    test('角色男 + 用户女：指代用户的"她"不得改动', () {
      const text = '我说：“你看，她的笑容多好看。”她很开心，她说她今天不想上班。';
      final fixed = MessageSanitizer.fixGenderPronouns(
        text,
        characterGender: '男',
        characterName: '阿强',
        userGender: '女',
      );
      expect(fixed, text);
    });

    test('角色男 + 用户女：角色名邻接的错代词照改（角色专属，安全）', () {
      // 规则 2 需要文中出现"我"才激活，这里顺手覆盖该门控
      const text = '阿强他说他很累，我听了很心疼，他想休息。';
      final fixed = MessageSanitizer.fixGenderPronouns(
        text,
        characterGender: '女',
        characterName: '阿强',
        userGender: '女',
      );
      // 角色女 → 错代词是"他"，角色名邻接的"他"应改为"她"
      expect(fixed, contains('阿强她说'));
      expect(fixed, contains('她很累'));
    });

    test('角色女 + 用户男：指代用户的"他"不得改动', () {
      const text = '我说：“看，他的车很帅。”他很喜欢，他说下周提车。';
      final fixed = MessageSanitizer.fixGenderPronouns(
        text,
        characterGender: '女',
        characterName: '小美',
        userGender: '男',
      );
      expect(fixed, text);
    });

    test('角色男 + 用户男："她"不可能指用户，照常纠错', () {
      const text = '我说她很漂亮，她的裙子也好看。';
      final fixed = MessageSanitizer.fixGenderPronouns(
        text,
        characterGender: '男',
        characterName: '阿强',
        userGender: '男',
      );
      expect(fixed, contains('他很漂亮'));
      expect(fixed, contains('他的裙子'));
    });

    test('用户性别未知时保持旧行为（不擅自改变）', () {
      const text = '我说：她的笑容很美。';
      final fixed = MessageSanitizer.fixGenderPronouns(
        text,
        characterGender: '男',
        characterName: '阿强',
        // userGender 不传
      );
      // 旧行为：全文替换
      expect(fixed, contains('他的笑容'));
    });

    test('用户性别保密时保持旧行为', () {
      const text = '我说：她的笑容很美。';
      final fixed = MessageSanitizer.fixGenderPronouns(
        text,
        characterGender: '男',
        characterName: '阿强',
        userGender: '保密',
      );
      expect(fixed, contains('他的笑容'));
    });
  });

  group('fixGenderPronouns · 基础不变式', () {
    test('空文本/无性别直接返回', () {
      expect(MessageSanitizer.fixGenderPronouns(''), '');
      expect(
        MessageSanitizer.fixGenderPronouns(
          '他很开心',
          characterGender: null,
          characterName: '阿强',
          userGender: '女',
        ),
        '他很开心',
      );
    });

    test('文中没有错代词时原样返回', () {
      const text = '我说：今天天气真好。';
      expect(
        MessageSanitizer.fixGenderPronouns(
          text,
          characterGender: '男',
          characterName: '阿强',
          userGender: '女',
        ),
        text,
      );
    });
  });
}
