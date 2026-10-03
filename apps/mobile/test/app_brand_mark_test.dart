import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/widgets/app_brand_mark.dart';

void main() {
  testWidgets('default brand uses approved glass artwork without tint', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppBrandMark(size: 64))),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/brand/app_icon_glass.png',
    );
    expect(image.width, 64);
    expect(image.color, isNull);
    expect(find.byType(SvgPicture), findsNothing);
  });

  testWidgets('explicit-color compact marks retain scalable original shape', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppBrandMark(color: Colors.white)),
      ),
    );
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
