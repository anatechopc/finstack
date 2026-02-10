import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// based on
/// https://m3.material.io/foundations/layout/applying-layout/window-size-classes
enum ScreenSize {
  /// phone screens
  compact,

  /// tablet screens - portrait
  /// phone screens - landscape
  medium,

  /// tablet screens - landscape
  /// foldable (unfolded)
  /// desktop screen - small
  expanded,

  /// desktop screens
  large,
}

const defaultIconSize = 24.0;
const defaultRadiusSize = 16.0;
const defaultPaddingSize = 16.0;
const defaultRadius = Radius.circular(defaultRadiusSize);
final defaultBorderRadius = BorderRadius.circular(defaultRadiusSize);
const defaultIconSize2 = Size(defaultIconSize, defaultIconSize);
const defaultCompactButtonPadding = EdgeInsets.symmetric(
  vertical: 16,
  horizontal: 24,
);
const defaultButtonPadding = EdgeInsets.symmetric(
  vertical: 24,
  horizontal: 20,
);

const defaultIconButtonPadding = EdgeInsets.symmetric(
  vertical: 18,
  horizontal: 20,
);

int lastTapMenuPosition = 0;

/// gets the screen size of the current context
ScreenSize getScreenSize({required BuildContext context}) {
  final deviceWidth = MediaQuery.sizeOf(context).width;
  // debugPrint('deviceWidth: $deviceWidth');

  if (deviceWidth < 600) return ScreenSize.compact;
  if (deviceWidth < 840) return ScreenSize.medium;
  if (deviceWidth < 1200) return ScreenSize.expanded;

  return ScreenSize.large;
}

/// returns true if the current platform/os is a android
/// or iOS
bool get isMobilePlatform {
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

class ImageHelper {
  static Image assetSafe(String name,
      {double? width, double? height, BoxFit? fit,}) {
    if (kIsWeb) {
      return Image.network(
        name,
        width: width,
        height: height,
        fit: fit,
      );
    }

    return Image.asset(
      name,
      width: width,
      height: height,
      fit: fit,
    );
  }
}

// class BitmapDescriptorHelper {
//   static Future<BitmapDescriptor> getBitmapDescriptorFromSvgAsset(
//       String assetName, [
//         Size size = const Size(48, 48),
//       ]) async {
//     final pictureInfo = await vg.loadPicture(SvgAssetLoader(assetName), null);
//
//     double devicePixelRatio = ui.window.devicePixelRatio;
//     int width = (size.width * devicePixelRatio).toInt();
//     int height = (size.height * devicePixelRatio).toInt();
//
//     final scaleFactor = math.min(
//       width / pictureInfo.size.width,
//       height / pictureInfo.size.height,
//     );
//
//     final recorder = ui.PictureRecorder();
//
//     ui.Canvas(recorder)
//       ..scale(scaleFactor)
//       ..drawPicture(pictureInfo.picture);
//
//     final rasterPicture = recorder.endRecording();
//
//     final image = rasterPicture.toImageSync(width, height);
//     final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
//
//     return BitmapDescriptor.fromBytes(bytes.buffer.asUint8List());
//   }
// }

/// application colors
abstract class AppColors {
  static const Color green1 = Color(0xFF38DC93);
  static const Color green1_5 = Color(0xFF28A16B);
  static const Color green1_6 = Color(0xFF16A163);
  static const Color green2 = Color(0xFF92E50A);
  static const Color red = Color(0xFFFE5858);
  static const Color red2 = Color(0xFFE51C1C);
  static const Color blue = Color(0xFF299CFF);
  static const Color white = Colors.white;
  static const Color black = Colors.black;
  static const Color lightBlack = Color(0xFF1C1B1F);
  static const Color buttonIconTransparencyBlack = Color(0x0D000000);
  static const Color ubOrange = Color(0xFFFEA30B);

  static const Color chart1 = Color(0xFFBB86FC);
  static const Color chart1_1 = Color(0xFFBB86FC);
  static const Color chart2 = Color(0xFFFFC775);
  static const Color chart2_1 = Color(0xFFFFDF80);
  // for capital usage
  static const Color chart3 = Color(0xFFEE77A2);
  static const Color chart4 = Color(0xFFD582E3);
  // for others
  static const Color chart5 = Color(0xFFFCBB86);
  static const Color chart6 = Color(0xFF80CBC3);

  static const Color chartEmpty = Color(0xFF404040);

  static const loanItemColorsList = [
    green2,
    blue,
    chart6,
    chart2,
  ];

  static const capitalUsageItemColorsList = [
    chart1,
    chart2,
    chart3,
    chart4,
    chart5,
    chart6,
  ];
  static const salesItemColorsList = [
    chart1_1,
    chart2_1,
    chart3,
    chart4,
    chart5,
    chart6,
  ];
}

/// Semantic spacing constants.
///
/// Use these instead of raw numbers for consistent spacing throughout the app.
/// See DESIGN.md for full documentation.
abstract class AppSpacing {
  /// Extra small spacing - 4.0
  static const double xs = 4;

  /// Small spacing - 8.0
  static const double sm = 8;

  /// Medium spacing (default) - 16.0
  static const double md = 16;

  /// Large spacing - 24.0
  static const double lg = 24;

  /// Extra large spacing - 32.0
  static const double xl = 32;

  /// Extra extra large spacing - 48.0
  static const double xxl = 48;
}

/// Typography size constants.
///
/// Use these with `Theme.of(context).textTheme` styles or for custom text.
/// See DESIGN.md for full documentation.
abstract class AppTypography {
  /// Logo title - 64px
  static const double displayLarge = 64;

  /// Section headers, dialog titles - 24px
  static const double headlineLarge = 24;

  /// Amount displays (whole number) - 20px
  static const double headlineMedium = 20;

  /// Tagline/subtitle - 18px
  static const double titleLarge = 18;

  /// Body text, welcome text, buttons - 16px
  static const double bodyLarge = 16;

  /// Card titles, notification text - 14px
  static const double bodyMedium = 14;

  /// Helper text, chips, currency symbols - 12px
  static const double bodySmall = 12;

  /// Timestamps, tertiary text - 10px
  static const double labelSmall = 10;
}
