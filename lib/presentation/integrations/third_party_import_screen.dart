import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/colors.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/models/party_model.dart';
import '../../data/services/data_import_service.dart';
import '../providers/company_providers.dart';
import '../providers/inventory_providers.dart';
import '../providers/ledger_providers.dart';

class ThirdPartyImportScreen extends ConsumerStatefulWidget {
  const ThirdPartyImportScreen({super.key});

  @override
  ConsumerState<ThirdPartyImportScreen> createState() =>
      _ThirdPartyImportScreenState();
}

class _ThirdPartyImportScreenState
    extends ConsumerState<ThirdPartyImportScreen> {
  ImportSourceType _selectedSource = ImportSourceType.tallyXml;
  final TextEditingController _contentController = TextEditingController();
  ImportParseResult? _parsedResult;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _loadSampleTemplate();
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  void _loadSampleTemplate() {
    switch (_selectedSource) {
      case ImportSourceType.tallyXml:
        _contentController.text = '''<ENVELOPE>
  <BODY>
    <DATA>
      <TALLYMESSAGE>
        <LEDGER NAME="Apex Infotech Solutions">
          <PARENT>Sundry Debtors</PARENT>
          <PARTYGSTIN>29ABCDE1234F1ZH</PARTYGSTIN>
          <LEDGERPHONE>+91 98765 43210</LEDGERPHONE>
          <OPENINGBALANCE>150000.00</OPENINGBALANCE>
        </LEDGER>
        <LEDGER NAME="Karnataka Silicon Vendors">
          <PARENT>Sundry Creditors</PARENT>
          <PARTYGSTIN>29XYZDE9876K1Z2</PARTYGSTIN>
          <LEDGERPHONE>+91 98220 55443</LEDGERPHONE>
          <OPENINGBALANCE>45000.00</OPENINGBALANCE>
        </LEDGER>
        <STOCKITEM NAME="Industrial Control Unit MK-4">
          <BASEUNITS>PCS</BASEUNITS>
          <OPENINGBALANCE>25.0</OPENINGBALANCE>
          <OPENINGRATE>12500.00</OPENINGRATE>
          <HSNCODE>8471</HSNCODE>
        </STOCKITEM>
      </TALLYMESSAGE>
    </DATA>
  </BODY>
</ENVELOPE>''';
        break;
      case ImportSourceType.zohoCsv:
        _contentController.text = '''Contact Name,Display Name,Contact Type,Phone,GST Identification Number (GSTIN)
"BlueStar Logistics Pvt Ltd","BlueStar Logistics","Customer","9844011223","29AAACB1122D1Z5"
"National Hardware Supplies","National Hardware","Vendor","9711099887","29BCCCD3344E1Z8"''';
        break;
      case ImportSourceType.quickBooksIif:
        _contentController.text = '''!CUST	NAME	BADDR1	PHONE
CUST	Horizon Tech Innovations	MG Road Bangalore	9876501234
!VEND	NAME	BADDR1	PHONE
VEND	Southern Power Corp	Indiranagar	9823098765
!INVITEM	NAME	DESC	PRICE	COST
INVITEM	Server Rack Cabinet	42U Server Rack	45000	32000''';
        break;
      case ImportSourceType.busyXml:
        _contentController.text = '''<BUSY_DATA>
  <MASTER>
    <ACCOUNT NAME="Apex Infotech Solutions">
      <GROUP>Sundry Debtors</GROUP>
      <GSTIN>29ABCDE1234F1ZH</GSTIN>
      <MOBILE>9876543210</MOBILE>
      <OP_BAL>150000.00</OP_BAL>
      <OP_BAL_TYPE>D</OP_BAL_TYPE>
    </ACCOUNT>
    <ACCOUNT NAME="Karnataka Silicon Vendors">
      <GROUP>Sundry Creditors</GROUP>
      <GSTIN>29XYZDE9876K1Z2</GSTIN>
      <MOBILE>9822055443</MOBILE>
      <OP_BAL>45000.00</OP_BAL>
      <OP_BAL_TYPE>C</OP_BAL_TYPE>
    </ACCOUNT>
    <ITEM NAME="Industrial Control Unit MK-4">
      <MAIN_UNIT>PCS</MAIN_UNIT>
      <OP_QTY>25.0</OP_QTY>
      <PUR_PRICE>10000.00</PUR_PRICE>
      <SALE_PRICE>12500.00</SALE_PRICE>
      <HSN_CODE>8471</HSN_CODE>
    </ITEM>
  </MASTER>
</BUSY_DATA>''';
        break;
      case ImportSourceType.excelCsv:
        _contentController.text = '''Customer Name,Phone,GSTIN,Opening Balance
"Prime Global Technologies","9811022334","29AAECP1234H1Z1","120000"
"Metro Retail Emporium","9822033445","29BBECP5678J1Z2","85000"''';
        break;
    }
    _runParse();
  }

  void _runParse() {
    final text = _contentController.text.trim();
    if (text.isEmpty) {
      setState(() => _parsedResult = null);
      return;
    }

    final company = ref.read(activeCompanyProvider);
    ImportParseResult res;

    switch (_selectedSource) {
      case ImportSourceType.tallyXml:
        res = DataImportService.parseTallyXml(xmlContent: text, companyId: company.id);
        break;
      case ImportSourceType.busyXml:
        res = DataImportService.parseBusyXml(xmlContent: text, companyId: company.id);
        break;
      case ImportSourceType.zohoCsv:
        res = DataImportService.parseZohoCsv(csvContent: text, companyId: company.id);
        break;
      case ImportSourceType.quickBooksIif:
        res = DataImportService.parseQuickBooksIif(iifContent: text, companyId: company.id);
        break;
      case ImportSourceType.excelCsv:
        res = DataImportService.parseExcelCsvAutoMapped(csvContent: text, companyId: company.id);
        break;
    }

    setState(() => _parsedResult = res);
  }

  Future<void> _commitImport() async {
    final result = _parsedResult;
    if (result == null || (result.importedParties.isEmpty && result.importedItems.isEmpty)) {
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isImporting = true);

    try {
      final ledgerRepo = ref.read(ledgerRepositoryProvider);
      final inventoryRepo = ref.read(inventoryRepositoryProvider);

      for (final party in result.importedParties) {
        await ledgerRepo.addParty(party);
      }

      for (final item in result.importedItems) {
        await inventoryRepo.addItem(item);
      }

      ref.invalidate(partyListProvider);
      ref.invalidate(inventoryItemsListProvider);
      ref.invalidate(inventoryValuationProvider);

      if (mounted) {
        setState(() => _isImporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully imported ${result.importedParties.length} parties and ${result.importedItems.length} inventory items!',
            ),
            backgroundColor: AppColors.receivableGreen,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isImporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to import records: $e'),
            backgroundColor: AppColors.payableRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = _parsedResult;

    return AdaptiveScaffold(
      title: 'Third-Party ERP & Excel Import',
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Source Selector
            DropdownButtonFormField<ImportSourceType>(
              initialValue: _selectedSource,
              decoration: InputDecoration(
                labelText: 'Select Software or Format',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: Icon(
                  isIos ? CupertinoIcons.arrow_2_circlepath : Icons.sync_alt_rounded,
                ),
                isDense: true,
              ),
              items: ImportSourceType.values.map((src) {
                return DropdownMenuItem(
                  value: src,
                  child: Text(src.displayName, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedSource = val);
                  _loadSampleTemplate();
                }
              },
            ),
            const SizedBox(height: 14),

            // Text Input / File Payload Area
            TextField(
              controller: _contentController,
              maxLines: 8,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              decoration: InputDecoration(
                labelText: 'Exported Payload (XML / CSV / IIF)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                alignLabelWithHint: true,
              ),
              onChanged: (_) => _runParse(),
            ),
            const SizedBox(height: 14),

            // Parse Summary Box
            if (result != null) ...[
              _buildParsePreview(isIos, isDark, result),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: AdaptiveButton(
                  onPressed: _isImporting || (result.importedParties.isEmpty && result.importedItems.isEmpty)
                      ? () {}
                      : _commitImport,
                  child: _isImporting
                      ? const CupertinoActivityIndicator()
                      : Text(
                          'Import ${result.importedParties.length} Parties & ${result.importedItems.length} Items',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildParsePreview(bool isIos, bool isDark, ImportParseResult result) {
    final content = Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Extraction Preview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.receivableGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${result.importedParties.length} Parties • ${result.importedItems.length} Items',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.receivableGreen, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          ...result.importedParties.take(3).map((p) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      isIos ? CupertinoIcons.person : Icons.person_outline,
                      size: 16,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('${p.name} (${p.type == PartyType.customer ? "Customer" : "Supplier"})',
                          style: const TextStyle(fontSize: 12)),
                    ),
                    if (p.gstin != null) Text(p.gstin!, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              )),
          ...result.importedItems.take(3).map((it) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      isIos ? CupertinoIcons.cube_box : Icons.inventory_2_outlined,
                      size: 16,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('${it.name} (${it.sku})', style: const TextStyle(fontSize: 12)),
                    ),
                    Text('Stock: ${it.currentStockQuantity.toStringAsFixed(0)}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              )),
        ],
      ),
    );

    if (isIos) {
      return LiquidGlassCard(borderRadius: 14, padding: EdgeInsets.zero, child: content);
    }
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
      ),
      child: content,
    );
  }
}
