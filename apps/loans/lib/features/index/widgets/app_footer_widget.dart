import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/index/widgets/app_title_widget.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/link.dart';

class AppFooterWdiget extends StatelessWidget {
  const AppFooterWdiget({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'svg/logo.svg'.assetSafe,
              width: 56,
            ),
            const Gap(16),
            const AppTitleWidget(
              includeSignUpButton: false,
              appNameFontSize: 64,
              tagLineFontSize: 16,
            ),
          ],
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Link(
              uri: Uri.parse('https://fb.com/loooans.official'),
              builder: (context, followLink) {
                return _iconLabel(
                  'svg/facebook.svg',
                  'https://fb.com/loooans.official',
                  onTap: followLink,
                );
              },
            ),
            const Gap(8),
            Link(
              uri: Uri.parse(
                'mailto:support@anaheimtechnologies.com?subject=Hello',
              ),
              builder: (context, openLink) {
                return _iconLabel(
                  'svg/email.svg',
                  'support@anaheimtechnologies.com',
                  onTap: openLink,
                );
              },
            ),
            const Gap(8),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Text(
                    'v${snapshot.data!.version}',
                    style: const TextStyle(fontSize: 12),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _iconLabel(
    String iconAssetName,
    String label, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      splashColor: Colors.transparent,
      hoverColor: Colors.transparent,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            iconAssetName.assetSafe,
            width: 16,
          ),
          const Gap(4),
          Text(label),
        ],
      ),
    );
  }
}
