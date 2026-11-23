import 'package:flutter_test/flutter_test.dart';

import '../tool/self_test.dart' as regression;

void main() {
  test('domain, workspace, and sync regression suite', regression.main);
}
