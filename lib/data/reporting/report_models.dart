enum ReportCategory {
  financial,
  gstCompliance,
  salesReceivables,
  purchasesPayables,
  inventoryWarehouse,
  auditGovernance,
  customSql;

  String get displayName {
    switch (this) {
      case ReportCategory.financial:
        return 'Financial Statements';
      case ReportCategory.gstCompliance:
        return 'GST & Statutory';
      case ReportCategory.salesReceivables:
        return 'Sales & Receivables';
      case ReportCategory.purchasesPayables:
        return 'Purchases & Payables';
      case ReportCategory.inventoryWarehouse:
        return 'Inventory & Warehouse';
      case ReportCategory.auditGovernance:
        return 'Audit & Governance';
      case ReportCategory.customSql:
        return 'Custom SQL Studio';
    }
  }
}

class ReportMetadata {
  final String id;
  final String title;
  final ReportCategory category;
  final String description;
  final String iconCode;
  final bool isCustomSql;

  const ReportMetadata({
    required this.id,
    required this.title,
    required this.category,
    required this.description,
    this.iconCode = 'bar_chart',
    this.isCustomSql = false,
  });
}

class ReportColumn {
  final String key;
  final String label;
  final bool isNumeric;
  final bool isCurrency;
  final double? width;

  const ReportColumn({
    required this.key,
    required this.label,
    this.isNumeric = false,
    this.isCurrency = false,
    this.width,
  });
}

class ReportRow {
  final Map<String, dynamic> cells;

  const ReportRow(this.cells);

  dynamic get(String key) => cells[key];
}

class ReportData {
  final ReportMetadata metadata;
  final List<ReportColumn> columns;
  final List<ReportRow> rows;
  final Map<String, dynamic> summary;
  final DateTime generatedAt;
  final String? dateRangeLabel;

  const ReportData({
    required this.metadata,
    required this.columns,
    required this.rows,
    this.summary = const {},
    required this.generatedAt,
    this.dateRangeLabel,
  });
}
