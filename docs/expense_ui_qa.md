# LedgerPulse Expense Tracker Mode – Manual QA Checklist

This manual QA checklist provides step-by-step verification instructions for testing the Expense Tracker mode UI across Android (API 34+) and iOS platforms.

---

## 1. Predictive Back & Navigation (Android 14+ & iOS)

### Android 14+ Predictive Back Gesture
- [ ] **Home Shell Tab Navigation**:
  - Open app in Expense Tracker mode on an Android 14+ device or emulator.
  - Navigate to Transactions (Tab 1), Budgets (Tab 2), Reports (Tab 3), or Accounts (Tab 4).
  - Perform the back gesture from the edge.
  - **Expected**: PopScope intercepts back gesture, executes smooth predictive animation, and returns active tab to Home (Tab 0) with `HapticFeedback.lightImpact()`.
- [ ] **Modal Bottom Sheets**:
  - Open Quick-Add Transaction Sheet, Filter Modal, or Export Sheet.
  - Perform back gesture.
  - **Expected**: Sheet smoothly shrinks and dismisses with predictive back animation without leaving orphaned backdrop overlays.
- [ ] **Pushed Screens**:
  - Navigate to Recurring Rules screen (`RecurringScreen`).
  - Perform back gesture.
  - **Expected**: Predictive back reveals Home Shell under scaling screen card.

### iOS Edge-Swipe Back Gesture
- [ ] **Pushed Route Edge Swipe**:
  - Open `RecurringScreen` or `SettingsScreen` on iOS.
  - Perform edge swipe from left border.
  - **Expected**: Smooth interactive pop transition driven by `createAdaptivePageRoute`.

---

## 2. iOS Glass Tab Bar & Visual Presentation

- [ ] **Glass Tab Bar Blur Over Scrolling Content**:
  - Scroll through long transaction lists or report screens on iOS.
  - **Expected**: Frosted glass tab bar reflects background content with real-time blur and translucent system background tints.
- [ ] **AMOLED Pure Black Dark Mode**:
  - Enable system Dark Mode.
  - **Expected**: Surfaces render in sleek OLED black (`#000000` / `#141414`) with elevated cards using subtle outline borders (`outlineVariant`).
- [ ] **Large Font Scaling & Small Screen Layouts**:
  - Set system text scale to 1.3x and viewport width to 320 px.
  - **Expected**: No render overflow errors across Home metrics cards, Quick-Add keypad, Category breakdown donut chart, or CSV import preview rows.

---

## 3. Sidebar Drawer & Navigation

- [ ] **Sidebar Drawer on Android & iOS**:
  - Tap top-left navigation drawer button or drag from left edge.
  - **Expected**: Drawer opens with company logo/header, mode badge (`EXPENSE`), and links (Home, Transactions, Budgets, Reports, Accounts, Settings, Modules, Sync & Backup, Subscription, Recurring, CSV Export).
- [ ] **Upgrade to Business Ledger Flow**:
  - In drawer, tap "Upgrade to Business Ledger" or "Switch Mode".
  - **Expected**: Shows confirmation dialog or company mode toggle.
- [ ] **Company Switcher Shell Swap**:
  - Switch active company from an Expense Tracker company to a Business Ledger company.
  - **Expected**: App shell cleanly transitions from `ExpenseHomeScreen` to `DashboardScreen` (and vice-versa) with zero state leakage.

---

## 4. Offline & Sync Indicators

- [ ] **Cloud Sync Status**:
  - Perform transaction addition or category edit while connected to network.
  - **Expected**: Sync indicator in top toolbar animates showing active cloud sync.
- [ ] **Offline Resilience**:
  - Enable Airplane mode and record new expense transactions.
  - **Expected**: Transaction saves locally instantly with optimistic balance update; pending sync counter increments smoothly.

---

## 5. Report Export & CSV Import Sheets

- [ ] **Toolbar Export Action**:
  - On Reports tab, tap Export icon in top app bar / nav bar.
  - **Expected**: `showAdaptiveFormSheet` displays CSV and PDF export options as `AdaptiveListRow`s (no Material `ListTile`s).
- [ ] **CSV Import Multi-Step Sheet**:
  - Trigger CSV import.
  - **Expected**:
    1. Step 1 (Column Mapping) with `AdaptiveDropdownField`s.
    2. Step 2 (Preview) with `AdaptiveListRow`s and summary badges.
    3. Step 3 (Import) with `AdaptiveButton` loading indicator and result feedback via `showAppFeedback`.
