import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

class MyLogger {
  /// call to initialize logger printing
  static void initializeLogger({ Level logLevel = Level.ALL}) {
    Logger.root.level = logLevel;
    Logger.root.onRecord.listen((record) {
      debugPrint('[${record.loggerName}] [${record.level.name}]: ${record.time}: ${record.message}');
    });
  }
}