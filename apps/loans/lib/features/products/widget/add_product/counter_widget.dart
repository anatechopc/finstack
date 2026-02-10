import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:loooans/app/counter_cubit.dart';
import 'package:loooans/utils/screen_helpers.dart';

class CounterWidget extends StatelessWidget {
  const CounterWidget({
    required this.initialValue,
    required this.onChanged,
    super.key,
    this.minValue = 1,
  });

  final int initialValue;
  final ValueChanged<int> onChanged;
  final int minValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.black,
        borderRadius: BorderRadius.circular(16),
      ),
      child: BlocProvider(
        create: (context) => CounterCubit(
          initValue: initialValue,
          minValue: minValue,
          onChanged: onChanged,
        ),
        child: BlocBuilder<CounterCubit, int>(
          builder: (context, state) {
            return Row(
              children: [
                IconButton(
                  onPressed: () {
                    context.read<CounterCubit>().decrease();
                  },
                  icon: const Icon(
                    Icons.remove,
                    color: AppColors.white,
                  ),
                ),
                const Gap(4),
                Text(
                  '$state',
                  style: const TextStyle(
                    color: AppColors.white,
                  ),
                ),
                const Gap(4),
                IconButton(
                  onPressed: () {
                    context.read<CounterCubit>().increase();
                  },
                  icon: const Icon(
                    Icons.add_rounded,
                    color: AppColors.white,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
