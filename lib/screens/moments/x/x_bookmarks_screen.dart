import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/auth/auth_bloc.dart';
import '../../../config/moments_theme.dart';
import '../../../models/moment.dart';
import '../../../repositories/local_storage_repository.dart';
import '../../../widgets/moments/moment_card.dart';
import 'x_moment_detail_screen.dart';

/// X 推特风格书签页面
class XBookmarksScreen extends StatefulWidget {
  const XBookmarksScreen({super.key});

  @override
  State<XBookmarksScreen> createState() => _XBookmarksScreenState();
}

class _XBookmarksScreenState extends State<XBookmarksScreen> {
  List<Moment> _bookmarks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    final storage = context.read<LocalStorageRepository>();
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : '';

    final bookmarks = await storage.getBookmarkedMoments(userId);
    if (mounted) {
      setState(() {
        _bookmarks = bookmarks;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MomentsTheme.background(context),
      appBar: AppBar(
        backgroundColor: MomentsTheme.cardBackground(context),
        elevation: 0,
        title: Text('书签',
            style: TextStyle(
              color: MomentsTheme.textPrimary(context),
              fontWeight: FontWeight.bold,
            )),
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: MomentsTheme.textPrimary(context)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                  color: MomentsTheme.primary(context)))
          : _bookmarks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(MomentsTheme.bookmark,
                          size: 64,
                          color: MomentsTheme.textSecondary(context)),
                      const SizedBox(height: 16),
                      Text('还没有书签',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: MomentsTheme.textPrimary(context),
                          )),
                      const SizedBox(height: 8),
                      Text('收藏动态后会显示在这里',
                          style: TextStyle(
                            fontSize: 14,
                            color: MomentsTheme.textSecondary(context),
                          )),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: MomentsTheme.primary(context),
                  onRefresh: _loadBookmarks,
                  child: ListView.builder(
                    itemCount: _bookmarks.length,
                    itemBuilder: (ctx, i) => MomentCard(
                      moment: _bookmarks[i],
                      isBookmarked: true,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => XMomentDetailScreen(
                              momentId: _bookmarks[i].id),
                        ),
                      ).then((_) => _loadBookmarks()),
                    ),
                  ),
                ),
    );
  }
}
