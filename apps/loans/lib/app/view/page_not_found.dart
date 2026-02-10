import 'package:flutter/material.dart';
import 'package:loooans/l10n/l10n.dart';

class PageNotFound extends StatelessWidget {
  const PageNotFound({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      body: Center(
        child: Text(l10n.pageNotFound),
      ),
    );
  }

}
