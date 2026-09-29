import 'package:flutter_test/flutter_test.dart';
import 'package:solace/services/agent/agent_loop.dart';

/// 测试 AgentLoop.matchBtKeyword — 确定性关键词路由
///
/// 覆盖全部 17 个 BT 操作，验证每种用户输入能正确匹配到对应工具和参数。
void main() {
  group('BT 确定性路由 — matchBtKeyword', () {
    // ═══════════════════════════════════════════════
    // 1. 主题切换
    // ═══════════════════════════════════════════════
    group('主题切换', () {
      test('浅色模式', () {
        final r = AgentLoop.matchBtKeyword('帮我调成浅色模式');
        expect(r, isNotNull);
        expect(r!.toolName, 'setTheme');
        expect(r.args['mode'], 'light');
      });

      test('亮色主题', () {
        final r = AgentLoop.matchBtKeyword('切换到亮色主题');
        expect(r, isNotNull);
        expect(r!.toolName, 'setTheme');
        expect(r.args['mode'], 'light');
      });

      test('白天模式', () {
        final r = AgentLoop.matchBtKeyword('用白天模式');
        expect(r, isNotNull);
        expect(r!.toolName, 'setTheme');
        expect(r.args['mode'], 'light');
      });

      test('深色模式', () {
        final r = AgentLoop.matchBtKeyword('切换深色模式');
        expect(r, isNotNull);
        expect(r!.toolName, 'setTheme');
        expect(r.args['mode'], 'dark');
      });

      test('暗色主题', () {
        final r = AgentLoop.matchBtKeyword('换成暗色主题');
        expect(r, isNotNull);
        expect(r!.toolName, 'setTheme');
        expect(r.args['mode'], 'dark');
      });

      test('夜间模式', () {
        final r = AgentLoop.matchBtKeyword('开启夜间模式');
        expect(r, isNotNull);
        expect(r!.toolName, 'setTheme');
        expect(r.args['mode'], 'dark');
      });

      test('黑色界面', () {
        final r = AgentLoop.matchBtKeyword('我要黑色界面');
        expect(r, isNotNull);
        expect(r!.toolName, 'setTheme');
        expect(r.args['mode'], 'dark');
      });

      test('跟随系统', () {
        final r = AgentLoop.matchBtKeyword('设置跟随系统主题');
        expect(r, isNotNull);
        expect(r!.toolName, 'setTheme');
        expect(r.args['mode'], 'system');
      });

      test('系统主题', () {
        final r = AgentLoop.matchBtKeyword('用系统主题');
        expect(r, isNotNull);
        expect(r!.toolName, 'setTheme');
        expect(r.args['mode'], 'system');
      });

      test('自动主题', () {
        final r = AgentLoop.matchBtKeyword('改成自动主题');
        expect(r, isNotNull);
        expect(r!.toolName, 'setTheme');
        expect(r.args['mode'], 'system');
      });
    });

    // ═══════════════════════════════════════════════
    // 2. 清空聊天记录
    // ═══════════════════════════════════════════════
    group('清空聊天记录', () {
      test('清空聊天记录', () {
        final r = AgentLoop.matchBtKeyword('清空聊天记录');
        expect(r, isNotNull);
        expect(r!.toolName, 'clearChatHistory');
      });

      test('清除对话记录', () {
        final r = AgentLoop.matchBtKeyword('帮我清除对话记录');
        expect(r, isNotNull);
        expect(r!.toolName, 'clearChatHistory');
      });

      test('删掉所有消息记录', () {
        final r = AgentLoop.matchBtKeyword('删掉所有消息记录');
        expect(r, isNotNull);
        expect(r!.toolName, 'clearChatHistory');
      });

      test('全部删除聊天', () {
        final r = AgentLoop.matchBtKeyword('全部删除聊天');
        expect(r, isNotNull);
        expect(r!.toolName, 'clearChatHistory');
      });
    });

    // ═══════════════════════════════════════════════
    // 3. 删除消息
    // ═══════════════════════════════════════════════
    group('删除消息', () {
      test('删掉这条消息', () {
        final r = AgentLoop.matchBtKeyword('删掉这条消息');
        expect(r, isNotNull);
        expect(r!.toolName, 'deleteMessage');
      });

      test('撤回上一条', () {
        final r = AgentLoop.matchBtKeyword('撤回上一条');
        expect(r, isNotNull);
        expect(r!.toolName, 'deleteMessage');
      });

      test('删除那条', () {
        final r = AgentLoop.matchBtKeyword('删除那条');
        expect(r, isNotNull);
        expect(r!.toolName, 'deleteMessage');
      });
    });

    // ═══════════════════════════════════════════════
    // 4. 屏蔽/取消屏蔽
    // ═══════════════════════════════════════════════
    group('屏蔽/取消屏蔽', () {
      test('屏蔽', () {
        final r = AgentLoop.matchBtKeyword('屏蔽他');
        expect(r, isNotNull);
        expect(r!.toolName, 'toggleBlock');
        expect(r.args['block'], true);
      });

      test('拉黑', () {
        final r = AgentLoop.matchBtKeyword('拉黑这个人');
        expect(r, isNotNull);
        expect(r!.toolName, 'toggleBlock');
        expect(r.args['block'], true);
      });

      test('取消屏蔽', () {
        final r = AgentLoop.matchBtKeyword('取消屏蔽');
        expect(r, isNotNull);
        expect(r!.toolName, 'toggleBlock');
        expect(r.args['block'], false);
      });

      test('解除拉黑', () {
        final r = AgentLoop.matchBtKeyword('解除拉黑');
        expect(r, isNotNull);
        expect(r!.toolName, 'toggleBlock');
        expect(r.args['block'], false);
      });

      test('解封', () {
        final r = AgentLoop.matchBtKeyword('解封');
        expect(r, isNotNull);
        expect(r!.toolName, 'toggleBlock');
        expect(r.args['block'], false);
      });
    });

    // ═══════════════════════════════════════════════
    // 5. 隐藏联系人
    // ═══════════════════════════════════════════════
    group('隐藏联系人', () {
      test('隐藏联系人', () {
        final r = AgentLoop.matchBtKeyword('隐藏这个联系人');
        expect(r, isNotNull);
        expect(r!.toolName, 'hideContact');
      });

      test('隐藏好友', () {
        final r = AgentLoop.matchBtKeyword('把她隐藏');
        expect(r, isNotNull);
        expect(r!.toolName, 'hideContact');
      });
    });

    // ═══════════════════════════════════════════════
    // 6. 删除联系人
    // ═══════════════════════════════════════════════
    group('删除联系人', () {
      test('删除联系人', () {
        final r = AgentLoop.matchBtKeyword('删除这个联系人');
        expect(r, isNotNull);
        expect(r!.toolName, 'deleteContact');
      });

      test('移除好友', () {
        final r = AgentLoop.matchBtKeyword('移除好友');
        expect(r, isNotNull);
        expect(r!.toolName, 'deleteContact');
      });
    });

    // ═══════════════════════════════════════════════
    // 7. 修改备注
    // ═══════════════════════════════════════════════
    group('修改备注', () {
      test('改成XXX', () {
        final r = AgentLoop.matchBtKeyword('改成备注小可爱');
        expect(r, isNotNull);
        expect(r!.toolName, 'updateContactRemark');
        expect(r.args['name'], '小可爱');
      });

      test('设置备注为XXX', () {
        final r = AgentLoop.matchBtKeyword('设置备注为宝贝');
        expect(r, isNotNull);
        expect(r!.toolName, 'updateContactRemark');
        expect(r.args['name'], '宝贝');
      });

      test('修改备注名XXX', () {
        final r = AgentLoop.matchBtKeyword('修改备注名老婆');
        expect(r, isNotNull);
        expect(r!.toolName, 'updateContactRemark');
        expect(r.args['name'], '老婆');
      });
    });

    // ═══════════════════════════════════════════════
    // 8. 在线/离线状态
    // ═══════════════════════════════════════════════
    group('在线/离线状态', () {
      test('上线', () {
        final r = AgentLoop.matchBtKeyword('让她上线');
        expect(r, isNotNull);
        expect(r!.toolName, 'setOnlineStatus');
        expect(r.args['online'], true);
      });

      test('设为在线', () {
        final r = AgentLoop.matchBtKeyword('设为在线');
        expect(r, isNotNull);
        expect(r!.toolName, 'setOnlineStatus');
        expect(r.args['online'], true);
      });

      test('下线', () {
        final r = AgentLoop.matchBtKeyword('让他下线');
        expect(r, isNotNull);
        expect(r!.toolName, 'setOnlineStatus');
        expect(r.args['online'], false);
      });

      test('设为离线', () {
        final r = AgentLoop.matchBtKeyword('设置离线');
        expect(r, isNotNull);
        expect(r!.toolName, 'setOnlineStatus');
        expect(r.args['online'], false);
      });
    });

    // ═══════════════════════════════════════════════
    // 9. 清空角色记忆
    // ═══════════════════════════════════════════════
    group('清空角色记忆', () {
      test('清空记忆', () {
        final r = AgentLoop.matchBtKeyword('清空她的记忆');
        expect(r, isNotNull);
        expect(r!.toolName, 'clearCharacterMemory');
      });

      test('清除全部记忆', () {
        final r = AgentLoop.matchBtKeyword('清除全部记忆');
        expect(r, isNotNull);
        expect(r!.toolName, 'clearCharacterMemory');
      });

      test('擦除角色记忆', () {
        final r = AgentLoop.matchBtKeyword('擦除角色记忆');
        expect(r, isNotNull);
        expect(r!.toolName, 'clearCharacterMemory');
      });
    });

    // ═══════════════════════════════════════════════
    // 10. 重置角色人设
    // ═══════════════════════════════════════════════
    group('重置角色人设', () {
      test('重置人设', () {
        final r = AgentLoop.matchBtKeyword('重置人设');
        expect(r, isNotNull);
        expect(r!.toolName, 'resetCharacterPersona');
      });

      test('恢复初始角色', () {
        final r = AgentLoop.matchBtKeyword('恢复初始角色');
        expect(r, isNotNull);
        expect(r!.toolName, 'resetCharacterPersona');
      });

      test('还原默认', () {
        final r = AgentLoop.matchBtKeyword('还原默认');
        expect(r, isNotNull);
        expect(r!.toolName, 'resetCharacterPersona');
      });
    });

    // ═══════════════════════════════════════════════
    // 11. 发朋友圈/动态
    // ═══════════════════════════════════════════════
    group('发朋友圈/动态', () {
      test('发朋友圈', () {
        final r = AgentLoop.matchBtKeyword('发个朋友圈');
        expect(r, isNotNull);
        expect(r!.toolName, 'postMoment');
      });

      test('发动态', () {
        final r = AgentLoop.matchBtKeyword('发动态');
        expect(r, isNotNull);
        expect(r!.toolName, 'postMoment');
      });

      test('发朋友圈带内容', () {
        final r = AgentLoop.matchBtKeyword('发朋友圈今天天气真好');
        expect(r, isNotNull);
        expect(r!.toolName, 'postMoment');
        expect(r.args['content'], contains('天气真好'));
      });

      test('帮我发说说', () {
        final r = AgentLoop.matchBtKeyword('帮我发说说：开心');
        expect(r, isNotNull);
        expect(r!.toolName, 'postMoment');
      });
    });

    // ═══════════════════════════════════════════════
    // 12. 删除动态
    // ═══════════════════════════════════════════════
    group('删除动态', () {
      test('删除动态', () {
        final r = AgentLoop.matchBtKeyword('删除那条动态');
        expect(r, isNotNull);
        expect(r!.toolName, 'deleteMoment');
      });

      test('删掉朋友圈', () {
        final r = AgentLoop.matchBtKeyword('删掉朋友圈');
        expect(r, isNotNull);
        expect(r!.toolName, 'deleteMoment');
      });
    });

    // ═══════════════════════════════════════════════
    // 13. 发信件
    // ═══════════════════════════════════════════════
    group('发信件', () {
      test('写信', () {
        final r = AgentLoop.matchBtKeyword('写信我想你了');
        expect(r, isNotNull);
        expect(r!.toolName, 'sendLetter');
        expect(r.args['content'], contains('想你了'));
      });

      test('发信件', () {
        final r = AgentLoop.matchBtKeyword('发一封');
        expect(r, isNotNull);
        expect(r!.toolName, 'sendLetter');
      });
    });

    // ═══════════════════════════════════════════════
    // 14. 修改昵称
    // ═══════════════════════════════════════════════
    group('修改昵称', () {
      test('改昵称', () {
        final r = AgentLoop.matchBtKeyword('改昵称小明');
        expect(r, isNotNull);
        expect(r!.toolName, 'updateProfileNickname');
        expect(r.args['nickname'], '小明');
      });

      test('设置我的名字为', () {
        final r = AgentLoop.matchBtKeyword('设置我的名字为阿强');
        expect(r, isNotNull);
        expect(r!.toolName, 'updateProfileNickname');
        expect(r.args['nickname'], '阿强');
      });

      test('改成名字XXX', () {
        final r = AgentLoop.matchBtKeyword('改成名字大帅哥');
        expect(r, isNotNull);
        expect(r!.toolName, 'updateProfileNickname');
        expect(r.args['nickname'], '大帅哥');
      });
    });

    // ═══════════════════════════════════════════════
    // 15. 写日记
    // ═══════════════════════════════════════════════
    group('写日记', () {
      test('写日记', () {
        final r = AgentLoop.matchBtKeyword('写日记');
        expect(r, isNotNull);
        expect(r!.toolName, 'createDiary');
      });

      test('记日记', () {
        final r = AgentLoop.matchBtKeyword('记日记今天很开心');
        expect(r, isNotNull);
        expect(r!.toolName, 'createDiary');
      });

      test('创建日记', () {
        final r = AgentLoop.matchBtKeyword('创建日记');
        expect(r, isNotNull);
        expect(r!.toolName, 'createDiary');
      });
    });

    // ═══════════════════════════════════════════════
    // 16. 插入系统消息
    // ═══════════════════════════════════════════════
    group('插入系统消息', () {
      test('插入系统消息', () {
        final r = AgentLoop.matchBtKeyword('插入系统消息测试');
        expect(r, isNotNull);
        expect(r!.toolName, 'insertSystemMessage');
      });
    });

    // ═══════════════════════════════════════════════
    // 17. 转幸运转盘
    // ═══════════════════════════════════════════════
    group('转幸运转盘', () {
      test('转盘', () {
        final r = AgentLoop.matchBtKeyword('转盘');
        expect(r, isNotNull);
        expect(r!.toolName, 'triggerLuckyWheel');
      });

      test('抽奖', () {
        final r = AgentLoop.matchBtKeyword('我要抽奖');
        expect(r, isNotNull);
        expect(r!.toolName, 'triggerLuckyWheel');
      });

      test('幸运转盘', () {
        final r = AgentLoop.matchBtKeyword('幸运转盘');
        expect(r, isNotNull);
        expect(r!.toolName, 'triggerLuckyWheel');
      });

      test('转一下', () {
        final r = AgentLoop.matchBtKeyword('转一下');
        expect(r, isNotNull);
        expect(r!.toolName, 'triggerLuckyWheel');
      });
    });

    // ═══════════════════════════════════════════════
    // 不匹配的消息 → 返回 null
    // ═══════════════════════════════════════════════
    group('普通聊天不匹配', () {
      test('你好', () {
        expect(AgentLoop.matchBtKeyword('你好'), isNull);
      });

      test('今天天气怎么样', () {
        expect(AgentLoop.matchBtKeyword('今天天气怎么样'), isNull);
      });

      test('我喜欢你', () {
        expect(AgentLoop.matchBtKeyword('我喜欢你'), isNull);
      });

      test('讲个笑话', () {
        expect(AgentLoop.matchBtKeyword('讲个笑话'), isNull);
      });

      test('空消息', () {
        expect(AgentLoop.matchBtKeyword(''), isNull);
      });

      test('纯空格', () {
        expect(AgentLoop.matchBtKeyword('   '), isNull);
      });
    });
  });
}