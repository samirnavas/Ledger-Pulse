import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/typography.dart';
import '../../../core/theme/adaptive_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/transaction_model.dart';

/// Animated chronological ledger stream with grouping, running balance, and receipt button.
class AnimatedPartyLedgerList extends StatefulWidget {
  final List<LedgerEntry> entries;
  final bool isIos;
  final void Function(BuildContext, LedgerEntry) onShowReceipt;
  final void Function(BuildContext, LedgerEntry) onOpenVoucher;

  const AnimatedPartyLedgerList({
    super.key,
    required this.entries,
    required this.isIos,
    required this.onShowReceipt,
    required this.onOpenVoucher,
  });

  @override
  State<AnimatedPartyLedgerList> createState() =>
      _AnimatedPartyLedgerListState();
}

class _AnimatedPartyLedgerListState extends State<AnimatedPartyLedgerList> {
  final Set<String> _knownEntryIds = {};
  final Set<String> _newlyAddedEntryIds = {};

  @override
  void initState() {
    super.initState();
    for (final e in widget.entries) {
      _knownEntryIds.add(e.id);
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedPartyLedgerList oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final e in widget.entries) {
      if (!_knownEntryIds.contains(e.id)) {
        _knownEntryIds.add(e.id);
        _newlyAddedEntryIds.add(e.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        0,
        4,
        0,
        110 + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: widget.entries.length,
      itemBuilder: (context, index) {
        final entry = widget.entries[index];
        final isGave = entry.type == EntryType.gave;
        final color = isGave ? AppColors.payableRed : AppColors.receivableGreen;
        final isNew = _newlyAddedEntryIds.contains(entry.id);

        // Check if group header should be shown (grouping by date)
        final showHeader =
            index == 0 ||
            DateFormatter.formatRelative(widget.entries[index - 1].date) !=
                DateFormatter.formatRelative(entry.date);

        final Widget plainRowContent = Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              widget.onOpenVoucher(context, entry);
            },
            onLongPress: () {
              HapticFeedback.lightImpact();
              widget.onOpenVoucher(context, entry);
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: _buildRowContent(context, entry, isGave, color),
            ),
          ),
        );

        Widget rowWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeader) ...[
              Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: index == 0 ? 6 : 14,
                  bottom: 4,
                ),
                child: Text(
                  DateFormatter.formatRelative(entry.date),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
            _HighlightedLedgerCard(
              key: ValueKey('highlight_${entry.id}'),
              isNew: isNew,
              highlightColor: color,
              onHighlightComplete: () {
                _newlyAddedEntryIds.remove(entry.id);
              },
              child: plainRowContent,
            ),
            Divider(
              height: 1,
              thickness: 0.5,
              indent: 16,
              endIndent: 16,
              color: Theme.of(context).colorScheme.outlineVariant.withValues(
                    alpha: isDark ? 0.2 : 0.35,
                  ),
            ),
          ],
        );

        if (isNew) {
          rowWidget = rowWidget
              .animate(key: ValueKey('anim_${entry.id}'))
              .fadeIn(duration: 300.ms, curve: Curves.easeOut)
              .slideY(
                begin: -0.35,
                end: 0,
                duration: 300.ms,
                curve: Curves.easeOutCubic,
              );
        }

        return rowWidget;
      },
    );
  }

  Widget _buildRowContent(
    BuildContext context,
    LedgerEntry entry,
    bool isGave,
    Color color,
  ) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final effectiveColor =
        entry.isVoided ? color.withValues(alpha: 0.45) : color;

    return Row(
      children: [
        // Note & Timestamp & Optional Bill Icon
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      entry.note ?? (isGave ? 'You Gave' : 'You Got'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: entry.isVoided
                            ? Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.45)
                            : Theme.of(context).colorScheme.onSurface,
                        decoration: entry.isVoided
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (entry.isVoided) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.payableRed.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'VOID',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: AppColors.payableRed,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Text(
                    DateFormatter.formatTime(entry.date),
                    style: AppTypography.labelSmall.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (entry.receiptPhotoUrl != null) ...[
                    const SizedBox(width: 8),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          widget.onShowReceipt(context, entry);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Ink(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.25),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isIos ? CupertinoIcons.doc_text : Icons.receipt_long_rounded,
                                size: 13,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Bill',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Icon(
                                isIos ? CupertinoIcons.arrow_up_right : Icons.open_in_new_rounded,
                                size: 11,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

        // Amount & Running Balance Indicator
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${isGave ? "-" : "+"} ${CurrencyFormatter.format(entry.amountInCents)}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: effectiveColor,
                decoration: entry.isVoided ? TextDecoration.lineThrough : null,
              ),
            ),
            if (entry.runningBalanceInCents != null) ...[
              const SizedBox(height: 2),
              Text(
                'Bal: ${CurrencyFormatter.format(entry.runningBalanceInCents!)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _HighlightedLedgerCard extends StatefulWidget {
  final Widget child;
  final bool isNew;
  final Color highlightColor;
  final VoidCallback? onHighlightComplete;

  const _HighlightedLedgerCard({
    super.key,
    required this.child,
    required this.isNew,
    required this.highlightColor,
    this.onHighlightComplete,
  });

  @override
  State<_HighlightedLedgerCard> createState() => _HighlightedLedgerCardState();
}

class _HighlightedLedgerCardState extends State<_HighlightedLedgerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    if (widget.isNew) {
      _controller.forward().then((_) {
        widget.onHighlightComplete?.call();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isNew) return widget.child;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final flashAlpha = (1.0 - _animation.value) * 0.28;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: widget.highlightColor.withValues(alpha: flashAlpha),
            border: flashAlpha > 0.05
                ? Border.all(
                    color: widget.highlightColor.withValues(
                      alpha: flashAlpha * 1.5,
                    ),
                    width: 1.5,
                  )
                : null,
            boxShadow: flashAlpha > 0.05
                ? [
                    BoxShadow(
                      color: widget.highlightColor.withValues(
                        alpha: flashAlpha * 0.4,
                      ),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
