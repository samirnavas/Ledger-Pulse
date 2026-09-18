import 'package:intl/intl.dart';

class DateFormatter {
  static String formatRelative(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(date.year, date.month, date.day);

    final differenceInDays = today.difference(itemDate).inDays;

    if (differenceInDays == 0) {
      return 'Today';
    } else if (differenceInDays == 1) {
      return 'Yesterday';
    } else if (differenceInDays < 7 && differenceInDays > 0) {
      return DateFormat('EEEE').format(date); // e.g. "Monday"
    } else if (date.year == now.year) {
      return DateFormat('d MMM').format(date); // e.g. "14 Sep"
    } else {
      return DateFormat('d MMM yyyy').format(date);
    }
  }

  static String formatTime(DateTime date) {
    return DateFormat('hh:mm a').format(date);
  }

  static String formatFull(DateTime date) {
    return DateFormat('d MMMM yyyy').format(date);
  }

  static String formatShortDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  /// Generates a group header string for timeline grouping
  static String getTimelineGroupHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(date.year, date.month, date.day);

    final diff = today.difference(itemDate).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (date.year == now.year) {
      return DateFormat('MMMM yyyy').format(date);
    }
    return DateFormat('MMMM yyyy').format(date);
  }
}
