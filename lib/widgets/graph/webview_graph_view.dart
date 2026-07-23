import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'graph_node.dart';

/// 企业级图谱组件 — WebView + D3.js 力导向布局
class WebViewGraphView extends StatefulWidget {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final void Function(String nodeId)? onNodeTap;
  final void Function()? onBackgroundTap;
  final Set<String>? highlightedNodeIds;
  final bool isDark;

  const WebViewGraphView({
    super.key,
    required this.nodes,
    required this.edges,
    this.onNodeTap,
    this.onBackgroundTap,
    this.highlightedNodeIds,
    this.isDark = false,
  });

  @override
  State<WebViewGraphView> createState() => _WebViewGraphViewState();
}

class _WebViewGraphViewState extends State<WebViewGraphView> {
  late final WebViewController _controller;
  bool _pageLoaded = false;
  bool _firstDataPushed = false;

  static const _typeColorsLight = [
    '#4A90D9',
    '#9C5A9A',
    '#E879A8',
    '#D94A6A',
    '#E85D9C',
    '#5AAF6A',
    '#BA68C8',
  ];

  static const _typeColorsDark = [
    '#6BA8E8',
    '#B87AB6',
    '#F098BC',
    '#E86A86',
    '#F07AB2',
    '#72C482',
    '#C98FD4',
  ];

  static const _bgLight = Color(0xFFF8F9FA);
  static const _bgDark = Color(0xFF121212);

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(widget.isDark ? _bgDark : _bgLight)
      ..addJavaScriptChannel('FlutterChannel', onMessageReceived: _onMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          _pageLoaded = true;
          _pushGraphData();
        },
      ))
      ..loadFlutterAsset('assets/graph/index.html');
  }

  void _onMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message);
      switch (data['type']) {
        case 'nodeTap':
          widget.onNodeTap?.call(data['nodeId']);
          break;
        case 'backgroundTap':
          widget.onBackgroundTap?.call();
          break;
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(WebViewGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_pageLoaded) return;
    final dataChanged =
        oldWidget.nodes != widget.nodes || oldWidget.edges != widget.edges;
    final themeChanged = oldWidget.isDark != widget.isDark;
    if (themeChanged) {
      _controller.setBackgroundColor(widget.isDark ? _bgDark : _bgLight);
    }
    if (dataChanged || themeChanged) {
      _pushGraphData();
    }
  }

  void _pushGraphData() {
    if (!_pageLoaded) return;

    final data = _buildGraphData();
    final jsonStr = jsonEncode(data);
    final js = 'updateGraph($jsonStr)';
    _controller.runJavaScript(js);
    _firstDataPushed = true;
  }

  Map<String, dynamic> _buildGraphData() {
    final colors = widget.isDark ? _typeColorsDark : _typeColorsLight;
    return {
      'dark': widget.isDark,
      'nodes': widget.nodes
          .map((n) => {
                'id': n.id,
                'label': n.label,
                'subtitle': n.subtitle ?? '',
                'summary': n.summary ?? '',
                'color': colors[n.typeIndex % colors.length],
                'radius': n.radius,
                'width': _calculateNodeWidth(n),
                'height': 52.0,
              })
          .toList(),
      'edges': widget.edges
          .map((e) => {
                'source': e.sourceId,
                'target': e.targetId,
                'label': e.label ?? '',
              })
          .toList(),
    };
  }

  double _calculateNodeWidth(GraphNode n) => 148.0;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: widget.isDark ? _bgDark : _bgLight,
      child: WebViewWidget(controller: _controller),
    );
  }
}

