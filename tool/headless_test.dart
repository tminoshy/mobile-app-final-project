// Run the existing suites in flutter_tester without a VM-service connection.
// The normal runner remains `flutter test`; see tool/test_headless.sh.
import '../test/core_test.dart' as core;
import '../test/database_test.dart' as database;
import '../test/guest_flow_test.dart' as guest;

void main() {
  core.main();
  database.main();
  guest.main();
}
