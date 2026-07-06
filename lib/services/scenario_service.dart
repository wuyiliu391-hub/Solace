import 'package:flutter/material.dart';

class ScenarioTemplate {
  final String id;
  final String name;
  final String icon;
  final String description;

  const ScenarioTemplate({
    required this.id,
    required this.name,
    required this.icon,
    required this.description,
  });

  /// 根据 icon 字段返回对应的 IconData
  IconData get iconData {
    switch (icon) {
      case 'castle': return Icons.castle;
      case 'nightlife': return Icons.nightlife;
      case 'coffee': return Icons.coffee;
      case 'temple_buddhist': return Icons.temple_buddhist;
      case 'auto_awesome': return Icons.auto_awesome;
      default: return Icons.place;
    }
  }

  factory ScenarioTemplate.fromMap(Map<String, dynamic> map) {
    return ScenarioTemplate(
      id: map['id'] as String,
      name: map['name'] as String,
      icon: map['icon'] as String,
      description: map['description'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'description': description,
    };
  }
}

class ScenarioService {
  static final List<ScenarioTemplate> _templates = [
    const ScenarioTemplate(
      id: 'medieval_tavern',
      name: '中世纪酒馆',
      icon: 'castle',
      description:
          '昏暗的木质酒馆内，壁炉在角落噼啪作响，跳动的火光映照在粗糙的石墙上。空气中弥漫着麦酒、烤肉和烟斗的气味。几张厚重的橡木桌旁坐着各色旅人，有的在低声交谈，有的独自饮酒。酒保心不在焉地擦拭着锡制酒杯，偶尔抬头看一眼门口。外面下着大雨，雨点密集地敲打着彩色玻璃窗。',
    ),
    const ScenarioTemplate(
      id: 'cyberpunk_bar',
      name: '赛博朋克酒吧',
      icon: 'nightlife',
      description:
          '霓虹灯管在天花板上闪烁着紫蓝色的光芒，全息投影屏播放着最新的义体广告。低沉的电子音乐从隐藏的音箱中传出，混合着冰块碰撞玻璃杯的声响。吧台是磨砂金属材质，上面摆满了发着荧光的鸡尾酒。角落里一个改造人在调试自己的机械臂，烟雾缭绕中看不清他的表情。',
    ),
    const ScenarioTemplate(
      id: 'modern_cafe',
      name: '现代咖啡厅',
      icon: 'coffee',
      description:
          '明亮温馨的咖啡厅里飘着浓郁的咖啡香。木质桌面上摆着小盆栽，墙上挂着几幅水彩画。咖啡机嗡嗡作响，奶泡的嘶嘶声此起彼伏。落地窗外是繁华的城市街景，阳光透过薄纱窗帘洒进来，在地板上投下斑驳的光影。角落的书架上摆满了旧书，一只橘猫蜷缩在窗台上打盹。',
    ),
    const ScenarioTemplate(
      id: 'ancient_inn',
      name: '古风客栈',
      icon: 'temple_buddhist',
      description:
          '古色古香的客栈大堂，八仙桌旁坐着各路江湖人士。茶香袅袅从紫砂壶中升起，说书先生在台上拍着惊堂木讲着前朝旧事。木质楼梯吱呀作响，偶尔有伙计端着热菜穿过大堂。门外是青石板铺就的长街，远处传来打更人的梆子声。',
    ),
    const ScenarioTemplate(
      id: 'magic_tower',
      name: '魔法塔',
      icon: 'auto_awesome',
      description:
          '神秘的魔法塔顶层，星图在穹顶天花板上缓缓旋转，投射出幽蓝的光芒。墙壁上的书架堆满了古籍和卷轴，空气中漂浮着微光粒子。实验台上摆满了各种形状的玻璃瓶，里面的药水冒着彩色泡泡。一只猫头鹰栖息在高高的烛台上，用琥珀色的眼睛注视着下方。',
    ),
  ];

  static List<ScenarioTemplate> getTemplates() => _templates;

  static ScenarioTemplate? getTemplate(String id) {
    for (final template in _templates) {
      if (template.id == id) return template;
    }
    return null;
  }

  static String buildEnvironmentPrompt(
    String? templateId,
    String? customScenario,
  ) {
    String environmentDescription;

    if (customScenario != null && customScenario.trim().isNotEmpty) {
      environmentDescription = customScenario.trim();
    } else if (templateId != null) {
      final template = getTemplate(templateId);
      if (template != null) {
        environmentDescription = template.description;
      } else {
        return '';
      }
    } else {
      return '';
    }

    return '【当前环境】\n$environmentDescription\n\n请在回复中适当融入环境细节，让对话更有氛围感。你可以描述角色与环境的互动（如拿起酒杯、看向窗外等）。';
  }
}
