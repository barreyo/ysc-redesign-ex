import EctoEnum

defenum(LedgerAccountType, ["revenue", "liability", "expense", "asset", "equity"])
defenum(LedgerEntryEntityType, ["event", "membership", "booking", "donation"])
defenum(LedgerPaymentStatus, ["pending", "completed", "failed", "refunded"])
defenum(LedgerTransactionType, ["payment", "refund", "fee", "adjustment"])
defenum(LedgerTransactionStatus, ["pending", "completed", "reversed"])
defenum(LedgerPaymentProvider, ["stripe"])
