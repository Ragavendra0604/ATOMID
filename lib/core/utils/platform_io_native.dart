import 'dart:io' as io;
import 'package:path_provider/path_provider.dart';

class PlatformIo {
  static bool get isAndroid => io.Platform.isAndroid;
  static bool get isIOS => io.Platform.isIOS;
  static bool get isWindows => io.Platform.isWindows;
  static bool get isMacOS => io.Platform.isMacOS;
  static bool get isLinux => io.Platform.isLinux;
  static String? get userProfile => io.Platform.environment['USERPROFILE'];

  static Future<String> getApplicationSupportDirectoryPath() async {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }

  static Future<String> getApplicationDocumentsDirectoryPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }
}

typedef PlatformFile = io.File;
typedef PlatformDirectory = io.Directory;
