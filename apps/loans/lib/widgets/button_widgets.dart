import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:loooans/app/button_option_cubit.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart' show ButtonOption;

class ButtonWidgets {
  static OutlinedButton defaultOutlinedButton({
    required Widget child,
    required VoidCallback? onPressed,
    EdgeInsets padding = defaultButtonPadding,
    Color foregroundColor = AppColors.black,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: foregroundColor),
        foregroundColor: foregroundColor,
        padding: padding,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      child: child,
    );
  }

  static Widget defaultFilledButton({
    required VoidCallback? onPressed, Widget? child,
    EdgeInsets padding = defaultButtonPadding,
    Color foregroundColor = AppColors.white,
    Color backgroundColor = AppColors.black,
    List<ButtonOption> options = const [],
    void Function(ButtonOption)? onOptionSelected,
    String? childText,
  }) {
    var finalPadding = padding;

    if (options.isNotEmpty) {
      finalPadding = defaultIconButtonPadding;
    }

    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        padding: finalPadding,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      child: options.isEmpty
          ? child
          : BlocProvider(
              create: (context) => ButtonOptionCubit(
                initial: options.first,
              ),
              child: BlocBuilder<ButtonOptionCubit, ButtonOption>(
                  builder: (context, option) {
                onOptionSelected?.call(option);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (child != null) ...[
                      child,
                      const Gap(8),
                    ],
                    if (childText != null)
                      Text(
                        '$childText ${option.label}',
                      )
                    else
                      Text(
                        option.label,
                      ),
                    const Gap(4),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.arrow_drop_down_rounded),
                      itemBuilder: (context) {
                        return options.map((option) {
                          return PopupMenuItem<String>(
                            value: option.value,
                            child: Text(option.label),
                          );
                        }).toList();
                      },
                      onSelected: (value) {
                        context.read<ButtonOptionCubit>().selectOption(
                              options.singleWhere(
                                  (option) => option.value == value,),
                            );
                      },
                    ),
                  ],
                );
              },),
            ),
    );
  }
}
