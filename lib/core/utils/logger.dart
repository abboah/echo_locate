import 'package:logger/logger.dart';

/// Application-wide logger utility
class AppLogger {
  AppLogger._();

  static Logger? _logger;

  static Logger get instance {
    _logger ??= Logger(
      printer: PrettyPrinter(
        methodCount: 2,
        errorMethodCount: 8,
        lineLength: 80,
        colors: true,
        printEmojis: true,
        dateTimeFormat: DateTimeFormat.dateAndTime,
      ),
    );
    return _logger!;
  }

  static void debug(String message, [Object? error, StackTrace? stackTrace]) {
    instance.log(Level.debug, message);
  }

  static void info(String message, [Object? error, StackTrace? stackTrace]) {
    instance.log(Level.info, message);
  }

  static void warn(String message, [Object? error, StackTrace? stackTrace]) {
    instance.log(Level.warning, message);
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    instance.log(Level.error, message);
  }
}
