import 'report_models.dart';

class ReportCatalog {
  static const List<ReportMetadata> allReports = [
    // 1. Financial Statements (6)
    ReportMetadata(
      id: 'rpt_balance_sheet',
      title: 'Balance Sheet',
      category: ReportCategory.financial,
      description: 'Statement of financial position detailing Assets, Liabilities, and Equity.',
      iconCode: 'account_balance',
    ),
    ReportMetadata(
      id: 'rpt_pnl',
      title: 'Profit & Loss Statement',
      category: ReportCategory.financial,
      description: 'Periodic operating statement of revenues, COGS, expenses, and net profit.',
      iconCode: 'trending_up',
    ),
    ReportMetadata(
      id: 'rpt_trial_balance',
      title: 'Trial Balance',
      category: ReportCategory.financial,
      description: 'Listing of all double-entry ledger accounts verifying debit-credit balance.',
      iconCode: 'balance',
    ),
    ReportMetadata(
      id: 'rpt_general_ledger',
      title: 'General Ledger',
      category: ReportCategory.financial,
      description: 'Comprehensive account-by-account running ledger transaction report.',
      iconCode: 'menu_book',
    ),
    ReportMetadata(
      id: 'rpt_day_book',
      title: 'Day Book',
      category: ReportCategory.financial,
      description: 'Daily chronological journal of all transactions, receipts, and invoices.',
      iconCode: 'calendar_today',
    ),
    ReportMetadata(
      id: 'rpt_cash_flow',
      title: 'Cash Flow Statement',
      category: ReportCategory.financial,
      description: 'Analysis of operating, investing, and financing cash inflows and outflows.',
      iconCode: 'payments',
    ),

    // 2. Statutory & GST Compliance (8)
    ReportMetadata(
      id: 'rpt_gstr1',
      title: 'GSTR-1 Outward Supplies',
      category: ReportCategory.gstCompliance,
      description: 'B2B, B2CL, B2CS, and HSN outward sales return in GSTN JSON format.',
      iconCode: 'file_download',
    ),
    ReportMetadata(
      id: 'rpt_gstr2',
      title: 'GSTR-2 Inward Supplies',
      category: ReportCategory.gstCompliance,
      description: 'Purchase register and inward supplies statement for Input Tax Credit.',
      iconCode: 'input',
    ),
    ReportMetadata(
      id: 'rpt_gstr2a_rec',
      title: 'GSTR-2A Inward Reconciliation',
      category: ReportCategory.gstCompliance,
      description: 'Reconciles purchase books against portal 2A inward feed to identify mismatched ITC.',
      iconCode: 'sync_alt',
    ),
    ReportMetadata(
      id: 'rpt_gstr3b',
      title: 'GSTR-3B Monthly Tax Summary',
      category: ReportCategory.gstCompliance,
      description: 'Monthly statutory tax summary return detailing outward liability and eligible ITC.',
      iconCode: 'fact_check',
    ),
    ReportMetadata(
      id: 'rpt_gstr4',
      title: 'GSTR-4 Composition Return',
      category: ReportCategory.gstCompliance,
      description: 'Quarterly and annual turnover tax return for Composition dealers.',
      iconCode: 'pie_chart',
    ),
    ReportMetadata(
      id: 'rpt_gstr9',
      title: 'GSTR-9 Annual Return Summary',
      category: ReportCategory.gstCompliance,
      description: 'Consolidated annual return aggregating 12-month GSTR-1 and GSTR-3B figures.',
      iconCode: 'assessment',
    ),
    ReportMetadata(
      id: 'rpt_hsn_summary',
      title: 'HSN / SAC Summary Register',
      category: ReportCategory.gstCompliance,
      description: 'Product and service HSN code breakdown with tax rate and taxable valuation.',
      iconCode: 'category',
    ),
    ReportMetadata(
      id: 'rpt_eway_irn_log',
      title: 'e-Way Bill & e-Invoice Master Log',
      category: ReportCategory.gstCompliance,
      description: 'Audit register of 64-char IRNs, signed QR codes, and 12-digit e-Way bills.',
      iconCode: 'qr_code',
    ),

    // 3. Sales & Receivables (6)
    ReportMetadata(
      id: 'rpt_sales_register',
      title: 'Sales Register',
      category: ReportCategory.salesReceivables,
      description: 'Itemized sales ledger grouped by date, voucher, and customer account.',
      iconCode: 'receipt',
    ),
    ReportMetadata(
      id: 'rpt_receivables_aging',
      title: 'Customer Receivables Aging Summary',
      category: ReportCategory.salesReceivables,
      description: 'Aging distribution of outstanding receivables (0-30, 31-60, 61-90, 90+ days).',
      iconCode: 'hourglass_empty',
    ),
    ReportMetadata(
      id: 'rpt_customer_ledger',
      title: 'Customer Ledger Statement',
      category: ReportCategory.salesReceivables,
      description: 'Detailed statement of account for individual customers with running balance.',
      iconCode: 'person',
    ),
    ReportMetadata(
      id: 'rpt_sales_orders',
      title: 'Sales Orders Pending Fulfillment',
      category: ReportCategory.salesReceivables,
      description: 'Open sales orders awaiting conversion or warehouse dispatch.',
      iconCode: 'shopping_cart',
    ),
    ReportMetadata(
      id: 'rpt_quotations',
      title: 'Quotations & Estimates Register',
      category: ReportCategory.salesReceivables,
      description: 'Listing of pending and converted customer estimates and proposals.',
      iconCode: 'request_quote',
    ),
    ReportMetadata(
      id: 'rpt_top_customers',
      title: 'Top Customers & Revenue Velocity',
      category: ReportCategory.salesReceivables,
      description: 'Ranking of customers by volume, invoice count, and net revenue.',
      iconCode: 'leaderboard',
    ),

    // 4. Purchases & Payables (5)
    ReportMetadata(
      id: 'rpt_purchase_register',
      title: 'Purchase Register',
      category: ReportCategory.purchasesPayables,
      description: 'Chronological inward purchase invoices grouped by supplier and tax rate.',
      iconCode: 'shopping_bag',
    ),
    ReportMetadata(
      id: 'rpt_payables_aging',
      title: 'Vendor Payables Aging Summary',
      category: ReportCategory.purchasesPayables,
      description: 'Aging analysis of unpaid supplier bills grouped by due periods.',
      iconCode: 'schedule',
    ),
    ReportMetadata(
      id: 'rpt_vendor_ledger',
      title: 'Vendor Ledger Statement',
      category: ReportCategory.purchasesPayables,
      description: 'Supplier statement of account with purchases and settlement payments.',
      iconCode: 'local_shipping',
    ),
    ReportMetadata(
      id: 'rpt_purchase_orders',
      title: 'Purchase Orders Status Report',
      category: ReportCategory.purchasesPayables,
      description: 'Active PO tracking from vendor order placement to GRN receipt.',
      iconCode: 'inventory_2',
    ),
    ReportMetadata(
      id: 'rpt_expense_analysis',
      title: 'Operating Expense Analysis',
      category: ReportCategory.purchasesPayables,
      description: 'Overhead expense breakdown across utilities, rent, logistics, and payroll.',
      iconCode: 'pie_chart_outline',
    ),

    // 5. Inventory & Warehouse (6)
    ReportMetadata(
      id: 'rpt_stock_summary',
      title: 'Stock Summary & Valuation',
      category: ReportCategory.inventoryWarehouse,
      description: 'Holding quantities, cost valuation, and potential selling value by SKU.',
      iconCode: 'inventory',
    ),
    ReportMetadata(
      id: 'rpt_item_stock_ledger',
      title: 'Item-wise Stock Movement Ledger',
      category: ReportCategory.inventoryWarehouse,
      description: 'Chronological inward, outward, and adjustment stock movements for SKUs.',
      iconCode: 'history',
    ),
    ReportMetadata(
      id: 'rpt_low_stock',
      title: 'Low Stock & Reorder Alert Register',
      category: ReportCategory.inventoryWarehouse,
      description: 'SKUs at or below safety reorder threshold requiring warehouse restock.',
      iconCode: 'warning',
    ),
    ReportMetadata(
      id: 'rpt_stock_ageing',
      title: 'Stock Ageing & Shelf-Life Analysis',
      category: ReportCategory.inventoryWarehouse,
      description: 'Analysis of slow-moving inventory holdings and carrying cost.',
      iconCode: 'timer',
    ),
    ReportMetadata(
      id: 'rpt_fast_moving_items',
      title: 'High-Velocity Fast Moving Items',
      category: ReportCategory.inventoryWarehouse,
      description: 'Inventory sales turnover ratio identifying top-selling items.',
      iconCode: 'speed',
    ),
    ReportMetadata(
      id: 'rpt_stock_adjustments',
      title: 'Stock Adjustment & Wastage Audit',
      category: ReportCategory.inventoryWarehouse,
      description: 'Audit log of manual physical inventory adjustments and recorded wastage.',
      iconCode: 'delete_sweep',
    ),

    // 6. Audit & Governance (5)
    ReportMetadata(
      id: 'rpt_audit_trail',
      title: 'Statutory Audit Trail Log',
      category: ReportCategory.auditGovernance,
      description: 'Cryptographically sealed audit trail tracking all record insertions and edits.',
      iconCode: 'security',
    ),
    ReportMetadata(
      id: 'rpt_voided_vouchers',
      title: 'Voided Transactions & Cancellations',
      category: ReportCategory.auditGovernance,
      description: 'Register of all voided invoices and reversed journal entries.',
      iconCode: 'cancel',
    ),
    ReportMetadata(
      id: 'rpt_user_activity',
      title: 'User Activity & RBAC Access Log',
      category: ReportCategory.auditGovernance,
      description: 'Security log tracking user logins, role elevations, and critical data operations.',
      iconCode: 'admin_panel_settings',
    ),
    ReportMetadata(
      id: 'rpt_multi_company',
      title: 'Multi-Company Consolidation Statement',
      category: ReportCategory.auditGovernance,
      description: 'Aggregated financial performance across all registered enterprise entities.',
      iconCode: 'domain',
    ),
    ReportMetadata(
      id: 'rpt_sync_queue',
      title: 'Offline Sync Outbox Queue Status',
      category: ReportCategory.auditGovernance,
      description: 'Diagnostics report of pending outbox sync mutations and retry attempts.',
      iconCode: 'cloud_sync',
    ),
  ];

  static List<ReportMetadata> getByCategory(ReportCategory category) {
    return allReports.where((r) => r.category == category).toList();
  }

  static ReportMetadata? getById(String id) {
    try {
      return allReports.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }
}
