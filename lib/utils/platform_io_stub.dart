// Web stub — dart:io 不可用，提供空实现
class Directory {
  final String path;
  Directory(this.path);
  Future<bool> exists() async => false;
  Future<Directory> create({bool recursive = false}) async => this;
  Future<Directory> delete({bool recursive = false}) async => this;
  List<FileSystemEntity> listSync({bool recursive = false}) => [];
}

class File {
  final String path;
  File(this.path);
  Future<bool> exists() async => false;
  bool existsSync() => false;
  Future<int> length() async => 0;
  Future<File> writeAsBytes(List<int> bytes, {bool flush = false}) async => this;
  Future<List<int>> readAsBytes() async => [];
  Future<File> delete() async => this;
  Future<File> copy(String newPath) async => File(newPath);
}

abstract class FileSystemEntity {}

class GzipCodec {
  List<int> encode(List<int> bytes) => bytes;
  List<int> decode(List<int> bytes) => bytes;
}

final gzip = GzipCodec();