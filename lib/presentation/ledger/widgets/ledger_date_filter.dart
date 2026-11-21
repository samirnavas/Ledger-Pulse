import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/adaptive_theme.dart';

Future<DateTimeRange?> pickLedgerDates(
  BuildContext context, {
  DateTimeRange? initial,
}) {
  final first = DateTime(1900);
  final last = DateTime(2100);
  if (!AdaptiveThemeHelper.isIos(context)) {
    return showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDateRange: initial,
    );
  }

  var start = initial?.start ?? DateUtils.dateOnly(DateTime.now());
  var end = initial?.end ?? start;
  var editingStart = true;
  return showCupertinoModalPopup<DateTimeRange>(
    context: context,
    builder: (popupContext) => StatefulBuilder(
      builder: (context, setSheetState) => CupertinoPopupSurface(
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    onPressed: () => Navigator.pop(popupContext),
                    child: const Text('Cancel'),
                  ),
                  CupertinoButton(
                    onPressed: () => Navigator.pop(
                      popupContext,
                      DateTimeRange(start: start, end: end),
                    ),
                    child: const Text('Apply'),
                  ),
                ],
              ),
              CupertinoSlidingSegmentedControl<bool>(
                groupValue: editingStart,
                children: const {true: Text('From'), false: Text('To')},
                onValueChanged: (value) {
                  if (value != null) setSheetState(() => editingStart = value);
                },
              ),
              SizedBox(
                height: 200,
                child: CupertinoDatePicker(
                  key: ValueKey(editingStart),
                  mode: CupertinoDatePickerMode.date,
                  minimumDate: first,
                  maximumDate: last,
                  initialDateTime: editingStart ? start : end,
                  onDateTimeChanged: (date) => setSheetState(() {
                    final day = DateUtils.dateOnly(date);
                    if (editingStart) {
                      start = day;
                      if (end.isBefore(start)) end = start;
                    } else {
                      end = day;
                      if (start.isAfter(end)) start = end;
                    }
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
