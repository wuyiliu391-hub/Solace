import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/map/map_bloc.dart';
import '../../models/location_record.dart';
import '../../services/ai_location_engine.dart';

class MapScreen extends StatefulWidget {
  final String aiId;
  final String aiName;
  final String? aiAvatar;
  const MapScreen({super.key, required this.aiId, required this.aiName, this.aiAvatar});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  late final MapController _mapController;
  late final MapBloc _mapBloc;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    final user = (context.read<AuthBloc>().state as AuthAuthenticated).user;
    _mapBloc = MapBloc()
      ..add(MapInitialize(
        userId: user.id,
        aiId: widget.aiId,
        baseLatitude: 39.9042,
        baseLongitude: 116.4074,
      ))
      ..add(MapStartUserTracking(user.id));
  }

  @override
  void dispose() {
    _mapBloc.add(const MapStopUserTracking());
    _mapBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _mapBloc,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        body: BlocConsumer<MapBloc, MapState>(
          listener: (context, state) {
            if (state is MapLoaded) {
              Future.delayed(const Duration(milliseconds: 300), () {
                try {
                  _mapController.move(
                    LatLng(state.aiLocation.latitude, state.aiLocation.longitude),
                    14,
                  );
                } catch (_) {}
              });
            }
          },
          builder: (context, state) {
            if (state is MapLoaded) {
              return Stack(
                children: [
                  _buildMap(state),
                  _buildTopBar(context, state),
                  _buildBottomInfo(context, state),
                ],
              );
            }
            if (state is MapError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text(state.message, style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        final user = (context.read<AuthBloc>().state as AuthAuthenticated).user;
                        _mapBloc.add(MapInitialize(
                          userId: user.id,
                          aiId: widget.aiId,
                          baseLatitude: 39.9042,
                          baseLongitude: 116.4074,
                        ));
                      },
                      child: const Text('重试'),
                    ),
                  ],
                ),
              );
            }
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    '正在加载地图...',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMap(MapLoaded state) {
    final markers = <Marker>[];
    final polylines = <Polyline>[];

    if (state.showAITrajectory && state.aiTrajectory.length > 1) {
      final points = state.aiTrajectory
          .map((r) => LatLng(r.latitude, r.longitude))
          .toList();
      polylines.add(Polyline(
        points: points,
        color: Colors.redAccent.withOpacity(0.7),
        strokeWidth: 3,
      ));
    }

    if (state.showUserTrajectory && state.userTrajectory.length > 1) {
      final points = state.userTrajectory
          .map((r) => LatLng(r.latitude, r.longitude))
          .toList();
      polylines.add(Polyline(
        points: points,
        color: Colors.blue.withOpacity(0.7),
        strokeWidth: 3,
      ));
    }

    markers.add(Marker(
      point: LatLng(state.aiLocation.latitude, state.aiLocation.longitude),
      width: 60,
      height: 70,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              state.aiLocation.placeName ?? '未知',
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.redAccent,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: const Icon(Icons.favorite, color: Colors.white, size: 18),
          ),
        ],
      ),
    ));

    if (state.userLocation != null) {
      markers.add(Marker(
        point: LatLng(state.userLocation!.latitude, state.userLocation!.longitude),
        width: 60,
        height: 70,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '我',
                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 18),
            ),
          ],
        ),
      ));
    }

    for (final point in state.aiTrajectory) {
      if (point == state.aiLocation) continue;
      markers.add(Marker(
        point: LatLng(point.latitude, point.longitude),
        width: 20,
        height: 20,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.redAccent.withOpacity(0.4),
            border: Border.all(color: Colors.redAccent.withOpacity(0.6), width: 1),
          ),
        ),
      ));
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: LatLng(state.aiLocation.latitude, state.aiLocation.longitude),
        initialZoom: 14,
        minZoom: 3,
        maxZoom: 18,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
          subdomains: const ['1', '2', '3', '4'],
          userAgentPackageName: 'com.solace.app',
          maxZoom: 18,
          minZoom: 3,
        ),
        PolylineLayer(polylines: polylines),
        MarkerLayer(markers: markers),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context, MapLoaded state) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: Row(
        children: [
          _circleBtn(Icons.arrow_back, () => Navigator.pop(context)),
          const Spacer(),
          _chipBtn(
            'AI轨迹',
            state.showAITrajectory ? Colors.redAccent : Colors.grey,
            () => context.read<MapBloc>().add(const MapToggleTrajectory(true)),
          ),
          const SizedBox(width: 6),
          _chipBtn(
            '我的轨迹',
            state.showUserTrajectory ? Colors.blue : Colors.grey,
            () => context.read<MapBloc>().add(const MapToggleTrajectory(false)),
          ),
          const SizedBox(width: 6),
          _circleBtn(Icons.my_location, () {
            final user = (context.read<AuthBloc>().state as AuthAuthenticated).user;
            context.read<MapBloc>().add(MapUpdateUserLocation(user.id));
          }),
          const SizedBox(width: 6),
          _circleBtn(Icons.refresh, () {
            context.read<MapBloc>().add(MapRefreshAILocation(widget.aiId));
          }),
        ],
      ),
    );
  }

  Widget _buildBottomInfo(BuildContext context, MapLoaded state) {
    final ai = state.aiLocation;
    final dist = state.userLocation != null ? _calcDistance(
      state.userLocation!.latitude, state.userLocation!.longitude,
      ai.latitude, ai.longitude,
    ) : null;

    return Positioned(
      bottom: 16,
      left: 12,
      right: 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => _showLocationDetail(context, state),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 2))],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.redAccent.withOpacity(0.1),
                    ),
                    child: const Icon(Icons.favorite, color: Colors.redAccent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.aiName} ${ai.activity != null ? "· ${ai.activity}" : ""}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${ai.placeName ?? "未知位置"}${ai.address != null ? " · ${ai.address}" : ""}',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (dist != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          dist < 1 ? '${(dist * 1000).toInt()}m' : '${dist.toStringAsFixed(1)}km',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.redAccent),
                        ),
                        Text(
                          '距离',
                          style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  context,
                  Icons.edit_location,
                  '设置AI位置',
                  Colors.orange,
                  () => _showSetAILocationSheet(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _actionBtn(
                  context,
                  Icons.add_location_alt,
                  '发布我的位置',
                  Colors.blue,
                  () => _publishMyLocation(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6)],
        ),
        child: Icon(icon, size: 20),
      ),
    );
  }

  Widget _chipBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _actionBtn(BuildContext ctx, IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  double _calcDistance(double lat1, double lng1, double lat2, double lng2) {
    const earth = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a = (dLat / 2) * (dLat / 2) + _deg2rad(lat1) * (_deg2rad(lat2)) * (dLng / 2) * (dLng / 2);
    final c = 2 * _atan2sqrt(a);
    return earth * c;
  }

  double _deg2rad(double deg) => deg * 3.141592653589793 / 180.0;
  double _atan2sqrt(double a) => 2 * (a < 0 ? 0 : a > 1 ? 0 : _sqrt(a < 0.0001 ? a : a));
  double _sqrt(double x) {
    double guess = x / 2;
    for (int i = 0; i < 10; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }

  void _showLocationDetail(BuildContext context, MapLoaded state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LocationDetailSheet(
        aiName: widget.aiName,
        location: state.aiLocation,
        trajectory: state.aiTrajectory,
      ),
    );
  }

  void _showSetAILocationSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SetAILocationSheet(
        onSelected: (name, type, activity) {
          context.read<MapBloc>().add(MapSetAILocationManually(
            placeName: name, placeType: type, activity: activity,
          ));
        },
      ),
    );
  }

  void _publishMyLocation(BuildContext context) async {
    final user = (context.read<AuthBloc>().state as AuthAuthenticated).user;
    context.read<MapBloc>().add(MapUpdateUserLocation(user.id));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已更新你的位置'), duration: Duration(seconds: 2)),
      );
    }
  }
}

