import 'dart:async';

import 'package:flutter/material.dart';
import 'package:loooans/utils/extensions.dart';

class CountdownText extends StatefulWidget {

  const CountdownText({required this.expireAt, super.key });
  final DateTime expireAt;

  @override
  State<StatefulWidget> createState() {
    return _CountdownTextState();
  }

}

class _CountdownTextState extends State<CountdownText> {
  late Duration remainingTime;

  Timer? timer;

  @override
  void initState() {
    super.initState();

    remainingTime = widget.expireAt.difference(DateTime.now());

    timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        remainingTime = Duration(seconds: remainingTime.inSeconds - 1);

        if (remainingTime.inSeconds == 0) {
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text('Remaining: ${remainingTime.formattedMinutes()}');
  }

}