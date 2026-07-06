import 'dart:math';
import '../models/location_record.dart';

class AILocationEngine {
  static final Random _rng = Random();

  static const double _defaultLat = 39.9042;
  static const double _defaultLng = 116.4074;

  static double _baseLat = _defaultLat;
  static double _baseLng = _defaultLng;

  static void setBaseLocation(double lat, double lng) {
    _baseLat = lat;
    _baseLng = lng;
  }

  static final Map<String, List<Map<String, String>>> _poiDatabase = {
    'office': [
      {'name': '星辰科技大厦', 'address': '科技园路88号'},
      {'name': '创新产业园A座', 'address': '高新区创业大道126号'},
      {'name': '银河商务中心', 'address': '金融街99号'},
      {'name': '未来科技园', 'address': '数字经济产业园3号楼'},
      {'name': '云峰写字楼', 'address': '中山路256号'},
    ],
    'cafe': [
      {'name': '星巴克', 'address': '万达广场1楼'},
      {'name': '瑞幸咖啡', 'address': '写字楼B1层'},
      {'name': 'Manner Coffee', 'address': '创意园区内'},
      {'name': '库迪咖啡', 'address': '步行街入口'},
      {'name': '%Arabica', 'address': '太古里'},
    ],
    'restaurant': [
      {'name': '海底捞火锅', 'address': '银泰百货6楼'},
      {'name': '麦当劳', 'address': '地铁站出口'},
      {'name': '沙县小吃', 'address': '小区门口'},
      {'name': '兰州拉面', 'address': '建设路12号'},
      {'name': '外婆家', 'address': '大悦城4楼'},
      {'name': '西贝莜面村', 'address': '万象城3楼'},
      {'name': '必胜客', 'address': '步行街中心'},
      {'name': '喜茶', 'address': '购物中心1楼'},
    ],
    'mall': [
      {'name': '万达广场', 'address': '城市中心'},
      {'name': '银泰百货', 'address': '解放路168号'},
      {'name': '大悦城', 'address': '滨江大道'},
      {'name': '万象城', 'address': '金融中心旁'},
      {'name': '龙湖天街', 'address': '新城开发区'},
    ],
    'park': [
      {'name': '人民公园', 'address': '市中心'},
      {'name': '中央湿地公园', 'address': '滨河路'},
      {'name': '城市森林公园', 'address': '北环路'},
      {'name': '樱花公园', 'address': '大学城附近'},
      {'name': '滨江公园', 'address': '江边'},
    ],
    'cinema': [
      {'name': '万达影城', 'address': '万达广场4楼'},
      {'name': 'CGV影城', 'address': '大悦城5楼'},
      {'name': '金逸影城', 'address': '步行街'},
    ],
    'gym': [
      {'name': '超级猩猩', 'address': '写字楼B1'},
      {'name': '乐刻运动', 'address': '社区店'},
      {'name': '威尔仕健身', 'address': '银泰5楼'},
    ],
    'bookstore': [
      {'name': '西西弗书店', 'address': '万象城2楼'},
      {'name': '方所', 'address': '太古里'},
      {'name': '新华书店', 'address': '文化路'},
      {'name': '言几又', 'address': '大悦城'},
    ],
    'supermarket': [
      {'name': '盒马鲜生', 'address': '购物中心B1'},
      {'name': '永辉超市', 'address': '社区商业中心'},
      {'name': '大润发', 'address': '城西'},
    ],
    'hospital': [
      {'name': '市第一人民医院', 'address': '健康路1号'},
      {'name': '社区卫生服务中心', 'address': '幸福路'},
    ],
    'bank': [
      {'name': '中国工商银行', 'address': '金融街'},
      {'name': '招商银行', 'address': '科技园'},
    ],
    'hotel': [
      {'name': '全季酒店', 'address': '火车站附近'},
      {'name': '如家酒店', 'address': '商业步行街'},
      {'name': '汉庭酒店', 'address': '市中心'},
      {'name': '亚朵酒店', 'address': '科技园'},
      {'name': '桔子水晶酒店', 'address': '滨江路'},
    ],
    'ktv': [
      {'name': '好乐迪KTV', 'address': '步行街3楼'},
      {'name': '纯K', 'address': '万达广场'},
    ],
    'home': [
      {'name': '阳光花园小区', 'address': '幸福路66号'},
      {'name': '翠湖天地', 'address': '湖滨路'},
      {'name': '绿城百合公寓', 'address': '学院路'},
      {'name': '万科城市花园', 'address': '新城路'},
    ],
    'governMent': [
      {'name': '市政府', 'address': '人民大道'},
      {'name': '市民服务中心', 'address': '行政路'},
    ],
    'transit': [
      {'name': '高铁站', 'address': '站前路'},
      {'name': '地铁站-人民广场', 'address': '地下'},
      {'name': '长途汽车站', 'address': '交通路'},
    ],
  };

