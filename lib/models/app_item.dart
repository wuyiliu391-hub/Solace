import 'dart:ui';

class AppItem {
  final String id;
  final String name;
  final String iconAsset;
  final String? route;
  final AppItemType type;
  final List<AppItem>? children;
  final int accentColor;
  final bool isDock;

  const AppItem({
    required this.id,
    required this.name,
    required this.iconAsset,
    this.route,
    this.type = AppItemType.app,
    this.children,
    this.accentColor = 0xFF007AFF,
    this.isDock = false,
  });

  AppItem copyWith({
    String? id,
    String? name,
    String? iconAsset,
    String? route,
    AppItemType? type,
    List<AppItem>? children,
    int? accentColor,
    bool? isDock,
  }) {
    return AppItem(
      id: id ?? this.id,
      name: name ?? this.name,
      iconAsset: iconAsset ?? this.iconAsset,
      route: route ?? this.route,
      type: type ?? this.type,
      children: children ?? this.children,
      accentColor: accentColor ?? this.accentColor,
      isDock: isDock ?? this.isDock,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'iconAsset': iconAsset,
        'route': route,
        'type': type.index,
        'accentColor': accentColor,
        'isDock': isDock,
        'children': children?.map((c) => c.toJson()).toList(),
      };

  factory AppItem.fromJson(Map<String, dynamic> json) => AppItem(
        id: json['id'] as String,
        name: json['name'] as String,
        iconAsset: json['iconAsset'] as String,
        route: json['route'] as String?,
        type: AppItemType.values[json['type'] as int? ?? 0],
        accentColor: json['accentColor'] as int? ?? 0xFF007AFF,
        isDock: json['isDock'] as bool? ?? false,
        children: (json['children'] as List<dynamic>?)
            ?.map((c) => AppItem.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

enum AppItemType { app, folder, spacer }

class HomeLayout {
  final List<List<AppItem>> pages;
  final List<AppItem> dock;
  final String? wallpaperPath;
  final String gridPreset; // "4x5", "5x5", "4x6", "5x6"

  const HomeLayout({
    required this.pages,
    required this.dock,
    this.wallpaperPath,
    this.gridPreset = '4x5',
  });

  HomeLayout copyWith({
    List<List<AppItem>>? pages,
    List<AppItem>? dock,
    String? wallpaperPath,
    String? gridPreset,
  }) {
    return HomeLayout(
      pages: pages ?? this.pages,
      dock: dock ?? this.dock,
      wallpaperPath: wallpaperPath ?? this.wallpaperPath,
      gridPreset: gridPreset ?? this.gridPreset,
    );
  }

  /// 所有图标（用于序列化）
  Iterable<AppItem> get allItems sync* {
    for (final page in pages) {
      yield* page;
    }
    yield* dock;
  }

  Map<String, dynamic> toJson() => {
        'pages': pages
            .map((p) => p.map((i) => i.toJson()).toList())
            .toList(),
        'dock': dock.map((i) => i.toJson()).toList(),
        'wallpaperPath': wallpaperPath,
        'gridPreset': gridPreset,
      };

  factory HomeLayout.fromJson(Map<String, dynamic> json) => HomeLayout(
        pages: (json['pages'] as List<dynamic>)
            .map((p) => (p as List<dynamic>)
                .map((i) => AppItem.fromJson(i as Map<String, dynamic>))
                .toList())
            .toList(),
        dock: (json['dock'] as List<dynamic>)
            .map((i) => AppItem.fromJson(i as Map<String, dynamic>))
            .toList(),
        wallpaperPath: json['wallpaperPath'] as String?,
        gridPreset: json['gridPreset'] as String? ?? '4x5',
      );
}
