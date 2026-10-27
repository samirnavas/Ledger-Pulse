import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/adaptive_theme.dart';
import '../../../data/models/party_model.dart';

/// Shows adaptive context menu for a party (CupertinoActionSheet on iOS, M3 bottom sheet on Android).
void showPartyContextMenu({
  required BuildContext context,
  required Party party,
  required VoidCallback onEditParty,
  required VoidCallback onDeleteParty,
}) {
  HapticFeedback.mediumImpact();
  final isIos = AdaptiveThemeHelper.isIos(context);

  if (isIos) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(party.name),
        message: Text(party.phoneNumber),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(ctx).pop();
              onEditParty();
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.pencil, size: 20),
                SizedBox(width: 8),
                Text('Edit Details'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.of(ctx).pop();
              onDeleteParty();
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.trash, size: 20),
                SizedBox(width: 8),
                Text('Delete Party'),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  } else {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: colorScheme.surfaceContainerHighest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      party.name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      party.phoneNumber,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(isIos ? CupertinoIcons.pencil : Icons.edit_outlined),
                      title: const Text(
                        'Edit Details',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        onEditParty();
                      },
                    ),
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: 56,
                      endIndent: 16,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                    ListTile(
                      leading: Icon(
                        isIos ? CupertinoIcons.trash : Icons.delete_outline,
                        color: colorScheme.error,
                      ),
                      title: Text(
                        'Delete Party',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.error,
                        ),
                      ),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                      ),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        onDeleteParty();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