  static final List<Map<String, dynamic>> _weekdaySchedule = [
    {'hour': 7, 'minute': 30, 'type': 'home', 'activity': '起床准备', 'stay': 60},
    {'hour': 8, 'minute': 30, 'type': 'transit', 'activity': '通勤中', 'stay': 20},
    {'hour': 9, 'minute': 0, 'type': 'office', 'activity': '上班', 'stay': 180},
    {'hour': 12, 'minute': 0, 'type': 'restaurant', 'activity': '吃午饭', 'stay': 60},
    {'hour': 13, 'minute': 0, 'type': 'cafe', 'activity': '喝杯咖啡', 'stay': 20},
    {'hour': 13, 'minute': 30, 'type': 'office', 'activity': '继续上班', 'stay': 270},
    {'hour': 18, 'minute': 0, 'type': 'gym', 'activity': '健身', 'stay': 90, 'chance': 0.4},
    {'hour': 18, 'minute': 0, 'type': 'mall', 'activity': '逛商场', 'stay': 90, 'chance': 0.2},
    {'hour': 18, 'minute': 0, 'type': 'bookstore', 'activity': '看书', 'stay': 60, 'chance': 0.1},
    {'hour': 18, 'minute': 0, 'type': 'home', 'activity': '回家', 'stay': 30, 'chance': 0.3},
    {'hour': 19, 'minute': 30, 'type': 'restaurant', 'activity': '吃晚饭', 'stay': 60},
    {'hour': 20, 'minute': 30, 'type': 'home', 'activity': '到家了', 'stay': 999},
  ];

  static final List<Map<String, dynamic>> _weekendSchedule = [
    {'hour': 9, 'minute': 30, 'type': 'home', 'activity': '睡懒觉起来了', 'stay': 60},
    {'hour': 10, 'minute': 30, 'type': 'cafe', 'activity': '喝杯咖啡', 'stay': 60, 'chance': 0.5},
    {'hour': 10, 'minute': 30, 'type': 'home', 'activity': '在家休息', 'stay': 120, 'chance': 0.5},
    {'hour': 12, 'minute': 0, 'type': 'restaurant', 'activity': '吃午饭', 'stay': 60},
    {'hour': 13, 'minute': 30, 'type': 'mall', 'activity': '逛街', 'stay': 120, 'chance': 0.4},
    {'hour': 13, 'minute': 30, 'type': 'park', 'activity': '散步', 'stay': 90, 'chance': 0.3},
    {'hour': 13, 'minute': 30, 'type': 'cinema', 'activity': '看电影', 'stay': 120, 'chance': 0.2},
    {'hour': 13, 'minute': 30, 'type': 'home', 'activity': '在家', 'stay': 180, 'chance': 0.1},
    {'hour': 16, 'minute': 0, 'type': 'bookstore', 'activity': '逛书店', 'stay': 60, 'chance': 0.3},
    {'hour': 16, 'minute': 0, 'type': 'supermarket', 'activity': '买菜', 'stay': 40, 'chance': 0.3},
    {'hour': 16, 'minute': 0, 'type': 'park', 'activity': '在公园', 'stay': 60, 'chance': 0.2},
    {'hour': 17, 'minute': 30, 'type': 'restaurant', 'activity': '吃晚饭', 'stay': 60},
    {'hour': 19, 'minute': 0, 'type': 'home', 'activity': '回家了', 'stay': 999},
  ];

