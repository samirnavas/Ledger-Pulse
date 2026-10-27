import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/adaptive_theme.dart';

/// Shows an adaptive attachment picker bottom sheet / action sheet.
Future<void> showEntryAttachmentPicker({
  required BuildContext context,
  required String? currentReceiptUrl,
  required ValueChanged<String?> onReceiptChanged,
}) async {
  HapticFeedback.lightImpact();
  final isIos = AdaptiveThemeHelper.isIos(context);

  Future<void> pickImage(ImageSource source) async {
    HapticFeedback.lightImpact();
    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (photo != null) {
        onReceiptChanged(photo.path);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Receipt attached successfully!'),
              backgroundColor: AppColors.primaryBlue,
              duration: Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to attach image: $e'),
            backgroundColor: AppColors.payableRed,
          ),
        );
      }
    }
  }

  if (isIos) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Attach Bill / Receipt'),
        message: const Text('Select an image source for this transaction receipt'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(ctx).pop();
              pickImage(ImageSource.camera);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.camera, size: 20),
                SizedBox(width: 8),
                Text('Take Photo'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(ctx).pop();
              pickImage(ImageSource.gallery);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.photo, size: 20),
                SizedBox(width: 8),
                Text('Choose from Gallery'),
              ],
            ),
          ),
          if (currentReceiptUrl != null)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.of(ctx).pop();
                onReceiptChanged(null);
              },
              child: const Text('Remove Receipt'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  } else {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      enableDrag: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      barrierColor: Colors.black.withValues(alpha: 0.35),
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
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Attach Bill / Receipt',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: AppColors.primaryBlue),
                title: const Text('Take Photo', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: AppColors.primaryBlue),
                title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  pickImage(ImageSource.gallery);
                },
              ),
              if (currentReceiptUrl != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: AppColors.payableRed),
                  title: const Text(
                    'Remove Receipt',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.payableRed,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onReceiptChanged(null);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
