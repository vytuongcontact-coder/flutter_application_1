import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/widgets/splash_screen.dart';

void main() {
  testWidgets('Splash chuyển sang home và không còn trong lịch sử', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
    await tester.pump(SplashScreen.displayDuration);
    await tester.pumpAndSettle();
    expect(find.byType(SplashScreen), findsNothing);
    final appBarTitle = find.descendant(
      of: find.byType(AppBar),
      matching: find.text('Trang chủ'),
    );
    expect(appBarTitle, findsOneWidget);
    expect(find.byTooltip('Trang chủ'), findsOneWidget);
    final context = tester.element(appBarTitle);
    expect(GoRouter.of(context).canPop(), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant({TargetPlatform.linux}));

  testWidgets('Đóng splash sớm không gây điều hướng sau dispose', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(SplashScreen.displayDuration);
    expect(tester.takeException(), isNull);
  });
}
