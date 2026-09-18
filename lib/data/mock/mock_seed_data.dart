import '../models/party_model.dart';
import '../models/transaction_model.dart';

class MockSeedData {
  static final DateTime now = DateTime.now();

  static List<Party> initialParties = [
    Party(
      id: 'party_1',
      name: 'Rahul Sharma',
      phoneNumber: '+91 98765 43210',
      type: PartyType.customer,
      netBalanceInCents: 450000, // +₹4,500.00 Receivable
      lastUpdated: now.subtract(const Duration(hours: 3)),
    ),
    Party(
      id: 'party_2',
      name: 'Ananya Patel',
      phoneNumber: '+91 98111 22334',
      type: PartyType.customer,
      netBalanceInCents: 0, // ₹0 Settled
      lastUpdated: now.subtract(const Duration(days: 2)),
    ),
    Party(
      id: 'party_3',
      name: 'Metro Wholesale Traders',
      phoneNumber: '+91 99223 34455',
      type: PartyType.supplier,
      netBalanceInCents: -1280000, // -₹12,800.00 Payable
      lastUpdated: now.subtract(const Duration(days: 1)),
    ),
    Party(
      id: 'party_4',
      name: 'Apex Logistics',
      phoneNumber: '+91 97654 32190',
      type: PartyType.supplier,
      netBalanceInCents: -120000, // -₹1,200.00 Payable
      lastUpdated: now.subtract(const Duration(days: 4)),
    ),
  ];

  static List<LedgerEntry> initialEntries = [
    // --- Rahul Sharma (party_1) - Customer ---
    // Net: +6000 -2500 +2000 -1000 = +4500
    LedgerEntry(
      id: 'entry_1_1',
      partyId: 'party_1',
      amountInCents: 600000, // ₹6,000
      type: EntryType.gave,
      date: now.subtract(const Duration(days: 14, hours: 2)),
      note: 'Grocery consignment #104',
      receiptPhotoUrl: 'https://images.unsplash.com/photo-1554224155-8d04cb21cd6c?w=400',
    ),
    LedgerEntry(
      id: 'entry_1_2',
      partyId: 'party_1',
      amountInCents: 250000, // ₹2,500
      type: EntryType.got,
      date: now.subtract(const Duration(days: 7, hours: 4)),
      note: 'UPI Payment received (PhonePe)',
    ),
    LedgerEntry(
      id: 'entry_1_3',
      partyId: 'party_1',
      amountInCents: 200000, // ₹2,000
      type: EntryType.gave,
      date: now.subtract(const Duration(days: 3, hours: 1)),
      note: 'Added 2 sacks of Basmati rice',
    ),
    LedgerEntry(
      id: 'entry_1_4',
      partyId: 'party_1',
      amountInCents: 100000, // ₹1,000
      type: EntryType.got,
      date: now.subtract(const Duration(hours: 3)),
      note: 'Cash payment on delivery',
    ),

    // --- Ananya Patel (party_2) - Customer ---
    // Net: +3200 -3200 = 0
    LedgerEntry(
      id: 'entry_2_1',
      partyId: 'party_2',
      amountInCents: 320000, // ₹3,200
      type: EntryType.gave,
      date: now.subtract(const Duration(days: 5, hours: 5)),
      note: 'Organic spices & tea pack',
      receiptPhotoUrl: 'https://images.unsplash.com/photo-1586528116311-ad8dd3c8310d?w=400',
    ),
    LedgerEntry(
      id: 'entry_2_2',
      partyId: 'party_2',
      amountInCents: 320000, // ₹3,200
      type: EntryType.got,
      date: now.subtract(const Duration(days: 2, hours: 2)),
      note: 'Settled via Google Pay',
    ),

    // --- Metro Wholesale Traders (party_3) - Supplier ---
    // Net: -20000 +10000 -7800 +5000 = -12800
    LedgerEntry(
      id: 'entry_3_1',
      partyId: 'party_3',
      amountInCents: 2000000, // ₹20,000
      type: EntryType.got, // Got supplies on credit -> owes more
      date: now.subtract(const Duration(days: 21, hours: 6)),
      note: 'Inventory restock Invoice #8892',
      receiptPhotoUrl: 'https://images.unsplash.com/photo-1554224154-26032ffc0d07?w=400',
    ),
    LedgerEntry(
      id: 'entry_3_2',
      partyId: 'party_3',
      amountInCents: 1000000, // ₹10,000
      type: EntryType.gave, // Paid them -> reduces debt
      date: now.subtract(const Duration(days: 14, hours: 3)),
      note: 'HDFC Cheque #304921',
    ),
    LedgerEntry(
      id: 'entry_3_3',
      partyId: 'party_3',
      amountInCents: 780000, // ₹7,800
      type: EntryType.got, // Got more supplies
      date: now.subtract(const Duration(days: 7, hours: 2)),
      note: 'Cooking oil carton pack',
    ),
    LedgerEntry(
      id: 'entry_3_4',
      partyId: 'party_3',
      amountInCents: 500000, // ₹5,000
      type: EntryType.gave, // Partial payment
      date: now.subtract(const Duration(days: 1, hours: 4)),
      note: 'NEFT Online Transfer',
    ),

    // --- Apex Logistics (party_4) - Supplier ---
    // Net: -3200 +2000 = -1200
    LedgerEntry(
      id: 'entry_4_1',
      partyId: 'party_4',
      amountInCents: 320000, // ₹3,200
      type: EntryType.got, // Service received on credit
      date: now.subtract(const Duration(days: 10, hours: 3)),
      note: 'Interstate freight delivery #442',
    ),
    LedgerEntry(
      id: 'entry_4_2',
      partyId: 'party_4',
      amountInCents: 200000, // ₹2,000
      type: EntryType.gave, // Advance payment
      date: now.subtract(const Duration(days: 4, hours: 1)),
      note: 'Cash advance against receipt',
    ),
  ];
}
