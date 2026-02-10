import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:gap/gap.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';

class TransactionsWidget extends StatelessWidget {
  const TransactionsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header(),
        const Gap(16),
        Expanded(
          child: _body(),
        ),
      ],
    );
  }

  static Widget header({
    bool maxAxisSize = false,
  }) {
    return Row(
      mainAxisSize: !maxAxisSize ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: !maxAxisSize ? MainAxisAlignment.start : MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Transactions',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.white,),
        ),
        const Gap(8),
        SvgPicture.asset(
          'svg/icon_arrow_up.svg'.assetSafe,
          colorFilter: const ColorFilter.mode(
            AppColors.white,
            BlendMode.srcIn,
          ),
        ),
      ],
    );
  }

  Widget _body() {
    return ListView.separated(
      itemBuilder: (context, index) {
        return transactionItem();
      },
      separatorBuilder: (context, index) {
        return const Divider(
          color: AppColors.white,
        );
      },
      itemCount: 10,
    );
  }

  static Widget transactionItem({ bool isLast = false,}) {
    const style = TextStyle(
      color: AppColors.white,
      fontSize: 12,
      fontWeight: FontWeight.w300,
    );
    return Padding(
      padding: !isLast ? EdgeInsets.zero : const EdgeInsets.only(bottom: 56),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 6,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateTime.now().toDefaultDateFormatWithDay(),
                  style: style,
                ),
                const Gap(16),
                Expanded(
                  child: Text(
                    'Paid ${1234.43.toCurrency()} to IzzyLoans. $isLast',
                    style: style,
                  ),
                ),
              ],
            ),
          ),
          const Text(
            'karma +0.01',
            style: style,
          ),
        ],
      ),
    );
  }
}
