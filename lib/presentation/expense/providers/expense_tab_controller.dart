import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State representing the expense shell's active tab and custom actions.
class ExpenseTabState {
  final int currentIndex;
  final VoidCallback? customPrimaryAction;
  final String? customPrimaryLabel;
  final List<Widget>? customActions;

  const ExpenseTabState({
    this.currentIndex = 0,
    this.customPrimaryAction,
    this.customPrimaryLabel,
    this.customActions,
  });

  ExpenseTabState copyWith({
    int? currentIndex,
    VoidCallback? Function()? customPrimaryAction,
    String? Function()? customPrimaryLabel,
    List<Widget>? Function()? customActions,
  }) {
    return ExpenseTabState(
      currentIndex: currentIndex ?? this.currentIndex,
      customPrimaryAction: customPrimaryAction != null
          ? customPrimaryAction()
          : this.customPrimaryAction,
      customPrimaryLabel: customPrimaryLabel != null
          ? customPrimaryLabel()
          : this.customPrimaryLabel,
      customActions:
          customActions != null ? customActions() : this.customActions,
    );
  }
}

/// Controller managing active tab index and actions for ExpenseHomeScreen.
class ExpenseTabController extends Notifier<ExpenseTabState> {
  @override
  ExpenseTabState build() => const ExpenseTabState(currentIndex: 0);

  void setTab(int index) {
    state = ExpenseTabState(currentIndex: index);
  }

  void setPrimaryAction(VoidCallback? action, [String? label]) {
    state = state.copyWith(
      customPrimaryAction: () => action,
      customPrimaryLabel: () => label,
    );
  }

  void setCustomActions(List<Widget>? actions) {
    state = state.copyWith(
      customActions: () => actions,
    );
  }
}

final expenseTabControllerProvider =
    NotifierProvider<ExpenseTabController, ExpenseTabState>(
  ExpenseTabController.new,
);
