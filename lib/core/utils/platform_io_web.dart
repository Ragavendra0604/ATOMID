import 'dart:async';
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

  static Future<String?> getExternalStorageDirectoryPath() async => null;
}

class PlatformFileStat {
  final int size = 0;
  final DateTime modified = DateTime.fromMillisecondsSinceEpoch(0);
}

class PlatformFile {
  PlatformFile(String path);
  bool existsSync() => false;
  Future<bool> exists() async => false;
  Future<void> create({bool recursive = false}) async {}
  void createSync({bool recursive = false}) {}
  String get path => '';
  Future<void> writeAsBytes(List<int> bytes, {bool flush = false}) async {}
  Future<Uint8List> readAsBytes() async => Uint8List(0);
  Future<String> readAsString() async => '';
  Future<PlatformFile> rename(String newPath) async => this;
  Future<PlatformFileStat> stat() async => PlatformFileStat();
  Future<void> delete({bool recursive = false}) async {}
}

class PlatformDirectory {
  PlatformDirectory(String path);
  bool existsSync() => false;
  Future<bool> exists() async => false;
  void createSync({bool recursive = false}) {}
  Future<void> create({bool recursive = false}) async {}
  String get path => '';
  Stream<dynamic> list({bool recursive = false, bool followLinks = true}) => const Stream.empty();
}
