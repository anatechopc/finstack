import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';

class AddLoanStageIndicator extends StatelessWidget {
  AddLoanStageIndicator({
    required this.selectedIndex, super.key,
  });

  final _selectedColor = AppColors.black;
  final _defaultColor = AppColors.black.withValues(alpha: 0.4);
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _indicator(
          'Select loan product',
          selected: selectedIndex >= 0,
          indicatorIcon: SvgPicture.asset(
            'svg/cash.svg'.assetSafe,
            width: 56,
          ),
        ),
        const Gap(8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 24),
            child: _indicatorTrail(
              selected: selectedIndex >= 1,
            ),
          ),
        ),
        const Gap(8),
        _indicator(
          'Add borrower',
          selected: selectedIndex >= 1,
          indicatorIcon: SvgPicture.asset(
            'svg/user.svg'.assetSafe,
            width: 56,
          ),
        ),
        const Gap(8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 24),
            child: _indicatorTrail(
              selected: selectedIndex >= 2,
            ),
          ),
        ),
        const Gap(8),
        _indicator(
          'Computation',
          selected: selectedIndex >= 2,
          indicatorIcon: SvgPicture.asset(
            'svg/finance.svg'.assetSafe,
            width: 56,
          ),
        ),
      ],
    );
  }

  Widget _indicator(
    String title, {
    Widget? indicatorIcon,
    bool selected = false,
  }) {
    final color = selected ? _selectedColor : _defaultColor;

    return Column(
      children: [
        if (indicatorIcon != null) ...[
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              color,
              BlendMode.srcIn,
            ),
            child: indicatorIcon,
          ),
          const Gap(8),
        ],
        Text(
          title,
          style: TextStyle(
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _indicatorTrail({
    bool selected = false,
  }) {
    final color = selected ? _selectedColor : _defaultColor;

    return Container(
      width: double.infinity,
      height: 6,
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(32)),
    );
  }
}
