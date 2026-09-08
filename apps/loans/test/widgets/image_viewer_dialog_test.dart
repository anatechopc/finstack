import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/widgets/image_viewer_dialog.dart';

import '../helpers/helpers.dart';

// Standard 1x1 transparent PNG.
final kTransparentImage = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  testWidgets('shows zoom controls and closes', (tester) async {
    await tester.pumpApp(
      Builder(
        builder: (context) {
          return Scaffold(
            body: ElevatedButton(
              onPressed: () => showImageViewerDialog(
                context,
                url: 'x',
                imageProvider: MemoryImage(kTransparentImage),
              ),
              child: const Text('Open'),
            ),
          );
        },
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byTooltip('Zoom in'), findsOneWidget);
    expect(find.byTooltip('Zoom out'), findsOneWidget);
    expect(find.byTooltip('Reset zoom'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);

    final windowSize = tester.view.physicalSize / tester.view.devicePixelRatio;
    final expectedWidth = (windowSize.width * 0.8).clamp(320.0, double.infinity);
    final expectedHeight =
        (windowSize.height * 0.8).clamp(320.0, double.infinity);

    final sizedBox = tester.widget<SizedBox>(
      find
          .descendant(
            of: find.byType(Dialog),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(sizedBox.width, expectedWidth);
    expect(sizedBox.height, expectedHeight);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
  });
}
