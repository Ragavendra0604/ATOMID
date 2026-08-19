import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Cover for UI-1, source-level half.
///
/// Every icon-only control has to say what it does. Without a label a screen
/// reader announces "button", and in a list of fifty product rows that is
/// indistinguishable from the other forty-nine — the user cannot tell which
/// row they are about to delete.
///
/// Flutter derives a button's semantic label from its `tooltip`, so requiring
/// one covers the sighted mouse user and the screen reader in a single
/// property. This is a source scan rather than a render test on purpose: it
/// holds for all 47 screens at once, including screens added after it was
/// written, and cannot be satisfied by a screen simply never being rendered.
///
/// `accessibility_guidelines_test.dart` is the other half — it renders the
/// real screens and runs Flutter's own contrast and tap-target guidelines.
void main() {
  /// Returns the argument list of every `pattern` constructor in [source],
  /// matching parentheses so a nested widget's own arguments are included
  /// rather than cutting the body short at the first `)`.
  List<String> bodiesOf(String source, RegExp pattern) {
    final bodies = <String>[];
    for (final match in pattern.allMatches(source)) {
      var depth = 1;
      var i = match.end;
      while (i < source.length && depth > 0) {
        if (source[i] == '(') depth++;
        if (source[i] == ')') depth--;
        i++;
      }
      bodies.add(source.substring(match.end, i));
    }
    return bodies;
  }

  final iconButton = RegExp(r'IconButton\(');
  // `.extended` and `.small` included: a bare FAB is the classic unlabelled
  // control, and `heroTag` alone does nothing for a screen reader.
  final fab = RegExp(r'FloatingActionButton(\.\w+)?\(');

  test('every icon-only button carries a label', () {
    final offenders = <String>[];

    final dartFiles = Directory('lib/presentation')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    for (final file in dartFiles) {
      final source = file.readAsStringSync();

      for (final body in bodiesOf(source, iconButton)) {
        if (body.contains('tooltip:')) continue;
        final icon = RegExp(r'Icons\.(\w+)').firstMatch(body)?.group(1) ?? '?';
        offenders.add('${file.path} — IconButton(Icons.$icon)');
      }

      for (final body in bodiesOf(source, fab)) {
        // An extended FAB shows visible text, which is its own label.
        if (body.contains('tooltip:') || body.contains('label:')) continue;
        final tag = RegExp(r"heroTag:\s*'([^']+)'").firstMatch(body)?.group(1);
        offenders.add('${file.path} — FloatingActionButton(${tag ?? '?'})');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These controls would be announced as an unlabelled "button". Add a '
          'tooltip saying what the control does — and where it acts on one row '
          'of a list, name the row:\n${offenders.join('\n')}',
    );
  });

  test('the guard can actually fail', () {
    // Proves the parser detects a missing label rather than always passing.
    const sample = "IconButton(icon: const Icon(Icons.delete), onPressed: x),";
    final bodies = bodiesOf(sample, iconButton);

    expect(bodies, hasLength(1));
    expect(bodies.single.contains('tooltip:'), isFalse);
  });

  test('the guard is not fooled by a nested widget', () {
    const sample = '''
      IconButton(
        tooltip: 'Remove',
        icon: Badge(label: Text('1'), child: Icon(Icons.close)),
        onPressed: doIt,
      ),
    ''';
    final bodies = bodiesOf(sample, iconButton);

    expect(bodies, hasLength(1));
    expect(
      bodies.single.contains('onPressed'),
      isTrue,
      reason: 'the body must run to the real closing paren, not the first one',
    );
  });

  test('an extended FAB is accepted on its visible label', () {
    const sample = '''
      FloatingActionButton.extended(
        heroTag: 'add-product',
        icon: Icon(Icons.add),
        label: Text('Add product'),
        onPressed: doIt,
      ),
    ''';
    final bodies = bodiesOf(sample, fab);

    expect(bodies, hasLength(1));
    expect(bodies.single.contains('label:'), isTrue);
  });
}
