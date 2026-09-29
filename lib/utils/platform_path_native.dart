// Native — 真实 path_provider
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory, getApplicationDocumentsDirectory;

Future<String?> getTemporaryDirectoryPath() async {
  final dir = await getTemporaryDirectory();
  return dir.path;
}

Future<String?> getApplicationDocumentsDirectoryPath() async {
  final dir = await getApplicationDocumentsDirectory();
  return dir.path;
}