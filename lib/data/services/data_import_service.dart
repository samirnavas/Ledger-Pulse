import 'dart:convert';
import '../models/inventory_item_model.dart';
import '../models/party_model.dart';

enum ImportSourceType {
  tallyXml,
  zohoCsv,
  quickBooksIif,
  busyXml,
  excelCsv;

  String get displayName {
    switch (this) {
      case ImportSourceType.tallyXml:
        return 'TallyPrime / ERP 9 (XML)';
      case ImportSourceType.zohoCsv:
        return 'Zoho Books (CSV / JSON)';
      case ImportSourceType.quickBooksIif:
        return 'QuickBooks (IIF / CSV)';
      case ImportSourceType.busyXml:
        return 'Busy Accounting (XML / CSV)';
      case ImportSourceType.excelCsv:
        return 'Microsoft Excel / CSV Template';
    }
  }
}

class ImportParseResult {
  final List<Party> importedParties;
  final List<InventoryItem> importedItems;
  final List<String> warnings;

  const ImportParseResult({
    this.importedParties = const [],
    this.importedItems = const [],
    this.warnings = const [],
  });
}

class DataImportService {
  /// Parses Tally XML export payload containing `<LEDGER>` and `<STOCKITEM>` tags
  static ImportParseResult parseTallyXml({
    required String xmlContent,
    required String companyId,
  }) {
    final parties = <Party>[];
    final items = <InventoryItem>[];
    final warnings = <String>[];

    // 1. Parse Tally Ledgers (Parties)
    final ledgerRegex = RegExp(r'<LEDGER\s+NAME="([^"]+)"[^>]*>(.*?)<\/LEDGER>', dotAll: true);
    for (final match in ledgerRegex.allMatches(xmlContent)) {
      final name = match.group(1)?.trim() ?? '';
      final body = match.group(2) ?? '';

      final parentMatch = RegExp(r'<PARENT>(.*?)<\/PARENT>').firstMatch(body);
      final gstinMatch = RegExp(r'<PARTYGSTIN>(.*?)<\/PARTYGSTIN>').firstMatch(body);
      final mobileMatch = RegExp(r'<LEDGERPHONE>(.*?)<\/LEDGERPHONE>').firstMatch(body);
      final openingBalMatch = RegExp(r'<OPENINGBALANCE>(.*?)<\/OPENINGBALANCE>').firstMatch(body);

      final parent = parentMatch?.group(1)?.trim().toLowerCase() ?? '';
      final gstin = gstinMatch?.group(1)?.trim();
      final phone = mobileMatch?.group(1)?.trim() ?? '9999999999';
      final opBal = double.tryParse(openingBalMatch?.group(1)?.trim() ?? '0') ?? 0.0;

      PartyType pType = PartyType.customer;
      if (parent.contains('creditor') || parent.contains('supplier') || parent.contains('purchase')) {
        pType = PartyType.supplier;
      }

      parties.add(
        Party(
          id: 'tally_pty_${DateTime.now().millisecondsSinceEpoch}_${parties.length}',
          name: name,
          phoneNumber: phone,
          type: pType,
          netBalanceInCents: (opBal * 100).round(),
          gstin: gstin?.isNotEmpty == true ? gstin : null,
          lastUpdated: DateTime.now(),
        ),
      );
    }

    // 2. Parse Tally Stock Items
    final stockRegex = RegExp(r'<STOCKITEM\s+NAME="([^"]+)"[^>]*>(.*?)<\/STOCKITEM>', dotAll: true);
    for (final match in stockRegex.allMatches(xmlContent)) {
      final name = match.group(1)?.trim() ?? '';
      final body = match.group(2) ?? '';

      final baseUnits = RegExp(r'<BASEUNITS>(.*?)<\/BASEUNITS>').firstMatch(body)?.group(1)?.trim() ?? 'PCS';
      final openingQty = double.tryParse(RegExp(r'<OPENINGBALANCE>(.*?)<\/OPENINGBALANCE>').firstMatch(body)?.group(1)?.trim() ?? '0') ?? 0.0;
      final openingRate = double.tryParse(RegExp(r'<OPENINGRATE>(.*?)<\/OPENINGRATE>').firstMatch(body)?.group(1)?.trim() ?? '0') ?? 0.0;
      final hsn = RegExp(r'<HSNCODE>(.*?)<\/HSNCODE>').firstMatch(body)?.group(1)?.trim() ?? '8471';

      items.add(
        InventoryItem(
          id: 'tally_itm_${DateTime.now().millisecondsSinceEpoch}_${items.length}',
          companyId: companyId,
          sku: 'SKU-${name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-').toUpperCase()}',
          name: name,
          hsnCode: hsn,
          unit: baseUnits,
          currentStockQuantity: openingQty,
          purchasePriceInCents: (openingRate * 100).round(),
          sellingPriceInCents: (openingRate * 1.25 * 100).round(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    }

    if (parties.isEmpty && items.isEmpty) {
      warnings.add('No <LEDGER> or <STOCKITEM> records could be extracted from Tally XML.');
    }

    return ImportParseResult(
      importedParties: parties,
      importedItems: items,
      warnings: warnings,
    );
  }

  /// Parses Zoho Books Contacts or Items CSV
  static ImportParseResult parseZohoCsv({
    required String csvContent,
    required String companyId,
  }) {
    final parties = <Party>[];
    final items = <InventoryItem>[];
    final warnings = <String>[];

    final lines = const LineSplitter().convert(csvContent);
    if (lines.isEmpty) return const ImportParseResult();

    final headers = lines.first.split(',').map((h) => h.replaceAll('"', '').trim().toLowerCase()).toList();

    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final cols = _splitCsvLine(line);

      if (headers.contains('contact name') || headers.contains('display name')) {
        final nameIdx = headers.contains('contact name') ? headers.indexOf('contact name') : headers.indexOf('display name');
        final name = cols.length > nameIdx ? cols[nameIdx] : '';
        if (name.isEmpty) continue;

        final phoneIdx = headers.indexOf('phone');
        final gstinIdx = headers.indexOf('gst identification number (gstin)');
        final typeIdx = headers.indexOf('contact type');

        final phone = phoneIdx != -1 && cols.length > phoneIdx && cols[phoneIdx].isNotEmpty ? cols[phoneIdx] : '9999999999';
        final gstin = gstinIdx != -1 && cols.length > gstinIdx ? cols[gstinIdx] : null;
        final typeStr = typeIdx != -1 && cols.length > typeIdx ? cols[typeIdx].toLowerCase() : 'customer';

        parties.add(
          Party(
            id: 'zoho_pty_${DateTime.now().millisecondsSinceEpoch}_$i',
            name: name,
            phoneNumber: phone,
            type: typeStr.contains('vendor') ? PartyType.supplier : PartyType.customer,
            netBalanceInCents: 0,
            gstin: gstin?.isNotEmpty == true ? gstin : null,
            lastUpdated: DateTime.now(),
          ),
        );
      } else if (headers.contains('item name')) {
        final nameIdx = headers.indexOf('item name');
        final skuIdx = headers.indexOf('sku');
        final rateIdx = headers.indexOf('rate');
        final stockIdx = headers.indexOf('stock on hand');

        final name = cols.length > nameIdx ? cols[nameIdx] : '';
        if (name.isEmpty) continue;

        final sku = skuIdx != -1 && cols.length > skuIdx && cols[skuIdx].isNotEmpty ? cols[skuIdx] : 'SKU-$i';
        final rate = rateIdx != -1 && cols.length > rateIdx ? double.tryParse(cols[rateIdx]) ?? 0.0 : 0.0;
        final stock = stockIdx != -1 && cols.length > stockIdx ? double.tryParse(cols[stockIdx]) ?? 0.0 : 0.0;

        items.add(
          InventoryItem(
            id: 'zoho_itm_${DateTime.now().millisecondsSinceEpoch}_$i',
            companyId: companyId,
            sku: sku,
            name: name,
            currentStockQuantity: stock,
            purchasePriceInCents: (rate * 0.8 * 100).round(),
            sellingPriceInCents: (rate * 100).round(),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
      }
    }

    return ImportParseResult(
      importedParties: parties,
      importedItems: items,
      warnings: warnings,
    );
  }

  /// Parses QuickBooks IIF (Intuit Interchange Format) or CSV
  static ImportParseResult parseQuickBooksIif({
    required String iifContent,
    required String companyId,
  }) {
    final parties = <Party>[];
    final items = <InventoryItem>[];
    final lines = const LineSplitter().convert(iifContent);

    for (final line in lines) {
      final cols = line.split('\t');
      if (cols.isEmpty) continue;

      final tag = cols.first.trim().toUpperCase();
      if (tag == 'CUST' && cols.length >= 3) {
        final name = cols[1].trim();
        final phone = cols.length >= 4 && cols[3].trim().isNotEmpty ? cols[3].trim() : '9999999999';
        parties.add(
          Party(
            id: 'qb_cust_${parties.length}_${DateTime.now().millisecondsSinceEpoch}',
            name: name,
            phoneNumber: phone,
            type: PartyType.customer,
            netBalanceInCents: 0,
            lastUpdated: DateTime.now(),
          ),
        );
      } else if (tag == 'VEND' && cols.length >= 3) {
        final name = cols[1].trim();
        final phone = cols.length >= 4 && cols[3].trim().isNotEmpty ? cols[3].trim() : '9999999999';
        parties.add(
          Party(
            id: 'qb_vend_${parties.length}_${DateTime.now().millisecondsSinceEpoch}',
            name: name,
            phoneNumber: phone,
            type: PartyType.supplier,
            netBalanceInCents: 0,
            lastUpdated: DateTime.now(),
          ),
        );
      } else if (tag == 'INVITEM' && cols.length >= 4) {
        final name = cols[1].trim();
        final price = double.tryParse(cols.length >= 4 ? cols[3].trim() : '0') ?? 0.0;
        final cost = double.tryParse(cols.length >= 5 ? cols[4].trim() : '0') ?? 0.0;

        items.add(
          InventoryItem(
            id: 'qb_itm_${items.length}_${DateTime.now().millisecondsSinceEpoch}',
            companyId: companyId,
            sku: 'SKU-${name.toUpperCase()}',
            name: name,
            sellingPriceInCents: (price * 100).round(),
            purchasePriceInCents: (cost * 100).round(),
            currentStockQuantity: 0.0,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
      }
    }

    return ImportParseResult(
      importedParties: parties,
      importedItems: items,
    );
  }

  /// Parses Busy Accounting XML export containing `<ACCOUNT>` and `<ITEM>` tags
  static ImportParseResult parseBusyXml({
    required String xmlContent,
    required String companyId,
  }) {
    final parties = <Party>[];
    final items = <InventoryItem>[];
    final warnings = <String>[];

    // 1. Parse Busy Accounts (Customers / Vendors)
    final accountRegex = RegExp(r'<ACCOUNT(?:\s+NAME="([^"]+)")?[^>]*>(.*?)<\/ACCOUNT>', dotAll: true);
    for (final match in accountRegex.allMatches(xmlContent)) {
      final body = match.group(2) ?? '';
      String name = match.group(1)?.trim() ?? '';
      if (name.isEmpty) {
        name = RegExp(r'<NAME>(.*?)<\/NAME>').firstMatch(body)?.group(1)?.trim() ??
            RegExp(r'<PRINT_NAME>(.*?)<\/PRINT_NAME>').firstMatch(body)?.group(1)?.trim() ??
            '';
      }
      if (name.isEmpty) continue;

      final group = RegExp(r'<GROUP>(.*?)<\/GROUP>').firstMatch(body)?.group(1)?.trim().toLowerCase() ?? '';
      final gstin = RegExp(r'<GSTIN>(.*?)<\/GSTIN>').firstMatch(body)?.group(1)?.trim() ??
          RegExp(r'<PARTYGSTIN>(.*?)<\/PARTYGSTIN>').firstMatch(body)?.group(1)?.trim();
      final phone = RegExp(r'<MOBILE>(.*?)<\/MOBILE>').firstMatch(body)?.group(1)?.trim() ??
          RegExp(r'<PHONE>(.*?)<\/PHONE>').firstMatch(body)?.group(1)?.trim() ??
          '9999999999';
      final opBalStr = RegExp(r'<OP_BAL>(.*?)<\/OP_BAL>').firstMatch(body)?.group(1)?.trim() ??
          RegExp(r'<OPENINGBALANCE>(.*?)<\/OPENINGBALANCE>').firstMatch(body)?.group(1)?.trim() ??
          '0';
      final opBal = double.tryParse(opBalStr) ?? 0.0;

      PartyType pType = PartyType.customer;
      if (group.contains('creditor') || group.contains('supplier') || group.contains('vendor') || group.contains('purchase')) {
        pType = PartyType.supplier;
      }

      parties.add(
        Party(
          id: 'busy_pty_${DateTime.now().millisecondsSinceEpoch}_${parties.length}',
          name: name,
          phoneNumber: phone,
          type: pType,
          netBalanceInCents: (opBal * 100).round(),
          gstin: (gstin != null && gstin.isNotEmpty) ? gstin : null,
          lastUpdated: DateTime.now(),
        ),
      );
    }

    // 2. Parse Busy Items
    final itemRegex = RegExp(r'<ITEM(?:\s+NAME="([^"]+)")?[^>]*>(.*?)<\/ITEM>', dotAll: true);
    for (final match in itemRegex.allMatches(xmlContent)) {
      final body = match.group(2) ?? '';
      String name = match.group(1)?.trim() ?? '';
      if (name.isEmpty) {
        name = RegExp(r'<NAME>(.*?)<\/NAME>').firstMatch(body)?.group(1)?.trim() ??
            RegExp(r'<PRINT_NAME>(.*?)<\/PRINT_NAME>').firstMatch(body)?.group(1)?.trim() ??
            '';
      }
      if (name.isEmpty) continue;

      final unit = RegExp(r'<MAIN_UNIT>(.*?)<\/MAIN_UNIT>').firstMatch(body)?.group(1)?.trim() ??
          RegExp(r'<UNIT>(.*?)<\/UNIT>').firstMatch(body)?.group(1)?.trim() ??
          'PCS';
      final opQty = double.tryParse(RegExp(r'<OP_QTY>(.*?)<\/OP_QTY>').firstMatch(body)?.group(1)?.trim() ?? '0') ?? 0.0;
      final purPrice = double.tryParse(RegExp(r'<PUR_PRICE>(.*?)<\/PUR_PRICE>').firstMatch(body)?.group(1)?.trim() ??
          RegExp(r'<OP_RATE>(.*?)<\/OP_RATE>').firstMatch(body)?.group(1)?.trim() ?? '0') ?? 0.0;
      final salePrice = double.tryParse(RegExp(r'<SALE_PRICE>(.*?)<\/SALE_PRICE>').firstMatch(body)?.group(1)?.trim() ?? '0') ?? (purPrice * 1.25);
      final hsn = RegExp(r'<HSN_CODE>(.*?)<\/HSN_CODE>').firstMatch(body)?.group(1)?.trim() ??
          RegExp(r'<HSNCODE>(.*?)<\/HSNCODE>').firstMatch(body)?.group(1)?.trim() ??
          '8471';

      items.add(
        InventoryItem(
          id: 'busy_itm_${DateTime.now().millisecondsSinceEpoch}_${items.length}',
          companyId: companyId,
          sku: 'SKU-${name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-').toUpperCase()}',
          name: name,
          hsnCode: hsn,
          unit: unit,
          currentStockQuantity: opQty,
          purchasePriceInCents: (purPrice * 100).round(),
          sellingPriceInCents: (salePrice * 100).round(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    }

    if (parties.isEmpty && items.isEmpty) {
      warnings.add('No <ACCOUNT> or <ITEM> records could be extracted from Busy XML.');
    }

    return ImportParseResult(
      importedParties: parties,
      importedItems: items,
      warnings: warnings,
    );
  }

  /// Parses Generic Excel / CSV with intelligent header auto-mapping
  static ImportParseResult parseExcelCsvAutoMapped({
    required String csvContent,
    required String companyId,
  }) {
    final parties = <Party>[];
    final items = <InventoryItem>[];
    final lines = const LineSplitter().convert(csvContent);
    if (lines.isEmpty) return const ImportParseResult();

    final headerRow = lines.first.split(',').map((h) => h.replaceAll('"', '').trim().toLowerCase()).toList();

    int findCol(List<String> synonyms) {
      for (final s in synonyms) {
        final idx = headerRow.indexWhere((h) => h.contains(s));
        if (idx != -1) return idx;
      }
      return -1;
    }

    final nameCol = findCol(['name', 'party', 'customer', 'supplier', 'item', 'product', 'description']);
    final phoneCol = findCol(['phone', 'mobile', 'contact']);
    final gstinCol = findCol(['gstin', 'gst', 'tax no']);
    final priceCol = findCol(['price', 'rate', 'amount', 'selling price', 'balance', 'opening']);
    final skuCol = findCol(['sku', 'code', 'item code', 'barcode']);
    final stockCol = findCol(['stock', 'qty', 'quantity', 'balance']);

    final isItemTable = skuCol != -1 || headerRow.any((h) => h.contains('item') || h.contains('sku') || h.contains('product'));

    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final cols = _splitCsvLine(line);

      final name = nameCol != -1 && cols.length > nameCol ? cols[nameCol] : '';
      if (name.isEmpty) continue;

      if (isItemTable) {
        final sku = skuCol != -1 && cols.length > skuCol && cols[skuCol].isNotEmpty ? cols[skuCol] : 'SKU-$i';
        final price = priceCol != -1 && cols.length > priceCol ? double.tryParse(cols[priceCol]) ?? 0.0 : 0.0;
        final stock = stockCol != -1 && cols.length > stockCol ? double.tryParse(cols[stockCol]) ?? 0.0 : 0.0;

        items.add(
          InventoryItem(
            id: 'xl_itm_${DateTime.now().millisecondsSinceEpoch}_$i',
            companyId: companyId,
            sku: sku,
            name: name,
            currentStockQuantity: stock,
            sellingPriceInCents: (price * 100).round(),
            purchasePriceInCents: (price * 0.75 * 100).round(),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
      } else {
        final phone = phoneCol != -1 && cols.length > phoneCol && cols[phoneCol].isNotEmpty ? cols[phoneCol] : '9999999999';
        final gstin = gstinCol != -1 && cols.length > gstinCol ? cols[gstinCol] : null;
        final opBal = priceCol != -1 && cols.length > priceCol ? double.tryParse(cols[priceCol]) ?? 0.0 : 0.0;

        parties.add(
          Party(
            id: 'xl_pty_${DateTime.now().millisecondsSinceEpoch}_$i',
            name: name,
            phoneNumber: phone,
            type: PartyType.customer,
            netBalanceInCents: (opBal * 100).round(),
            gstin: gstin?.isNotEmpty == true ? gstin : null,
            lastUpdated: DateTime.now(),
          ),
        );
      }
    }

    return ImportParseResult(
      importedParties: parties,
      importedItems: items,
    );
  }

  static List<String> _splitCsvLine(String line) {
    final List<String> result = [];
    final matches = RegExp(r'(?:^|,)(?:"([^"]*)"|([^,]*))').allMatches(line);
    for (final m in matches) {
      final val = m.group(1) ?? m.group(2) ?? '';
      result.add(val.trim());
    }
    return result;
  }
}
