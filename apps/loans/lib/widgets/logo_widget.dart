import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:loooans/l10n/l10n.dart';
import 'package:loooans/utils/extensions.dart';

class LogoWidget extends StatelessWidget {
  const LogoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          'svg/logo.svg'.assetSafe,
          width: 128,
        ),
        Text(
          context.l10n.appName,
          style: const TextStyle(
            fontSize: 64,
          ),
        ),
        Text(
          context.l10n.tagLine,
          style: const TextStyle(
            fontSize: 18,
          ),
        ),
      ],
    );
  }
}