class _LocationDetailSheet extends StatelessWidget {
  final String aiName;
  final LocationRecord location;
  final List<LocationRecord> trajectory;
  const _LocationDetailSheet({required this.aiName, required this.location, required this.trajectory});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.5,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.redAccent.withOpacity(0.1),
                  child: const Icon(Icons.favorite, color: Colors.redAccent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(aiName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                      Text(
                        '当前 · ${location.activity ?? location.placeName ?? "未知"}',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (location.emotion != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(location.emotion!, style: const TextStyle(color: Colors.orange, fontSize: 12)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.place, size: 16, color: Colors.redAccent),
                const SizedBox(width: 6),
                Expanded(child: Text(location.placeName ?? '未知', style: const TextStyle(fontSize: 14))),
                Text(
                  AILocationEngine.getPlaceTypeLabel(location.placeType ?? ''),
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (location.address != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.home_work_outlined, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(location.address!, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.timeline, size: 16),
                const SizedBox(width: 6),
                Text('今日轨迹 (${trajectory.length}个地点)', style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: trajectory.length,
              itemBuilder: (_, i) {
                final r = trajectory[i];
                final time = '${r.timestamp.hour.toString().padLeft(2, '0')}:${r.timestamp.minute.toString().padLeft(2, '0')}';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == trajectory.length - 1 ? Colors.redAccent : Colors.grey[400],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(time, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${r.placeName ?? "未知"} ${r.activity != null ? "· ${r.activity}" : ""}',
                          style: TextStyle(fontSize: 13, fontWeight: i == trajectory.length - 1 ? FontWeight.w600 : FontWeight.normal),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SetAILocationSheet extends StatelessWidget {
  final Function(String name, String type, String activity) onSelected;
  const _SetAILocationSheet({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final categories = [
      ('office', '公司', Icons.business),
      ('cafe', '咖啡厅', Icons.local_cafe),
      ('restaurant', '餐厅', Icons.restaurant),
      ('mall', '商场', Icons.shopping_bag),
      ('park', '公园', Icons.park),
      ('cinema', '电影院', Icons.movie),
      ('gym', '健身房', Icons.fitness_center),
      ('hotel', '酒店', Icons.hotel),
      ('ktv', 'KTV', Icons.mic),
      ('home', '家', Icons.home),
      ('bookstore', '书店', Icons.menu_book),
      ('supermarket', '超市', Icons.shopping_cart),
    ];

    return Container(
      height: MediaQuery.of(context).size.height * 0.55,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('设置AI位置', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: categories.length,
              itemBuilder: (_, i) {
                final (type, label, icon) = categories[i];
                final pois = AILocationEngine.getAllPOIs().where((p) => p['type'] == type).toList();
                return ExpansionTile(
                  leading: Icon(icon, size: 20),
                  title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  children: pois.map((poi) => ListTile(
                    dense: true,
                    title: Text(poi['name']!),
                    subtitle: Text(poi['address'] ?? '', style: const TextStyle(fontSize: 11)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                    onTap: () {
                      onSelected(poi['name']!, type, '前往${poi['name']}');
                      Navigator.pop(context);
                    },
                  )).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
