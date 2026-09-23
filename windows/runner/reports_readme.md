# Ludgerpulse Windows Desktop Custom Report Engine (FR-RPT-04)

This desktop add-on module allows power users to query the local SQLite database using raw SQL syntax and XML configuration files.

## XML Report Schema

Place custom XML templates in the application data directory or load them directly into the **Desktop Custom Report Studio**:

```xml
<report id="unique_report_id" title="My Custom Report">
  <description>User-friendly description of report purpose</description>
  <query>
    SELECT columns FROM table WHERE condition;
  </query>
  <columns>
    <column key="db_column_name" label="Display Title" isNumeric="true" isCurrency="false" />
  </columns>
</report>
```

## Features
- **Raw SQL execution**: Runs optimized queries against local SQLite database tables (`vouchers`, `parties`, `ledger_entries`, `inventory_items`, `stock_ledger`).
- **Interactive UI**: Search, sort, and paginate through report records.
- **Multi-Format Export**: Export directly to Microsoft Excel (CSV with UTF-8 BOM), PDF, or print via system print dialog.
