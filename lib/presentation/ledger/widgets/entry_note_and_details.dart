import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/adaptive_theme.dart';
import '../../../core/utils/date_formatter.dart';

/// Note text field and Date / Attach Receipt action buttons.
class EntryNoteAndDetails extends StatelessWidget {
  final TextEditingController noteController;
  final DateTime selectedDate;
  final String? receiptUrl;
  final Color themeColor;
  final VoidCallback onPickDate;
  final VoidCallback onOpenAttachmentPicker;

  const EntryNoteAndDetails({
    super.key,
    required this.noteController,
    required this.selectedDate,
    required this.receiptUrl,
    required this.themeColor,
    required this.onPickDate,
    required this.onOpenAttachmentPicker,
  });

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Entry name text box
        TextFormField(
          controller: noteController,
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          decoration: InputDecoration(
            labelText: 'Entry name',
            labelStyle: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            hintText: 'e.g. Chai, Lunch, Bill #104, Quality...',
            hintStyle: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            prefixIcon: Icon(
              isIos ? CupertinoIcons.tag : Icons.label_outline_rounded,
              size: 20,
              color: themeColor,
            ),
            suffixIcon: noteController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () => noteController.clear(),
                  )
                : null,
            filled: true,
            fillColor: isDark
                ? const Color(0xFF141414)
                : Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.4),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: isDark
                    ? const Color(0xFF282828)
                    : Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: isDark
                    ? const Color(0xFF282828)
                    : Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.6),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: themeColor,
                width: 1.5,
              ),
            ),
            isDense: true,
          ),
        ),

        const SizedBox(height: 8),

        // Date & Attach Receipt row
        Row(
          children: [
            // Date Chip
            OutlinedButton.icon(
              onPressed: onPickDate,
              icon: Icon(
                isIos ? CupertinoIcons.calendar : Icons.calendar_today_rounded,
                size: 14,
              ),
              label: Text(
                DateFormatter.formatRelative(selectedDate),
                style: const TextStyle(fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: const Size(0, 36),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Attach Bill Button
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onOpenAttachmentPicker,
                icon: Icon(
                  receiptUrl != null
                      ? (isIos
                          ? CupertinoIcons.checkmark_circle_fill
                          : Icons.check_circle_rounded)
                      : (isIos
                          ? CupertinoIcons.camera
                          : Icons.camera_alt_outlined),
                  size: 14,
                  color: receiptUrl != null
                      ? AppColors.primaryBlue
                      : AppColors.textSecondaryLight,
                ),
                label: Text(
                  receiptUrl != null ? 'Bill Attached' : 'Attach Bill',
                  style: TextStyle(
                    fontSize: 12,
                    color: receiptUrl != null
                        ? AppColors.primaryBlue
                        : AppColors.textSecondaryLight,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: const Size(0, 36),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
