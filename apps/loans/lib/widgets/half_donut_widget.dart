import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:loooans/utils/screen_helpers.dart';

class HalfDonutPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final centerX = width / 2;
    final centerY = height / 2;
    final radius = width / 2 - 200;

    final paint = Paint()
      ..color = AppColors.white
      ..style = PaintingStyle.stroke
      // ..shader = ui.Gradient.sweep(
      //   Offset(centerX, centerY),
      //   [
      //     Colors.transparent,
      //     Colors.transparent,
      //     Colors.transparent,
      //     AppColors.white,
      //     AppColors.white,
      //   ],
      //   [
      //     0.0,
      //     0.25,
      //     0.5,
      //     0.75,
      //     1.0,
      //   ],
      // )
      ..strokeWidth = 60
      ..strokeCap = StrokeCap.round;
    final paint2 = Paint()
      // ..color = AppColors.white
      ..style = PaintingStyle.stroke
      ..shader = ui.Gradient.sweep(
        Offset(centerX, centerY),
        [
          Colors.white,
          Colors.grey.withValues(alpha: 0.6),
          AppColors.black,
        ],
        [
          0.1,
          0.4,
          0.8,
        ],
      )
      ..strokeWidth = 60;
    final paint3 = Paint()
    // ..color = AppColors.white
      ..style = PaintingStyle.stroke
      ..shader = ui.Gradient.sweep(
        Offset(centerX, centerY),
        [
          Colors.white,
          Colors.grey.withValues(alpha: 0.2),
          AppColors.black.withValues(alpha: 0.4),
        ],
        [
          0.1,
          0.4,
          0.8,
        ],
      )
      ..strokeWidth = 60;

    final outerRect = Rect.fromCircle(
      center: Offset(centerX, centerY),
      radius: radius,
    );
    final innerRect = Rect.fromCircle(
      center: Offset(centerX, centerY),
      radius: radius / 1.74,
    );

    // final path = Path()
    //   ..arcTo(outerRect, 0, -3.14, true) // Draw half of the outer circle
    //   // ..arcTo(innerRect, 3.14, 3.14, true) // Draw the inner half-circle
    //   // ..addArc(outerRect, 0, -3.14)
    //   ..close();

    // canvas.drawPath(path, paint);
    canvas
      ..drawArc(outerRect, -0.1, -0.8, false, paint)
      ..drawArc(outerRect, -0.8, -2.34, false, paint2)
      ..drawArc(innerRect, -0.8, -2.34, false, paint3);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
