import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../config/moments_theme.dart';
import '../../../models/moment.dart';
import '../../../models/trending_tag.dart';
import '../../../repositories/local_storage_repository.dart';
import '../../../widgets/moments/moment_card.dart';
import 'x_moment_detail_screen.dart';

/// X 推特风格搜索页面
class XSearchScreen extends StatefulWidget {
  const XSearchScreen({super.key});

  @override
  State<XSearchScreen> createState() => _XSearchScreenState();
}

class _XSearchScreenState extends State<XSearchScreen> {
  final _controller = TextEditingController();
  List<Moment> _results = [];
  List<TrendingTag> _trending = [];
  bool _isSearching = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _loadTrending();
  }

  Future<void> _loadTrending() async {
    final storage = context.read<LocalStorageRepository>();
    final trending = await storage.getTrendingTags(limit: 20);
    if (mounted) setState(() => _trending = trending);
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _isSearching = true);
    final storage = context.read<LocalStorageRepository>();
    final results = await storage.searchMoments(query.trim());
    if (mounted) {
      setState(() {
        _results = results;
        _isSearching = false;
        _hasSearched = true;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MomentsTheme.background(context),
      appBar: AppBar(
        backgroundColor: MomentsTheme.cardBackground(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: MomentsTheme.textPrimary(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: TextStyle(
            fontSize: 18,
            color: MomentsTheme.textPrimary(context),
          ),
          decoration: InputDecoration(
            hintText: '搜索动态...',
            hintStyle: TextStyle(
              color: MomentsTheme.textSecondary(context),
            ),
            border: InputBorder.none,
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear,
                        color: MomentsTheme.textSecondary(context)),
                    onPressed: () {
                      _controller.clear();
                      setState(() {
                        _results = [];
                        _hasSearched = false;
                      });
                    },
                  )
                : null,
          ),
          onChanged: (v) => setState(() {}),
          onSubmitted: _search,
          textInputAction: TextInputAction.search,
        ),
      ),
      body: _hasSearched ? _searchResults() : _trendingSection(),
    );
  }

  Widget _trendingSection() {
    if (_trending.isEmpty) {
      return Center(
        child: Text('暂无热门话题',
            style: TextStyle(color: MomentsTheme.textSecondary(context))),
      );
    }
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '热门话题',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: MomentsTheme.textPrimary(context),
            ),
          ),
        ),
        ...List.generate(_trending.length, (i) {
          final tag = _trending[i];
          return ListTile(
            leading: Text(
              '${i + 1}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: MomentsTheme.textSecondary(context),
              ),
            ),
            title: Text(
              '#${tag.tag}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: MomentsTheme.textPrimary(context),
              ),
            ),
            subtitle: Text(
              '${tag.count} 条动态',
              style: TextStyle(
                  color: MomentsTheme.textSecondary(context)),
            ),
            onTap: () {
              _controller.text = '#${tag.tag}';
              _search('#${tag.tag}');
            },
          );
        }),
      ],
    );
  }

  Widget _searchResults() {
    if (_isSearching) {
      return Center(
        child: CircularProgressIndicator(
            color: MomentsTheme.primary(context)),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search,
                size: 64, color: MomentsTheme.textSecondary(context)),
            const SizedBox(height: 16),
            Text('没有找到相关动态',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: MomentsTheme.textPrimary(context),
                )),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (ctx, i) => MomentCard(
        moment: _results[i],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  XMomentDetailScreen(momentId: _results[i].id)),
        ),
      ),
    );
  }
}
