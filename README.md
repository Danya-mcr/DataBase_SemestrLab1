📋 Project Overview
A robust PostgreSQL database designed to manage warehouse operations, inventory tracking, and financial reporting.
Key Features:
Inventory Management: Comprehensive tracking of products and stock levels across multiple warehouses.
Document Workflow: Full support for purchase invoices, stock transfer notes, and sales invoices.
Supply Chain Tracking: Management of suppliers, customers, and goods movement.
Analytical Reporting: Built-in functions for calculating profits and stock balances.
🏗️ Database Structure
1. Dictionaries (Lookup Tables)
organizationtype — Legal forms (LLC, IE, Self-employed).
documenttype — Document categories (Purchase Invoice, Stock Transfer Note, Sales Invoice).
movementtype — Traffic directions (Inflow/Outflow).
unit — Units of measurement (pcs, kg, liters).
warehouse — Storage locations.
product_org — Product catalog.
2. Counterparties
supplier — Vendor data.
customer — Client data.
3. Document Headers
basetable — Universal document header.
purchaseinvoice, salesinvoice, stocktransfernote — Specialized document headers.
4. Line Items & Logistics
purchaseinvoice_str, salesinvoice_str, stocktransfernote_str — Detailed document line items.
movement — Ledger for all product transactions.
🔑 Implementation Highlights
1. Primary Key Generation Engine
Solution: Custom genprimarykey() function.
Details: Generates compact Base62 strings (5 characters) for primary keys.
Automation: Each table is supported by an independent PostgreSQL sequence.
2. Tax ID (INN) Validation
Solution: Integrated checkinn() validation logic.
Mechanism: Validates checksums for 10 and 12-digit Russian Tax IDs.
Data Integrity: Database-level triggers automatically validate INN before insertion into supplier or customer tables.
3. Document Numbering System
Solution: genregnumber() function.
Details: Automatically generates unique 7-digit registration numbers for all incoming documents using sequences.
4. Analytical PL/pgSQL Functions
getadmission() — Aggregates product inflows for a specified period.
getsells() — Summarizes sales data.
getcustomerstats() — Analyzes customer purchasing patterns.
getproductbydate() — Calculates inventory snapshots (stock on hand) for any given date.
getprofit() — Calculates gross profit per item based on purchase/sales price delta.
🛠️ Technology Stack
Database: PostgreSQL 15+
Language: PL/pgSQL (Triggers, Functions, Procedures)
Architecture: Third Normal Form (3NF)
