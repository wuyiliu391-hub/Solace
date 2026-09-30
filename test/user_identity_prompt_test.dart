import 'package:flutter_test/flutter_test.dart';
import 'package:solace/utils/identity_label.dart';

void main() {
  group('normalizeGenderLabel', () {
    test('标准写法', () {
      expect(normalizeGenderLabel('女'), '女');
      expect(normalizeGenderLabel('男'), '男');
      expect(normalizeGenderLabel('女性'), '女');
      expect(normalizeGenderLabel('男性'), '男');
      expect(normalizeGenderLabel('female'), '女');
      expect(normalizeGenderLabel('male'), '男');
      expect(normalizeGenderLabel('F'), '女');
      expect(normalizeGenderLabel('M'), '男');
    });

    test('未知写法一律 null（不猜）', () {
      expect(normalizeGenderLabel(null), isNull);
      expect(normalizeGenderLabel(''), isNull);
      expect(normalizeGenderLabel('  '), isNull);
      // 保密/其他绝不能硬解释成某种性别——这是"设置X却出现相反"的根源之一
      expect(normalizeGenderLabel('保密'), isNull);
      expect(normalizeGenderLabel('未知'), isNull);
      expect(normalizeGenderLabel('other'), isNull);
    });
  });

  group('thirdPersonPronoun', () {
    test('女→她，男→他，未知→null', () {
      expect(thirdPersonPronoun('女'), '她');
      expect(thirdPersonPronoun('男'), '他');
      expect(thirdPersonPronoun(null), isNull);
      expect(thirdPersonPronoun('保密'), isNull);
    });
  });

  group('buildUserIdentityBlock', () {
    test('代称+性别：绑定本人 + 正确代词', () {
      final block = buildUserIdentityBlock(
        alias: '林晚晚',
        nickname: '阿哲',
        gender: '女',
      );
      expect(block, contains('「林晚晚」'));
      expect(block, contains('就是用户本人'));
      expect(block, contains('「她」'));
      // 代称优先于昵称：昵称不应成为指代主体
      expect(block, isNot(contains('「阿哲」')));
    });

    test('无代称时回退昵称', () {
      final block = buildUserIdentityBlock(
        alias: '  ',
        nickname: '阿哲',
        gender: '男',
      );
      expect(block, contains('「阿哲」'));
      expect(block, contains('「他」'));
    });

    test('代称昵称全空：只剩中性指代，不崩', () {
      final block = buildUserIdentityBlock(gender: '保密');
      expect(block, contains('「你」'));
      expect(block, isNot(contains('她')));
      expect(block, isNot(contains('他')));
    });

    test('无性别时不写性别行', () {
      final block = buildUserIdentityBlock(alias: '主人');
      expect(block, contains('「主人」'));
      expect(block, isNot(contains('性别')));
    });
  });

  group('buildUserAddendumBlock', () {
    test('空输入返回空串（调用方跳过注入）', () {
      expect(buildUserAddendumBlock(null), isEmpty);
      expect(buildUserAddendumBlock(''), isEmpty);
      expect(buildUserAddendumBlock('   '), isEmpty);
    });

    test('非空包装为最高优先级段落', () {
      final block = buildUserAddendumBlock('叫我晚晚');
      expect(block, contains('最高优先级'));
      expect(block, contains('叫我晚晚'));
    });

    test('超长截断到 2000 字', () {
      final long = '字' * 2500;
      final block = buildUserAddendumBlock(long);
      expect(block.length, lessThanOrEqualTo(2000 + 40));
      expect(block, contains('字' * 100));
    });
  });
}
