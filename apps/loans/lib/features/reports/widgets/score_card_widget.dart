import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class ScoreCardWidget extends StatelessWidget {
  const ScoreCardWidget({
    super.key,
    this.headerIcon,
    this.headerTitle,
    this.footerTitle,
    this.onTap,
    this.content,
    this.contentWidget,
    this.subContent,
    this.isContentMoney = false,
    this.contentCentered = true,
    this.footerIcon,
    this.largeMoneyContent = false,
  })  : assert(headerTitle != null || footerTitle != null, 'Please add title'),
        assert(content != null || contentWidget != null, 'Please set content');

  final Widget? headerIcon;
  final String? headerTitle;
  final String? footerTitle;
  final VoidCallback? onTap;
  final String? content;
  final String? subContent;
  final bool isContentMoney;
  final bool largeMoneyContent;
  final bool contentCentered;
  final Widget? footerIcon;
  final Widget? contentWidget;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      constraints: const BoxConstraints(
        minWidth: 264,
        maxHeight: 220,
      ),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: defaultBorderRadius,
      ),
      child: Column(
        crossAxisAlignment: !contentCentered
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          _scoreCardHeader(context),
          const Gap(16),
          _buildContent(),
          if (subContent != null)
            Text(
              subContent!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w200,
              ),
            ),
          if (footerTitle != null) ...[
            const Gap(16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    footerTitle!,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Gap(8),
                if (footerIcon != null)
                  Expanded(
                    child: footerIcon!,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (contentWidget != null) {
      return contentWidget!;
    }

    if (!isContentMoney) {
      return Text(
        content!,
        style: const TextStyle(
          height: 1.1,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: AppWidgets.defaultAmountWidget(
        content!,
        fontSize: largeMoneyContent ? 28 : 20,
        subFontSize: largeMoneyContent ? 16 : 12,
      ),
    );
  }

  Widget _scoreCardHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (headerIcon != null)
          Container(
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(
              maxHeight: 36,
              maxWidth: 36,
            ),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.green1,
            ),
            child: headerIcon,
          ),
        if (headerTitle != null) ...[
          if (headerIcon != null)
            const Gap(8),
          Expanded(
            child: Text(
              headerTitle!,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
        if (onTap != null) ...[
          const Gap(16),
          InkWell(
            borderRadius: BorderRadius.circular(32),
            onTap: onTap,
            child: SvgPicture.asset(
              'svg/icon_arrow_up.svg'.assetSafe,
              width: 24,
              colorFilter: const ColorFilter.mode(
                AppColors.black,
                BlendMode.srcIn,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
