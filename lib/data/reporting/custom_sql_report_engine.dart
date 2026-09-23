import '../local/database.dart';
import 'report_models.dart';

class CustomReportXmlTemplate {
  final String id;
  final String title;
  final String description;
  final String sqlQuery;
  final List<ReportColumn> columns;

  const CustomReportXmlTemplate({
    required this.id,
    required this.title,
    required this.description,
    required this.sqlQuery,
    required this.columns,
  });

  /// Simple and robust XML parser for custom report configurations
  factory CustomReportXmlTemplate.fromXml(String xmlString) {
    final idMatch = RegExp(r'id="([^"]+)"').firstMatch(xmlString);
    final titleMatch = RegExp(r'title="([^"]+)"').firstMatch(xmlString);
    final descMatch = RegExp(r'<description>(.*?)</description>', dotAll: true).firstMatch(xmlString);
    final queryMatch = RegExp(r'<query>(.*?)</query>', dotAll: true).firstMatch(xmlString);

    final id = idMatch?.group(1) ?? 'custom_report_${DateTime.now().millisecondsSinceEpoch}';
    final title = titleMatch?.group(1) ?? 'Custom SQL Report';
    final description = descMatch?.group(1)?.trim() ?? 'User-defined SQL report';
    final query = queryMatch?.group(1)?.trim() ?? 'SELECT * FROM parties LIMIT 50;';

    // Parse column elements
    final List<ReportColumn> parsedCols = [];
    final colMatches = RegExp(r'<column\s+key="([^"]+)"\s+label="([^"]+)"(?:\s+isNumeric="([^"]+)")?(?:\s+isCurrency="([^"]+)")?').allMatches(xmlString);

    for (final m in colMatches) {
      final key = m.group(1)!;
      final label = m.group(2)!;
      final isNumeric = m.group(3) == 'true';
      final isCurrency = m.group(4) == 'true';

      parsedCols.add(ReportColumn(
        key: key,
        label: label,
        isNumeric: isNumeric,
        isCurrency: isCurrency,
      ));
    }

    return CustomReportXmlTemplate(
      id: id,
      title: title,
      description: description,
      sqlQuery: query,
      columns: parsedCols,
    );
  }

  String toXml() {
    final colBuffer = StringBuffer();
    for (final col in columns) {
      colBuffer.writeln(
          '    <column key="${col.key}" label="${col.label}" isNumeric="${col.isNumeric}" isCurrency="${col.isCurrency}" />');
    }

    return '''<report id="$id" title="$title">
  <description>$description</description>
  <query>
$sqlQuery
  </query>
  <columns>
$colBuffer  </columns>
</report>''';
  }
}

typedef CustomSqlTemplate = CustomReportXmlTemplate;

/// Advanced reporting engine for desktop users allowing raw SQL execution
/// combined with XML report templates to render custom system reports.
class CustomSqlReportEngine {
  final AppDatabase _db;

  CustomSqlReportEngine(this._db);

  /// Parses multiple `<report>` elements from an XML document string
  static List<CustomReportXmlTemplate> parseXmlTemplates(String xmlString) {
    final List<CustomReportXmlTemplate> templates = [];
    final reportBlocks =
        RegExp(r'<report\s+id="[^"]+".*?<\/report>', dotAll: true)
            .allMatches(xmlString);
    for (final block in reportBlocks) {
      final blockText = block.group(0)!;
      templates.add(CustomReportXmlTemplate.fromXml(blockText));
    }
    if (templates.isEmpty && xmlString.contains('<report')) {
      templates.add(CustomReportXmlTemplate.fromXml(xmlString));
    }
    return templates;
  }

  /// Executes raw SQL query with read-only validation
  Future<ReportData> executeRawSql({
    required String sqlQuery,
    String reportTitle = 'Custom SQL Report',
    String reportDescription = 'Executed via Desktop Custom Report Studio',
    List<ReportColumn> columns = const [],
  }) async {
    final template = CustomReportXmlTemplate(
      id: 'custom_sql_${DateTime.now().millisecondsSinceEpoch}',
      title: reportTitle,
      description: reportDescription,
      sqlQuery: sqlQuery,
      columns: columns,
    );
    return executeReport(template: template);
  }

  /// Executes a custom SQL query and returns ReportData
  Future<ReportData> executeReport({
    required CustomReportXmlTemplate template,
  }) async {
    final sanitizedQuery = template.sqlQuery.trim();

    // Safety audit: custom reports should only execute read-only queries
    final lower = sanitizedQuery.toLowerCase();
    if (lower.startsWith('delete') ||
        lower.startsWith('drop') ||
        lower.startsWith('truncate') ||
        lower.startsWith('alter') ||
        lower.startsWith('insert') ||
        lower.startsWith('update') ||
        lower.startsWith('create')) {
      throw ArgumentError('Custom Report Error: Only SELECT queries are permitted in the report studio.');
    }

    final queryRows = await _db.customSelect(sanitizedQuery).get();

    List<ReportColumn> columns = template.columns;

    // Dynamically infer columns if none explicitly defined in XML template
    if (columns.isEmpty && queryRows.isNotEmpty) {
      columns = queryRows.first.data.keys.map((k) {
        return ReportColumn(key: k, label: k);
      }).toList();
    }

    final rows = queryRows.map((r) {
      return ReportRow(r.data);
    }).toList();

    return ReportData(
      metadata: ReportMetadata(
        id: template.id,
        title: template.title,
        category: ReportCategory.customSql,
        description: template.description,
        isCustomSql: true,
      ),
      columns: columns,
      rows: rows,
      summary: {
        'totalRecordsFound': rows.length,
      },
      generatedAt: DateTime.now(),
    );
  }
}
