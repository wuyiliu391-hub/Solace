import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// file_picker 8.x uses a late platform singleton. Some Flutter builds can
/// register the native Android plugin but miss the Dart platform instance,
/// causing FilePicker.platform to throw before the picker opens.
class SafeFilePicker {
  SafeFilePicker._();

  static void _ensurePlatform() {
    try {
      FilePicker.platform;
    } catch (error) {
      if (!_isUninitializedPlatform(error)) {
        rethrow;
      }
      FilePickerIO.registerWith();
    }
  }

  static bool _isUninitializedPlatform(Object error) {
    final message = error.toString();
    return error.runtimeType.toString() == 'LateInitializationError' &&
        message.contains('_instance');
  }

  static Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    _ensurePlatform();
    try {
      return await FilePicker.platform.pickFiles(
        dialogTitle: dialogTitle,
        initialDirectory: initialDirectory,
        type: type,
        allowedExtensions: allowedExtensions,
        onFileLoading: onFileLoading,
        allowCompression: allowCompression,
        compressionQuality: compressionQuality,
        allowMultiple: allowMultiple,
        withData: withData,
        withReadStream: withReadStream,
        lockParentWindow: lockParentWindow,
        readSequential: readSequential,
      );
    } catch (error) {
      if (!_isUninitializedPlatform(error)) {
        rethrow;
      }
      FilePickerIO.registerWith();
      return FilePicker.platform.pickFiles(
        dialogTitle: dialogTitle,
        initialDirectory: initialDirectory,
        type: type,
        allowedExtensions: allowedExtensions,
        onFileLoading: onFileLoading,
        allowCompression: allowCompression,
        compressionQuality: compressionQuality,
        allowMultiple: allowMultiple,
        withData: withData,
        withReadStream: withReadStream,
        lockParentWindow: lockParentWindow,
        readSequential: readSequential,
      );
    }
  }

  static Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    _ensurePlatform();
    try {
      return await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        initialDirectory: initialDirectory,
        type: type,
        allowedExtensions: allowedExtensions,
        bytes: bytes,
        lockParentWindow: lockParentWindow,
      );
    } catch (error) {
      if (!_isUninitializedPlatform(error)) {
        rethrow;
      }
      FilePickerIO.registerWith();
      return FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        initialDirectory: initialDirectory,
        type: type,
        allowedExtensions: allowedExtensions,
        bytes: bytes,
        lockParentWindow: lockParentWindow,
      );
    }
  }
}