  static final List<Map<String, dynamic>> _specialEvents = [
    {'type': 'hotel', 'activity': '在酒店', 'chance': 0.03, 'hours': [14, 15, 16, 20, 21, 22]},
    {'type': 'ktv', 'activity': '唱K', 'chance': 0.05, 'hours': [19, 20, 21, 22, 23]},
    {'type': 'hospital', 'activity': '去医院', 'chance': 0.02, 'hours': [9, 10, 11, 14, 15]},
    {'type': 'bank', 'activity': '去银行', 'chance': 0.04, 'hours': [9, 10, 11, 14, 15, 16]},
  ];

  static Map<String, String> _getRandomPOI(String type) {
    final pois = _poiDatabase[type];
    if (pois == null || pois.isEmpty) {
      return {'name': '未知地点', 'address': ''};
    }
    return pois[_rng.nextInt(pois.length)];
  }

  static double _randomOffset(double base, double range) {
    return base + (_rng.nextDouble() * 2 - 1) * range;
  }

  static (double lat, double lng) _generateCoordinates(String type) {
    double range;
    switch (type) {
      case 'office':
        range = 0.02;
        break;
      case 'home':
        range = 0.005;
        break;
      case 'transit':
        range = 0.015;
        break;
      default:
        range = 0.03;
        break;
    }
    return (_randomOffset(_baseLat, range), _randomOffset(_baseLng, range));
  }

  static String _getEmotion(String activity) {
    final emotions = {
      '起床准备': '困倦',
      '通勤中': '平淡',
      '上班': '专注',
      '吃午饭': '满足',
      '喝杯咖啡': '惬意',
      '继续上班': '专注',
      '健身': '活力',
      '逛商场': '开心',
      '看书': '安静',
      '回家': '放松',
      '吃晚饭': '满足',
      '到家了': '温馨',
      '睡懒觉起来了': '慵懒',
      '逛街': '兴奋',
      '散步': '悠闲',
      '看电影': '投入',
      '在家': '放松',
      '在家休息': '慵懒',
      '逛书店': '文艺',
      '买菜': '日常',
      '在公园': '惬意',
      '在酒店': '紧张',
      '唱K': '嗨',
      '去医院': '不安',
      '去银行': '平淡',
    };
    return emotions[activity] ?? '平淡';
  }

  static LocationRecord generateCurrentLocation(String aiId) {
    final now = DateTime.now();
    final isWeekend = now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;

    for (final event in _specialEvents) {
      final hours = event['hours'] as List<int>;
      if (hours.contains(now.hour) && _rng.nextDouble() < (event['chance'] as double)) {
        final type = event['type'] as String;
        final poi = _getRandomPOI(type);
        final coords = _generateCoordinates(type);
        return LocationRecord(
          id: '${aiId}_${now.millisecondsSinceEpoch}',
          ownerId: aiId,
          latitude: coords.$1,
          longitude: coords.$2,
          placeName: poi['name'],
          placeType: type,
          address: poi['address'],
          timestamp: now,
          isUser: false,
          activity: event['activity'] as String,
          emotion: _getEmotion(event['activity'] as String),
        );
      }
    }

    final schedule = isWeekend ? _weekendSchedule : _weekdaySchedule;
    Map<String, dynamic>? currentSlot;
    for (final slot in schedule) {
      final slotTime = DateTime(now.year, now.month, now.day, slot['hour'] as int, slot['minute'] as int);
      if (now.isAfter(slotTime) || now.isAtSameMomentAs(slotTime)) {
        if (slot.containsKey('chance')) {
          if (_rng.nextDouble() < (slot['chance'] as double)) {
            currentSlot = slot;
          }
        } else {
          currentSlot = slot;
        }
      }
    }

    currentSlot ??= schedule.last;
    final type = currentSlot['type'] as String;
    final poi = _getRandomPOI(type);
    final coords = _generateCoordinates(type);

    return LocationRecord(
      id: '${aiId}_${now.millisecondsSinceEpoch}',
      ownerId: aiId,
      latitude: coords.$1,
      longitude: coords.$2,
      placeName: poi['name'],
      placeType: type,
      address: poi['address'],
      timestamp: now,
      isUser: false,
      activity: currentSlot['activity'] as String,
      emotion: _getEmotion(currentSlot['activity'] as String),
    );
  }

