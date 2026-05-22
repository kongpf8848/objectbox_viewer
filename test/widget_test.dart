import 'package:flutter_test/flutter_test.dart';
import 'package:objectbox_viewer/main.dart';

void main() {
  testWidgets('App starts without error', (WidgetTester tester) async {
    await tester.pumpWidget(const ObjectBoxViewerApp());
    expect(find.text('ObjectBox Viewer'), findsWidgets);
  });
}
