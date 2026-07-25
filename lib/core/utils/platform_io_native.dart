import 'dart:io' as io;

class PlatformIo {
  static bool get isAndroid => io.Platform.isAndroid;
  static bool get isIOS => io.Platform.isIOS;
  static bool get isWindows => io.Platform.isWindows;
  static bool get isMacOS => io.Platform.isMacOS;
  static bool get isLinux => io.Platform.isLinux;
  static String? get userProfile => io.Platform.environment['USERPROFILE'];
}

typedef PlatformFile = io.File;
typedef PlatformDirectory = io.Directory;
