import 'package:flutter/material.dart';

class ForceDownloadAppScreen extends StatelessWidget {
  const ForceDownloadAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('We detected that you are running the app on a mobile browswer. Please download app in playstore or app store'),
      ),
    );
  }

}