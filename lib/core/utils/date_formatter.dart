import 'package:intl/intl.dart';

class DateFormatter {
  static String formatRelative(DateTime date) {
    final local = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(local.year, local.month, local.day);

    final differenceInDays = today.difference(itemDate).inDays;

    if (differenceInDays == 0) {
      return 'Today';
    } else if (differenceInDays == 1) {
      return 'Yesterday';
    } else if (differenceInDays < 7 && differenceInDays > 0) {
      return DateFormat('EEEE').format(local); // e.g. "Monday"
    } else if (local.year == now.year) {
      return DateFormat('d MMM').format(local); // e.g. "14 Sep"
    } else {
      return DateFormat('d MMM yyyy').format(local);
    }
  }

  static String formatTime(DateTime date) {
    return DateFormat('hh:mm a').format(date.toLocal());
  }

  static String formatFull(DateTime date) {
    return DateFormat('d MMMM yyyy').format(date.toLocal());
  }

  static String formatShortDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date.toLocal());
  }

  static String formatShortDateTime(DateTime date) {
    return DateFormat('dd/MM/yyyy, hh:mm a').format(date.toLocal());
  }

  static String formatRelativeWithTime(DateTime date) {
    final local = date.toLocal();
    return '${formatRelative(local)}, ${formatTime(local)}';
  }

  /// Generates a group header string for timeline grouping
  static String getTimelineGroupHeader(DateTime date) {
    final local = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(local.year, local.month, local.day);

    final diff = today.difference(itemDate).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('MMMM yyyy').format(local);
  }
}
