import 'package:flutter_test/flutter_test.dart';
import 'package:english_reader/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const EnglishReaderApp());
    expect(find.text('English Reader'), findsOneWidget);
  });
}
