import 'package:flutter/material.dart';
import 'package:loooans/utils/screen_helpers.dart';

class AlphaBanner extends StatefulWidget {
  const AlphaBanner({super.key});

  @override
  State<AlphaBanner> createState() => _AlphaBannerState();
}

class _AlphaBannerState extends State<AlphaBanner> {
  bool _isVisible = true;

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) {
      return const SizedBox.shrink();
    }

    return Material(
      child: Container(
        width: double.infinity,
        height: 56,
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        color: AppColors.ubOrange,
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.lightBlack,
              size: 20,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '\u{1F6A7} This app is currently in ALPHA stage. Features may be incomplete or change without notice.',
                style: TextStyle(
                  color: AppColors.lightBlack,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            IconButton(
              onPressed: () {
                setState(() {
                  _isVisible = false;
                });
              },
              icon: const Icon(
                Icons.close,
                color: AppColors.lightBlack,
                size: 20,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 24,
                minHeight: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
