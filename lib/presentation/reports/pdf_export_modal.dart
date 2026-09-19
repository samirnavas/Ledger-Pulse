import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/colors.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/draggable_modal_sheet.dart';


class PdfExportModal extends StatelessWidget {
  final Uint8List pdfBytes;
  final File file;
  final String fileName;
  final String partyName;
  final String periodLabel;

  const PdfExportModal({
    super.key,
    required this.pdfBytes,
    required this.file,
    required this.fileName,
    required this.partyName,
    required this.periodLabel,
  });

  static Future<void> show({
    required BuildContext context,
    required Uint8List pdfBytes,
    required File file,
    required String fileName,
    required String partyName,
    required String periodLabel,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => PdfExportModal(
        pdfBytes: pdfBytes,
        file: file,
        fileName: fileName,
        partyName: partyName,
        periodLabel: periodLabel,
      ),
    );
  }

  Future<void> _sharePdf(BuildContext context) async {
    HapticFeedback.lightImpact();
    final xFile = XFile(file.path, mimeType: 'application/pdf', name: fileName);
    // ignore: deprecated_member_use
    await Share.shareXFiles(
      [xFile],
      text: 'Ledger Statement for $partyName ($periodLabel)',
      subject: 'Statement - $partyName',
    );
  }

  Future<void> _downloadPdf(BuildContext context) async {
    HapticFeedback.mediumImpact();
    try {
      Directory? targetDir;

      if (Platform.isAndroid) {
        targetDir = Directory('/storage/emulated/0/Download');
        if (!await targetDir.exists()) {
          targetDir = await getExternalStorageDirectory();
        }
      } else if (Platform.isIOS) {
        targetDir = await getApplicationDocumentsDirectory();
      } else {
        targetDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      }

      final savePath = '${targetDir?.path ?? (await getTemporaryDirectory()).path}/$fileName';
      final savedFile = File(savePath);
      await savedFile.writeAsBytes(pdfBytes);

      if (context.mounted) {
        final isDownloads = targetDir?.path.toLowerCase().contains('download') ?? false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Saved to ${isDownloads ? 'Downloads' : 'Documents'}: $fileName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.receivableGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save file: $e'),
            backgroundColor: AppColors.payableRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      snap: true,
      snapSizes: const [0.5, 0.85, 0.95],
      snapAnimationDuration: const Duration(milliseconds: 250),
      shouldCloseOnMinExtent: true,
      expand: false,
      builder: (context, scrollController) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Container(
              decoration: BoxDecoration(
                color: isIos
                    ? (isDark ? const Color(0xFF1C1C1E) : CupertinoColors.systemBackground)
                    : Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const ModalDragHandle(
                    margin: EdgeInsets.only(top: 10, bottom: 4),
                  ),

                  // Header Bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                    child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.picture_as_pdf_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Account Statement PDF',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$partyName • $periodLabel',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        isIos ? CupertinoIcons.xmark_circle_fill : Icons.close_rounded,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, thickness: 1),

              // PDF Preview Body
              Expanded(
                child: ClipRRect(
                  child: Container(
                    color: isDark ? const Color(0xFF121212) : const Color(0xFFF3F4F6),
                    child: PdfPreview(
                      build: (format) async => pdfBytes,
                      allowPrinting: false,
                      allowSharing: false,
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      canDebug: false,
                      maxPageWidth: 580,
                      loadingWidget: const Center(
                        child: CupertinoActivityIndicator(radius: 14),
                      ),
                    ),
                  ),
                ),
              ),

              const Divider(height: 1, thickness: 1),

              // Action Buttons Bar (1. Share, 2. Download)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                child: Row(
                  children: [
                    // 1. Share Button
                    Expanded(
                      child: AdaptiveButton(
                        onPressed: () => _sharePdf(context),
                        type: AdaptiveButtonType.secondary,
                        height: 50,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isIos ? CupertinoIcons.share : Icons.share_rounded,
                              size: 19,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Share',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // 2. Download Button
                    Expanded(
                      child: AdaptiveButton(
                        onPressed: () => _downloadPdf(context),
                        type: AdaptiveButtonType.primary,
                        height: 50,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isIos ? CupertinoIcons.arrow_down_to_line : Icons.download_rounded,
                              size: 19,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Download',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  },
);

  }
}
