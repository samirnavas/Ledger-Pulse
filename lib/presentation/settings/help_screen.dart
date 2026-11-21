import 'package:flutter/material.dart';

import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/adaptive_surface_card.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key, required this.isExpense});

  final bool isExpense;

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      title: 'Help',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AdaptiveSurfaceCard(
                padding: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    children: [
                      if (isExpense) ...[
                        const _HelpTopic(
                          question: 'How do I add or find a transaction?',
                          answer:
                              'Tap Add transaction on Home or Transactions '
                              'and choose Expense, Income, or Transfer. Open '
                              'Transactions to search or filter saved entries.',
                        ),
                        const _HelpTopic(
                          question: 'Where do I manage wallets and categories?',
                          answer:
                              'Open My Account from the top-right button. '
                              'Choose Wallet for cash, bank accounts, and cards, '
                              'or Category to organize income and expenses.',
                        ),
                        const _HelpTopic(
                          question: 'Where can I see my spending?',
                          answer:
                              'Open Reports to review spending and income. '
                              'When Budgets is enabled for your workspace, open '
                              'Budgets to set and track spending limits.',
                        ),
                      ] else ...[
                        const _HelpTopic(
                          question:
                              'How do I get started with Business Ledger?',
                          answer:
                              'Add a customer or supplier from the '
                              'Dashboard. Open their account to record a '
                              'transaction or review their balance.',
                        ),
                        const _HelpTopic(
                          question: 'Where do I find business reports?',
                          answer:
                              'Open the navigation menu to find reporting '
                              'tools for your ledger. Available reports depend '
                              'on the modules enabled for your company.',
                        ),
                      ],
                      const _HelpTopic(
                        question: 'How do I switch workspaces?',
                        answer:
                            'Tap the active workspace name in the Home or '
                            'Dashboard header and choose the workspace to open.',
                      ),
                      const _HelpTopic(
                        question: 'How do I sync my records?',
                        answer:
                            'Open Settings, choose Cloud Sync & Backup Hub, '
                            'and tap Sync Now. If sync fails, check your '
                            'connection and try again.',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpTopic extends StatelessWidget {
  const _HelpTopic({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(question),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [Text(answer)],
    );
  }
}
