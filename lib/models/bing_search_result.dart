class BingSearchResult {
  final String title;
  final String url;
  final String snippet;
  final String displayUrl;

  const BingSearchResult({
    required this.title,
    required this.url,
    required this.snippet,
    this.displayUrl = '',
  });
}
