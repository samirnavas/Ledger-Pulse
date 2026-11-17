import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/utils/adaptive_page_route.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/adaptive_surface_card.dart';
import '../../core/widgets/amount_text.dart';
import '../../data/models/voucher_model.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';

class TransactionDetailsScreen extends ConsumerWidget {
  final VoucherModel transaction;

  const TransactionDetailsScreen({super.key, required this.transaction});

  static void show(BuildContext context, VoucherModel transaction) {
    Navigator.of(context).push(
      createAdaptivePageRoute(
        builder: (_) => TransactionDetailsScreen(transaction: transaction),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final categories = ref.watch(categoriesProvider).asData?.value;
    final wallets = ref.watch(walletsProvider).asData?.value;
    final company = ref.watch(activeCompanyProvider);
    final category = categories
        ?.where((c) => c.id == transaction.categoryAccountId)
        .firstOrNull;
    final wallet = wallets
        ?.where((w) => w.id == transaction.walletAccountId)
        .firstOrNull;
    final destination = wallets
        ?.where((w) => w.id == transaction.toWalletAccountId)
        .firstOrNull;
    final transfer = transaction.type == VoucherType.transfer;
    final receipt = transaction.receiptPhotoUrl?.trim();

    Widget detail(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );

    return AdaptiveScaffold(
      title: 'Transaction details',
      body: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AdaptiveSurfaceCard(
                child: Column(
                  children: [
                    Text(
                      transfer
                          ? 'Transfer'
                          : transaction.type == VoucherType.income
                          ? 'Income'
                          : 'Expense',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: AmountText(
                        amountInCents: transaction.totalAmountInCents,
                        currencyCode: company.currencyCode,
                        variant: AmountVariant.large,
                        overrideColor: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      transaction.status.displayName,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AdaptiveSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    detail(
                      'Date',
                      DateFormat.yMMMd().add_jm().format(transaction.date),
                    ),
                    if (!transfer)
                      detail('Category', category?.name ?? 'Uncategorized'),
                    detail(
                      transfer ? 'From wallet' : 'Wallet',
                      wallet?.name ?? 'Unavailable',
                    ),
                    if (transfer)
                      detail('To wallet', destination?.name ?? 'Unavailable'),
                    if (transaction.referenceNumber?.trim().isNotEmpty ?? false)
                      detail('Reference', transaction.referenceNumber!),
                    if (transaction.narration?.trim().isNotEmpty ?? false)
                      detail('Note', transaction.narration!),
                    detail('Transaction number', transaction.voucherNumber),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('Invoice / receipt', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              AdaptiveSurfaceCard(
                key: const Key('transaction_invoice_section'),
                child: receipt == null || receipt.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: Text('No invoice attached')),
                      )
                    : Column(
                        children: [
                          SizedBox(
                            height: 320,
                            width: double.infinity,
                            child: InteractiveViewer(
                              minScale: 1,
                              maxScale: 5,
                              child: _InvoiceImage(source: receipt),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Pinch to zoom',
                            style: theme.textTheme.bodySmall,
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

class _InvoiceImage extends StatelessWidget {
  final String source;

  const _InvoiceImage({required this.source});

  @override
  Widget build(BuildContext context) {
    Widget unavailable(BuildContext context, Object error, StackTrace? stack) =>
        const Center(child: Text('Invoice unavailable on this device'));
    final uri = Uri.tryParse(source);
    if (uri?.scheme == 'https' || uri?.scheme == 'http') {
      return Image.network(
        source,
        fit: BoxFit.contain,
        errorBuilder: unavailable,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const Center(child: CircularProgressIndicator()),
      );
    }
    return Image.file(
      uri?.scheme == 'file' ? File.fromUri(uri!) : File(source),
      fit: BoxFit.contain,
      errorBuilder: unavailable,
    );
  }
}
