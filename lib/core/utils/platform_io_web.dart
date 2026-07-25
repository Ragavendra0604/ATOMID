import 'dart:typed_data';

class PlatformIo {
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isWindows => false;
  static bool get isMacOS => false;
  static bool get isLinux => false;
  static String? get userProfile => null;

  static Future<String> getApplicationSupportDirectoryPath() async {
    return '';
  }

  static Future<String> getApplicationDocumentsDirectoryPath() async {
    return '';
  }
}

class PlatformFile {
  PlatformFile(String path);
  bool existsSync() => false;
  Future<bool> exists() async => false;
  Future<void> create({bool recursive = false}) async {}
  void createSync({bool recursive = false}) {}
  String get path => '';
  Future<void> writeAsBytes(List<int> bytes) async {}
  Future<Uint8List> readAsBytes() async => Uint8List(0);
}

class PlatformDirectory {
  PlatformDirectory(String path);
  bool existsSync() => false;
  Future<bool> exists() async => false;
  void createSync({bool recursive = false}) {}
  Future<void> create({bool recursive = false}) async {}
  String get path => '';
}
