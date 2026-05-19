import 'package:flutter_test/flutter_test.dart';
import 'package:neyesem_mobile/main.dart';

void main() {
  testWidgets('shows NeYesem auth screen', (WidgetTester tester) async {
    await tester.pumpWidget(const NeYesemDemoApp());

    expect(find.text('NeYesem'), findsOneWidget);
    expect(find.text('Giriş yap'), findsOneWidget);
    expect(
      find.text('Fiyatları karşılaştır, sahte indirimleri yakala.'),
      findsOneWidget,
    );
  });
}
