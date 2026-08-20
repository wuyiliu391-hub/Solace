import 'package:flutter/material.dart';
import '../../config/wechat_theme.dart';

/// 微信朋友圈 — 1:1 还原
///
/// 结构（item_dynamic_head.xml + item_dynamic_img.xml）：
/// 封面图 250dp + 昵称/头像右下角叠加
/// 动态卡片：头像33dp + 蓝色昵称(#576B95) + 正文 + 九宫格图 + 时间/位置 + 操作
class WxMomentsPage extends StatelessWidget {
  final ImageProvider? coverImage;     // 朋友圈封面
  final String nickname;
  final ImageProvider? avatar;        // 我的头像
  final String? signature;             // 个性签名
  final List<WxMoment> moments;        // 动态列表
  final VoidCallback? onBack;
  final VoidCallback? onCamera;        // 顶部相机
  final VoidCallback? onCoverTap;      // 点击封面换图

  const WxMomentsPage({
    super.key,
    this.coverImage,
    required this.nickname,
    this.avatar,
    this.signature,
    required this.moments,
    this.onBack,
    this.onCamera,
    this.onCoverTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: WxColors.listBg,
      child: CustomScrollView(
        slivers: [
          // 封面区
          SliverToBoxAdapter(
            child: _CoverHeader(
              cover: coverImage,
              nickname: nickname,
              avatar: avatar,
              signature: signature,
              onBack: onBack,
              onCamera: onCamera,
              onCoverTap: onCoverTap,
            ),
          ),
          // 动态列表
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _MomentCard(moment: moments[i]),
              childCount: moments.length,
            ),
          ),
          SliverFillRemaining(hasScrollBody: false),
        ],
      ),
    );
  }
}

/// 封面 + 头像叠加
class _CoverHeader extends StatelessWidget {
  final ImageProvider? cover;
  final String nickname;
  final ImageProvider? avatar;
  final String? signature;
  final VoidCallback? onBack;
  final VoidCallback? onCamera;
  final VoidCallback? onCoverTap;
  const _CoverHeader({
    this.cover,
    required this.nickname,
    this.avatar,
    this.signature,
    this.onBack,
    this.onCamera,
    this.onCoverTap,
  });

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Stack(
      children: [
        // 封面图
        GestureDetector(
          onTap: onCoverTap,
          child: Container(
            height: 280 + topPad,
            width: double.infinity,
            color: const Color(0xFFDDDDDD),
            child: cover != null
                ? Image(image: cover!, fit: BoxFit.cover)
                : null,
          ),
        ),
        // 顶部返回 + 相机（浮在封面上）
        Positioned(
          top: topPad + 6,
          left: 6,
          child: IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.chevron_left,
                color: Colors.white, size: 28),
          ),
        ),
        Positioned(
          top: topPad + 6,
          right: 6,
          child: IconButton(
            onPressed: onCamera,
            icon: const Icon(Icons.camera_alt_outlined,
                color: Colors.white, size: 24),
          ),
        ),
        // 昵称 + 头像（右下角叠加，封面底部）
        Positioned(
          bottom: 0,
          right: 10,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(nickname,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(color: Colors.black54, blurRadius: 4)
                      ])),
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 52,
                  height: 52,
                  color: const Color(0xFFDDDEDD),
                  child: avatar != null
                      ? Image(image: avatar!, fit: BoxFit.cover)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 朋友圈动态数据
class WxMoment {
  final String authorName;
  final ImageProvider? avatar;
  final String content;
  final List<ImageProvider> images;  // 九宫格图
  final String? location;
  final String time;
  final List<WxLike> likes;
  final List<WxComment> comments;

  const WxMoment({
    required this.authorName,
    this.avatar,
    required this.content,
    this.images = const [],
    this.location,
    required this.time,
    this.likes = const [],
    this.comments = const [],
  });
}

class WxLike {
  final String name;
  final ImageProvider? avatar;
  const WxLike({required this.name, this.avatar});
}

class WxComment {
  final String name;
  final String text;
  const WxComment({required this.name, required this.text});
}

/// 动态卡片
class _MomentCard extends StatelessWidget {
  final WxMoment moment;
  const _MomentCard({required this.moment});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: WxColors.listBg,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头像
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              width: 33,
              height: 33,
              color: const Color(0xFFDDDEDD),
              child: moment.avatar != null
                  ? Image(image: moment.avatar!, fit: BoxFit.cover)
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          // 右侧内容
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 昵称（微信蓝）
                Text(moment.authorName,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: WxColors.link)),
                const SizedBox(height: 5),
                // 正文
                Text(moment.content,
                    style: const TextStyle(
                        fontSize: 14, color: WxColors.textBlack, height: 1.4)),
                // 九宫格图
                if (moment.images.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  _ImageGrid(images: moment.images),
                ],
                // 位置
                if (moment.location != null) ...[
                  const SizedBox(height: 5),
                  Text(moment.location!,
                      style: const TextStyle(
                          fontSize: 11, color: WxColors.link)),
                ],
                // 时间
                const SizedBox(height: 5),
                Text(moment.time,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFFAAAAAA))),
                // 点赞评论区
                if (moment.likes.isNotEmpty || moment.comments.isNotEmpty)
                  _LikeCommentBlock(
                      likes: moment.likes, comments: moment.comments),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 九宫格图
class _ImageGrid extends StatelessWidget {
  final List<ImageProvider> images;
  const _ImageGrid({required this.images});

  @override
  Widget build(BuildContext context) {
    if (images.length == 1) {
      // 单图大图
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180, maxHeight: 240),
          child: Image(image: images.first, fit: BoxFit.cover),
        ),
      );
    }
    final cross = images.length == 4 ? 2 : 3;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: images.map((img) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Image(
            image: img,
            width: (MediaQuery.of(context).size.width - 100) / cross,
            height: (MediaQuery.of(context).size.width - 100) / cross,
            fit: BoxFit.cover,
          ),
        );
      }).toList(),
    );
  }
}

/// 点赞评论区（浅灰背景）
class _LikeCommentBlock extends StatelessWidget {
  final List<WxLike> likes;
  final List<WxComment> comments;
  const _LikeCommentBlock({required this.likes, required this.comments});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (likes.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.favorite,
                    size: 14, color: WxColors.link),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    likes.map((l) => l.name).join('，'),
                    style: const TextStyle(
                        fontSize: 12, color: WxColors.link),
                  ),
                ),
              ],
            ),
          ],
          if (likes.isNotEmpty && comments.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Divider(height: 0.5, color: Color(0xFFE1E1E1)),
            ),
          ...comments.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                          text: '${c.name}：',
                          style: const TextStyle(
                              fontSize: 12, color: WxColors.link)),
                      TextSpan(
                          text: c.text,
                          style: const TextStyle(
                              fontSize: 12, color: WxColors.textBlack)),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
