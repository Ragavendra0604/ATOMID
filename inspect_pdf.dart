import 'dart:io';

void main() {
  final bytes = File('test.pdf').readAsBytesSync();
  final content = String.fromCharCodes(bytes);
  
  // Find all cm matrices
  final matches = RegExp(r'([\d\.]+)\s+([\d\.\-]+)\s+([\d\.\-]+)\s+([\d\.]+)\s+([\d\.\-]+)\s+([\d\.\-]+)\s+cm').allMatches(content);
  for (final m in matches) {
    print('Matrix: ${m.group(1)} ${m.group(2)} ${m.group(3)} ${m.group(4)} X:${m.group(5)} Y:${m.group(6)}');
  }
}
