import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/default_choice_chip.dart';

class KarmaHistoryChoiceGroup extends StatefulWidget {
  const KarmaHistoryChoiceGroup({required this.onChoiceSelected, super.key,});

  final void Function(int) onChoiceSelected;

  @override
  State<StatefulWidget> createState() {
    return _KarmaHistoryChoiceGroupState();
  }
}

class _KarmaHistoryChoiceGroupState extends State<KarmaHistoryChoiceGroup> {
  int selected = 0;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DefaultChoiceChip(
          title: '3 m',
          color: selected == 0
              ? AppColors.white
              : AppColors.white.withOpacity(0.6),
          onTap: () {
            setState(() {
              selected = 0;
              widget.onChoiceSelected(0);
            });
          },
        ),
        const Gap(8),
        DefaultChoiceChip(
          title: '6 m',
          color: selected == 1
              ? AppColors.white
              : AppColors.white.withOpacity(0.6),
          onTap: () {
            setState(() {
              selected = 1;
              widget.onChoiceSelected(1);
            });
          },
        ),
        const Gap(8),
        DefaultChoiceChip(
          title: '1 y',
          color: selected == 2
              ? AppColors.white
              : AppColors.white.withOpacity(0.6),
          onTap: () {
            setState(() {
              selected = 2;
              widget.onChoiceSelected(2);
            });
          },
        ),
      ],
    );
  }
}
