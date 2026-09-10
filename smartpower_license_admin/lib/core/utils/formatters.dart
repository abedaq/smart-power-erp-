import 'package:intl/intl.dart';

class AppFormatters {
  static String formatDate(DateTime? date) {
    if (date == null) return 'غير محدد';
    return DateFormat('yyyy-MM-dd', 'en_US').format(date);
  }

  static String formatDateTime(DateTime? date) {
    if (date == null) return 'غير محدد';
    return DateFormat('yyyy-MM-dd HH:mm', 'en_US').format(date);
  }

  static String formatNumber(num number) {
    return NumberFormat('#,##0', 'en_US').format(number);
  }

  static int daysRemaining(DateTime? expiresAt) {
    if (expiresAt == null) return 0;
    final diff = expiresAt.difference(DateTime.now()).inDays;
    return diff > 0 ? diff : 0;
  }

  static bool isExpired(DateTime? expiresAt) {
    if (expiresAt == null) return true;
    return DateTime.now().isAfter(expiresAt);
  }
}
