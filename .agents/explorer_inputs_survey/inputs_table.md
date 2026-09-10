# Full Survey of All Input Fields in Frontend Codebase

| # | File | Line | Current Type | InputMode | Field Purpose | Current Sanitizer/Handler | Evaluation / Action Required |
|---|------|------|--------------|-----------|---------------|----------------------------|-------------------------------|
| 1 | `components/ArrearsThresholdModal.tsx` | 49 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 2 | `components/PaymentModal.tsx` | 110 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 3 | `components/ReadingModal.tsx` | 205 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 4 | `components/common/ExcelGrid.tsx` | 229 | `text` | `none` | Text / Search | `Direct string` | OK (Search/Filter text) |
| 5 | `components/common/ExcelGrid.tsx` | 277 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 6 | `components/common/ExcelGrid.tsx` | 291 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 7 | `components/common/ExcelGrid.tsx` | 385 | `text` | `none` | Search query box | `Direct string onChange` | OK (Search text field) |
| 8 | `components/common/ExcelGrid.tsx` | 512 | `text` | `numeric` | Integer / Phone / Route / Meter | `toEnglishDigits` | Protected with toEnglishDigits |
| 9 | `components/common/ExcelGrid.tsx` | 525 | `text` | `none` | Integer / Phone / Route / Meter | `toEnglishDigits` | Protected with toEnglishDigits |
| 10 | `components/common/ExcelGrid.tsx` | 537 | `text` | `none` | Name / Address / Username | `Direct string onChange` | OK (Text field) |
| 11 | `components/common/ExcelGrid.tsx` | 549 | `text` | `none` | Name / Address / Username | `Direct string onChange` | OK (Text field) |
| 12 | `components/common/ExcelGrid.tsx` | 561 | `text` | `numeric` | Integer / Phone / Route / Meter | `toEnglishDigits` | Protected with toEnglishDigits |
| 13 | `components/common/ExcelGrid.tsx` | 574 | `text` | `numeric` | Integer / Phone / Route / Meter | `toEnglishDigits` | Protected with toEnglishDigits |
| 14 | `components/common/ExcelGrid.tsx` | 588 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 15 | `components/common/ExcelGrid.tsx` | 607 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 16 | `components/common/ExcelGrid.tsx` | 632 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 17 | `components/common/ExcelGrid.tsx` | 652 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 18 | `components/common/ExcelGrid.tsx` | 676 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 19 | `components/common/ExcelGrid.tsx` | 695 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 20 | `components/common/ExcelGrid.tsx` | 719 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 21 | `pages/ArrearsReport.tsx` | 487 | `text` | `none` | Search query box | `Direct string onChange` | OK (Search text field) |
| 22 | `pages/AuditLogs.tsx` | 65 | `text` | `none` | Search query box | `Direct string onChange` | OK (Search text field) |
| 23 | `pages/Customers.tsx` | 574 | `text` | `numeric` | Integer / Phone / Route / Meter | `toEnglishDigits` | Protected with toEnglishDigits |
| 24 | `pages/Customers.tsx` | 590 | `text` | `none` | Name / Address / Username | `Direct string onChange` | OK (Text field) |
| 25 | `pages/Customers.tsx` | 603 | `text` | `numeric` | Integer / Phone / Route / Meter | `toEnglishDigits` | Protected with toEnglishDigits |
| 26 | `pages/Customers.tsx` | 617 | `text` | `none` | Integer / Phone / Route / Meter | `toEnglishDigits` | Protected with toEnglishDigits |
| 27 | `pages/Customers.tsx` | 627 | `text` | `numeric` | Integer / Phone / Route / Meter | `toEnglishDigits` | Protected with toEnglishDigits |
| 28 | `pages/Customers.tsx` | 640 | `text` | `none` | Integer / Phone / Route / Meter | `toEnglishDigits` | Protected with toEnglishDigits |
| 29 | `pages/Customers.tsx` | 652 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 30 | `pages/Customers.tsx` | 740 | `text` | `numeric` | Integer / Phone / Route / Meter | `toEnglishDigits` | Protected with toEnglishDigits |
| 31 | `pages/Customers.tsx` | 755 | `text` | `none` | Name / Address / Username | `Direct string onChange` | OK (Text field) |
| 32 | `pages/Customers.tsx` | 769 | `text` | `numeric` | Integer / Phone / Route / Meter | `toEnglishDigits` | Protected with toEnglishDigits |
| 33 | `pages/Customers.tsx` | 800 | `text` | `none` | Name / Address / Username | `Direct string onChange` | OK (Text field) |
| 34 | `pages/Customers.tsx` | 811 | `text` | `numeric` | Integer / Phone / Route / Meter | `toEnglishDigits` | Protected with toEnglishDigits |
| 35 | `pages/Customers.tsx` | 825 | `text` | `none` | Integer / Phone / Route / Meter | `toEnglishDigits` | Protected with toEnglishDigits |
| 36 | `pages/Customers.tsx` | 838 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 37 | `pages/Dashboard.tsx` | 537 | `text` | `none` | Search query box | `Direct string onChange` | OK (Search text field) |
| 38 | `pages/Dashboard.tsx` | 776 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 39 | `pages/Invoices.tsx` | 395 | `text` | `none` | Search query box | `Direct string onChange` | OK (Search text field) |
| 40 | `pages/Login.tsx` | 67 | `text` | `none` | Name / Address / Username | `Direct string onChange` | OK (Text field) |
| 41 | `pages/Login.tsx` | 83 | `password` | `none` | Password input | `Password handler` | OK (Password field) |
| 42 | `pages/Login.tsx` | 99 | `checkbox` | `none` | Checkbox (Remember me) | `Boolean state` | OK (Checkbox) |
| 43 | `pages/ReportsHub.tsx` | 695 | `text` | `none` | Search query box | `Direct string onChange` | OK (Search text field) |
| 44 | `pages/ReportsHub.tsx` | 925 | `text` | `none` | Search query box | `Direct string onChange` | OK (Search text field) |
| 45 | `pages/ReportsHub.tsx` | 1141 | `text` | `none` | Search query box | `Direct string onChange` | OK (Search text field) |
| 46 | `pages/ReportsHub.tsx` | 1479 | `text` | `none` | Search query box | `Direct string onChange` | OK (Search text field) |
| 47 | `pages/ReportsHub.tsx` | 1605 | `text` | `none` | Search query box | `Direct string onChange` | OK (Search text field) |
| 48 | `pages/TodayReadingsReview.tsx` | 413 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 49 | `pages/TodayReadingsReview.tsx` | 427 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 50 | `pages/TodayReadingsReview.tsx` | 559 | `text` | `none` | Search query box | `Direct string onChange` | OK (Search text field) |
| 51 | `pages/TodayReadingsReview.tsx` | 700 | `text` | `numeric` | Integer / Phone / Route / Meter | `toEnglishDigits` | Protected with toEnglishDigits |
| 52 | `pages/TodayReadingsReview.tsx` | 713 | `text` | `none` | Integer / Phone / Route / Meter | `toEnglishDigits` | Protected with toEnglishDigits |
| 53 | `pages/TodayReadingsReview.tsx` | 725 | `text` | `none` | Name / Address / Username | `Direct string onChange` | OK (Text field) |
| 54 | `pages/TodayReadingsReview.tsx` | 737 | `text` | `none` | Name / Address / Username | `Direct string onChange` | OK (Text field) |
| 55 | `pages/TodayReadingsReview.tsx` | 749 | `text` | `numeric` | Integer / Phone / Route / Meter | `toEnglishDigits` | Protected with toEnglishDigits |
| 56 | `pages/TodayReadingsReview.tsx` | 762 | `text` | `numeric` | Integer / Phone / Route / Meter | `toEnglishDigits` | Protected with toEnglishDigits |
| 57 | `pages/TodayReadingsReview.tsx` | 776 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 58 | `pages/TodayReadingsReview.tsx` | 795 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 59 | `pages/TodayReadingsReview.tsx` | 819 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 60 | `pages/TodayReadingsReview.tsx` | 838 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 61 | `pages/TodayReadingsReview.tsx` | 862 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 62 | `pages/TodayReadingsReview.tsx` | 881 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 63 | `pages/TodayReadingsReview.tsx` | 905 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 64 | `pages/UnreadMeters.tsx` | 262 | `text` | `none` | Search query box | `Direct string onChange` | OK (Search text field) |
| 65 | `pages/UnreadMeters.tsx` | 375 | `text` | `decimal` | Decimal numeric field | `sanitizeDecimalInput` | Protected with toEnglishDigits + decimal sanitize |
| 66 | `pages/UsersManagement.tsx` | 329 | `text` | `none` | Name / Address / Username | `Direct string onChange` | OK (Text field) |
| 67 | `pages/UsersManagement.tsx` | 341 | `text` | `none` | Name / Address / Username | `Direct string onChange` | OK (Text field) |
| 68 | `pages/UsersManagement.tsx` | 353 | `password` | `none` | Password input | `Password handler` | OK (Password field) |
| 69 | `pages/UsersManagement.tsx` | 405 | `text` | `none` | Name / Address / Username | `Direct string onChange` | OK (Text field) |
| 70 | `pages/UsersManagement.tsx` | 450 | `password` | `none` | Password input | `Password handler` | OK (Password field) |
| 71 | `pages/WhatsApp.tsx` | 241 | `text` | `numeric` | Integer / Phone / Route / Meter | `toEnglishDigits` | Protected with toEnglishDigits |
