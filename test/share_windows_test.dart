import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Test share plus on windows', () async {
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile('pubspec.yaml')], text: 'text'),
      );
      print("Share success!");
    } catch (e) {
      print("Share failed: $e");
    }
  });
}
