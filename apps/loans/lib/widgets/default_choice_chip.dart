import 'package:flutter/material.dart';
import 'package:loooans/utils/screen_helpers.dart';

class DefaultChoiceChip extends StatelessWidget {
  const DefaultChoiceChip({
    required this.title, super.key,
    this.onTap,
    this.color = AppColors.white,
  });

  final String title;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: 8,
          horizontal: 16,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: color),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