  static List<LocationRecord> generateTodayTrajectory(String aiId) {
    final now = DateTime.now();
    final isWeekend = now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
    final schedule = isWeekend ? _weekendSchedule : _weekdaySchedule;
    final List<LocationRecord> trajectory = [];
    String? trajectoryId;
    int seq = 0;

    for (final slot in schedule) {
      final slotTime = DateTime(now.year, now.month, now.day, slot['hour'] as int, slot['minute'] as int);
      if (slotTime.isAfter(now)) break;

      if (slot.containsKey('chance') && _rng.nextDouble() >= (slot['chance'] as double)) {
        continue;
      }

      trajectoryId ??= 'traj_${aiId}_${now.year}${now.month}${now.day}';
      final type = slot['type'] as String;
      final poi = _getRandomPOI(type);
      final coords = _generateCoordinates(type);

      trajectory.add(LocationRecord(
        id: '${aiId}_${slotTime.millisecondsSinceEpoch}',
        ownerId: aiId,
        latitude: coords.$1,
        longitude: coords.$2,
        placeName: poi['name'],
        placeType: type,
        address: poi['address'],
        timestamp: slotTime,
        isUser: false,
        trajectoryId: trajectoryId,
        sequenceIndex: seq++,
        activity: slot['activity'] as String,
        emotion: _getEmotion(slot['activity'] as String),
      ));
    }

    return trajectory;
  }

  static LocationRecord generateManualLocation(String aiId, String placeName, String placeType, String activity) {
    final poi = _poiDatabase[placeType]?.firstWhere(
      (p) => p['name'] == placeName,
      orElse: () => {'name': placeName, 'address': ''},
    ) ?? {'name': placeName, 'address': ''};
    final coords = _generateCoordinates(placeType);
    return LocationRecord(
      id: '${aiId}_${DateTime.now().millisecondsSinceEpoch}',
      ownerId: aiId,
      latitude: coords.$1,
      longitude: coords.$2,
      placeName: poi['name'],
      placeType: placeType,
      address: poi['address'],
      timestamp: DateTime.now(),
      isUser: false,
      activity: activity,
      emotion: _getEmotion(activity),
    );
  }

  static List<Map<String, String>> getAllPOIs() {
    final List<Map<String, String>> all = [];
    _poiDatabase.forEach((type, pois) {
      for (final poi in pois) {
        all.add({...poi, 'type': type});
      }
    });
    return all;
  }

  static String getPlaceTypeLabel(String type) {
    const labels = {
      'office': '公司',
      'cafe': '咖啡厅',
      'restaurant': '餐厅',
      'mall': '商场',
      'park': '公园',
      'cinema': '电影院',
      'gym': '健身房',
      'bookstore': '书店',
      'supermarket': '超市',
      'hospital': '医院',
      'bank': '银行',
      'hotel': '酒店',
      'ktv': 'KTV',
      'home': '家',
      'governMent': '政府',
      'transit': '交通',
    };
    return labels[type] ?? '地点';
  }
}
