# Handoff Report — Survey of Data Integrity & Runtime Verification

**Agent**: `explorer_survey_3`  
**Date**: 2026-09-07T14:45:00Z  
**Target File**: `d:/elctercity/.agents/explorer_survey_3/handoff.md`  
**Milestone**: `survey_data_integrity_and_runtime`  

---

## 1. Observation

### 1.1 Customer Entity, Constraints, and Database Indexes
- **Table Definition**:
  - `dist_portable/schema/init_schema.sql` (Line 1681 & 6892):
    ```sql
    subscriber_number character varying(50) NOT NULL,
    ...
    ALTER TABLE ONLY public.customers
        ADD CONSTRAINT customers_subscriber_number_key UNIQUE (subscriber_number);
    ```
  - `database/02_tables_and_constraints.sql` (Lines 137-159):
    ```sql
    CREATE TABLE IF NOT EXISTS public.customers (
        id BIGSERIAL PRIMARY KEY,
        subscriber_number VARCHAR(50) NOT NULL UNIQUE,
        ...
    );
    ```
- **Unique Clean Index (`uq_customers_subscriber_number_clean`)**:
  - In `dist_portable/schema/init_schema.sql` (Lines 7521-7524):
    ```sql
    -- Name: uq_customers_subscriber_number_clean; Type: INDEX; Schema: public; Owner: -
    CREATE UNIQUE INDEX uq_customers_subscriber_number_clean ON public.customers 
    USING btree (TRIM(BOTH FROM lower((subscriber_number)::text))) WHERE (is_deleted = false);
    ```
  - In `database/02_tables_and_constraints.sql`:
    - The index `uq_customers_subscriber_number_clean` does **not exist** in this file. Only standard indexes exist:
      ```sql
      CREATE INDEX IF NOT EXISTS idx_customers_subscriber_number ON public.customers(subscriber_number);
      CREATE INDEX IF NOT EXISTS idx_customers_route_subscriber ON public.customers(route_number, subscriber_number);
      ```
  - **Discrepancy with Requirement R3**:
    The requirement in `ORIGINAL_REQUEST.md:265` states:
    > "Enforce unique index `uq_customers_subscriber_number_clean` on `REGEXP_REPLACE(subscriber_number, '^0+', '')`"
    In current database dumps and schema files, the index expression is `TRIM(BOTH FROM lower((subscriber_number)::text))` rather than `REGEXP_REPLACE(subscriber_number, '^0+', '')`.

- **Current Customer Records in `init_schema.sql`**:
  - Verified via `check_customers.py`:
    - Total customers: `495`
    - Active customers (`is_deleted = false`): `495`
    - Deleted customers: `0`
    - Customer IDs: sequential from `1` to `495`
    - Exact duplicate subscriber numbers: `0`
    - Leading-zero stripped duplicate subscriber numbers: `0`
    - Table counts: `meter_readings` (495 rows), `invoices` (1979 rows), `payments` (46 rows), `audit_logs` (75 rows).

---

### 1.2 Go Backend Handlers & Services (`CreateCustomer`, `UpdateCustomer`, `UpdateGridCell`)
- **Route Bindings** (`server/cmd/server/main.go`):
  - Line 126: `api.Post("/customers", middleware.AuthRequired(authService), h.CreateCustomer)`
  - Lines 127-128: `api.Put("/customers/:id", ...)` / `api.Patch("/customers/:id", ...)` -> `h.UpdateCustomer`
  - Lines 129-132: `api.Patch("/customers/:id/grid-cell", ...)` / `api.Patch("/customers/:id/cell-update", ...)` -> `h.UpdateGridCell`
  - Lines 143-144: `api.Put("/readings/:id/cell-update", ...)` / `api.Patch("/readings/:id/cell-update", ...)` -> `h.UpdateGridCell`
  - Lines 159-160: `api.Put("/invoices/:id/cell-update", ...)` / `api.Patch("/invoices/:id/cell-update", ...)` -> `h.UpdateGridCell`

- **`CreateCustomer`** (`server/internal/services/customer_service.go:144-174`):
  ```go
  func (s *CustomerService) CreateCustomer(customer *models.Customer) (*models.Customer, error) {
      trimmedSubNo := strings.TrimSpace(customer.SubscriberNumber)
      if trimmedSubNo == "" {
          customer.SubscriberNumber = s.GetNextSubscriberNumber()
      } else {
          customer.SubscriberNumber = trimmedSubNo
          // Strict duplicate check before inserting
          var existing models.Customer
          if err := s.db.Where("TRIM(LOWER(subscriber_number)) = TRIM(LOWER(?)) AND is_deleted = false", customer.SubscriberNumber).First(&existing).Error; err == nil && existing.ID > 0 {
              return nil, fmt.Errorf("رقم المشترك [%s] مسجل مسبقاً للمشترك [%s]! يمنع منعاً باتاً تكرار رقم المشترك.", customer.SubscriberNumber, existing.FullName)
          }
      }
      ...
      err := s.db.Create(customer).Error
      if err != nil {
          if strings.Contains(err.Error(), "duplicate key") || strings.Contains(err.Error(), "unique") || strings.Contains(err.Error(), "uq_customers_subscriber_number") {
              return nil, fmt.Errorf("رقم المشترك [%s] مسجل مسبقاً لمشترك آخر في قاعدة البيانات!", customer.SubscriberNumber)
          }
          return nil, err
      }
  ```

- **`UpdateCustomer`** (`server/internal/services/customer_service.go:313-344`):
  ```go
  if subNoVal, ok := updates["subscriber_number"].(string); ok {
      trimmedSubNo := strings.TrimSpace(subNoVal)
      if trimmedSubNo != "" && !strings.EqualFold(trimmedSubNo, strings.TrimSpace(customer.SubscriberNumber)) {
          var existing models.Customer
          if err := s.db.Where("TRIM(LOWER(subscriber_number)) = TRIM(LOWER(?)) AND id != ? AND is_deleted = false", trimmedSubNo, id).First(&existing).Error; err == nil && existing.ID > 0 {
              return nil, fmt.Errorf("رقم المشترك [%s] مسجل مسبقاً للمشترك [%s]! يمنع تكرار رقم المشترك.", trimmedSubNo, existing.FullName)
          }
          updates["subscriber_number"] = trimmedSubNo
      }
  }
  ```

- **`UpdateGridCell`** (`server/internal/services/customer_service.go:347-446`):
  ```go
  var newSubNum string
  if subNum, ok := payload["subscriber_number"].(string); ok && subNum != "" {
      newSubNum = strings.TrimSpace(subNum)
  } else if subNum, ok := payload["subNumber"].(string); ok && subNum != "" {
      newSubNum = strings.TrimSpace(subNum)
  }
  if newSubNum != "" && !strings.EqualFold(newSubNum, strings.TrimSpace(customer.SubscriberNumber)) {
      var existing models.Customer
      if err := tx.Where("TRIM(LOWER(subscriber_number)) = TRIM(LOWER(?)) AND id != ? AND is_deleted = false", newSubNum, customer.ID).First(&existing).Error; err == nil && existing.ID > 0 {
          return fmt.Errorf("رقم المشترك [%s] مسجل مسبقاً للمشترك [%s]! يمنع تكرار رقم المشترك.", newSubNum, existing.FullName)
      }
      customerUpdates["subscriber_number"] = newSubNum
  }
  ```

- **Anti-Duplication Enforcement Assessment**:
  1. **Exact Matches**: Both application pre-checks and database constraints strictly block duplicate subscriber numbers with clear Arabic error messages.
  2. **Leading-Zero Normalized Matches**: **NOT prevented** in current Go backend code or PostgreSQL schema. For example, if subscriber `1001` exists, an input of `01001` or `001001` is not detected by `TRIM(LOWER(...))` and will bypass the database unique index (`uq_customers_subscriber_number_clean` only trims whitespace and lowers case).

---

### 1.3 Survey of Runtime Behavior

#### 1.3.1 Auto-Launching Browser to `http://localhost:3000`
- **Location**: `server/cmd/server/main.go` (Lines 221-246):
  ```go
  // 10. Auto-open default browser on start
  go func() {
      time.Sleep(800 * time.Millisecond)
      openURL(fmt.Sprintf("http://localhost:%s", cfg.Port))
  }()

  // 11. Start Server Listener
  addr := fmt.Sprintf(":%s", cfg.Port)
  log.Printf("🌐 Server listening on http://localhost%s", addr)
  if err := app.Listen(addr); err != nil {
      log.Fatalf("Server stopped: %v", err)
  }

  func openURL(url string) {
      var cmd *exec.Cmd
      switch runtime.GOOS {
      case "windows":
          cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", url)
      case "darwin":
          cmd = exec.Command("open", url)
      default:
          cmd = exec.Command("xdg-open", url)
      }
      _ = cmd.Start()
  }
  ```
- **Configuration**:
  - `server/internal/config/config.go:35-38`: `PORT` environment variable defaults to `"3000"`.
  - On Windows startup, the launcher triggers `rundll32 url.dll,FileProtocolHandler http://localhost:3000` after an 800ms stabilization sleep.

#### 1.3.2 Subsequent Restarts, Skipping Re-initialization & Preserving Records
- **Implementation in `server/internal/database/db_lifecycle.go`**:
  - **Idempotency Flag Check** (Lines 86-90):
    ```go
    flagFile := filepath.Join(m.DataDir, ".db_initialized")
    needsInit := false
    if _, err := os.Stat(flagFile); os.IsNotExist(err) {
        needsInit = true
    }
    ```
  - **First-Time Cluster Init** (Lines 93-98):
    Executed only if `needsInit == true`.
  - **Stale PID Lock Recovery** (Lines 101, 139-158):
    Reads `postmaster.pid`. Executes `tasklist /FI "PID eq <pid>"` to check if the PID is genuinely active. If not found, removes `postmaster.pid` to allow clean recovery after abnormal termination.
  - **Embedded Engine Startup** (Lines 104-107, 160-196):
    Executes `pg_ctl.exe -D <DataDir> -l <server.log> -o "-p 15432 -h 127.0.0.1" start`, and pings `postgres://postgres@127.0.0.1:15432` until healthy (up to 15s timeout).
  - **First-Time Schema Seeding & Flag Writing** (Lines 110-118):
    Imports `init_schema.sql` via `psql.exe` and writes `.db_initialized`.
  - **Subsequent Restarts**:
    Because `.db_initialized` exists, `needsInit` is `false`. Both `initdb` and `createDatabaseAndSeed` are skipped, completely preserving the database cluster, customer records, readings, invoices, and payments.
  - **Graceful Shutdown** (Lines 233-245):
    `Stop()` executes `pg_ctl.exe -D <DataDir> -m fast stop`.
- **Architectural Disconnect in `server/cmd/server/main.go`**:
  - `server/cmd/server/main.go:34` currently connects to `cfg.DatabaseURL` directly via `database.InitDB(cfg)` (connecting to `localhost:5432`).
  - `main.go` **does not call** `database.NewDBLifecycleManager()` or `m.EnsureDatabaseReady()`, and does not bind `m.Stop()` to application termination signals (`SIGINT`, `SIGTERM`).
  - To fulfill R2 of the installer requirements, `main.go` must initialize and invoke `DBLifecycleManager` prior to calling `database.InitDB`.

---

### 1.4 Survey of Existing Test Suites & Runners
1. **Python End-to-End Test Suites**:
   - `test_financial_suite.py` (324 lines):
     - Comprehensive E2E test running against `http://127.0.0.1:3000/api`.
     - Tests JWT authentication (`/auth/login`).
     - Tests settings retrieval (`/settings`).
     - Creates dedicated test customer (`/customers`).
     - Modifies ExcelGrid cells across 6 consecutive billing cycles (August 2 -> September 1 -> October 1 -> November 1 -> December 1 -> January 1 2027) via `/customers/{id}/grid-cell`.
     - Validates mathematical formulas: `Consumption`, `Consumption Cost`, `Total Amount`, `Arrears`, `Total Due`, `Remaining`.
     - Validates chronological forward waterfall cascading and payment allocations (Full, Partial, Overpayment/Credit Surplus).
   - `test_whatsapp_and_ui.py` (87 lines):
     - Tests WhatsApp message queueing (`/whatsapp/send-test`, `/whatsapp/messages`).
     - Tests analytics summaries (`/analytics/dashboard-summary`, `/analytics/monthly-performance`).
     - Tests audit logging system (`/audit/logs`).
2. **SQL Database Verification Suites** (`database/tests/`):
   - `test_monotonic_guard.sql`: Tests that non-monotonic meter readings (`reading_value < previous_reading`) raise `check_violation`.
   - `test_deterministic_invoicing.sql`: Tests deterministic composite invoice numbering (`INV-[Cycle]-[SubscriberNumber]`).
   - `test_waterfall_allocation.sql`: Tests FIFO waterfall payment allocations across multiple invoices.
   - `test_retroactive_recalc.sql`: Tests PL/pgSQL cascading recalculation function `rpc_recalculate_customer_cascade`.
3. **Go Unit & Stress Test Suites**:
   - `server/internal/services/financial_test.go`:
     - `TestPhoneNormalization`: 12 test cases verifying Yemeni phone formatting (`734019059` -> `967734019059`).
     - `TestToEnglishDigits`: Verifies Eastern Arabic (٠-٩) and Persian (۰-۹) numerals conversion to English digits (0-9).
     - `TestFinancialArithmeticFormula`: Validates consumption, consumption value, fixed fees, arrears, and total due arithmetic.
     - `TestFIFOWaterfallAlgorithm`: Verifies FIFO payment allocation across unpaid invoice arrays.
   - `server/internal/services/auth_service_test.go`: Tests Bcrypt hash generation and comparison.
   - `server/cmd/seed_and_verify/main.go` (508 lines):
     - Seeder script that generates customers across routes and runs checks on Arabic numeral absence, grid cell edits, and recalculation triggers.

---

## 2. Logic Chain

1. **Observation 1.1** demonstrates that `dist_portable/schema/init_schema.sql` line 7524 implements `uq_customers_subscriber_number_clean` as:
   `CREATE UNIQUE INDEX uq_customers_subscriber_number_clean ON public.customers USING btree (TRIM(BOTH FROM lower((subscriber_number)::text))) WHERE (is_deleted = false);`
2. **Observation 1.2** demonstrates that in Go backend `customer_service.go`, `CreateCustomer` (L152), `UpdateCustomer` (L325), and `UpdateGridCell` (L426) query:
   `TRIM(LOWER(subscriber_number)) = TRIM(LOWER(?))`
3. From (1) and (2), both the application code and the database index strip whitespace and lowercase the input, but neither removes leading zeros (`^0+`).
4. Therefore, subscriber `0100` and `100` are currently considered distinct and can coexist in the database without triggering any unique constraint violation.
5. To satisfy Requirement R3 (`ORIGINAL_REQUEST.md:265`), the index definition must be changed to:
   `CREATE UNIQUE INDEX uq_customers_subscriber_number_clean ON public.customers USING btree (REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', '')) WHERE (is_deleted = false);`
   and the Go backend pre-checks must normalize subscriber numbers by removing leading zeros before comparison.
6. **Observation 1.3.1** demonstrates that `cmd/server/main.go:222-225` already implements browser auto-launch to `http://localhost:3000` via `openURL` using Windows `rundll32 url.dll,FileProtocolHandler`.
7. **Observation 1.3.2** demonstrates that `db_lifecycle.go` implements the required logic for first-time `initdb`, seeding, `.db_initialized` idempotency marker, stale PID cleanup, and subsequent restart bypass.
8. However, **Observation 1.3.2** also proves that `cmd/server/main.go` never invokes `DBLifecycleManager` and currently connects directly to external/default PostgreSQL at `localhost:5432`.
9. Therefore, while the self-healing and restart lifecycle logic is fully coded in `db_lifecycle.go`, it is dormant until wired into `main.go` and connected to process termination signals.
10. **Observation 1.4** cataloged multiple comprehensive test runners (Python E2E, SQL unit tests, Go tests) that can be run to verify the entire system end-to-end once compiled.

---

## 3. Caveats

- Investigation was strictly read-only; no code files were modified and no build commands were executed.
- `SmartPowerERP.exe` in `dist_portable` is an existing compiled binary (34.6 MB). Whether it was compiled before or after `db_lifecycle.go` was created cannot be confirmed by static inspection alone, but the source code in `server/cmd/server/main.go` currently lacks the invocation call.
- The `dist_portable/schema/init_schema.sql` file contains 495 customer records, whereas `ORIGINAL_REQUEST.md:256` mentions "494 customers". All 495 records in `init_schema.sql` are active and unique; the 494 vs 495 distinction is a trivial 1-record discrepancy in the seed dataset.

---

## 4. Conclusion

1. **Unique Index & Anti-Duplication**:
   - Current state: Exact matches are strictly prevented at both DB and Go levels. Leading-zero variations (`0123` vs `123`) are **NOT prevented** because neither `uq_customers_subscriber_number_clean` nor `customer_service.go` applies regex zero-stripping.
   - Action needed: Update index expression to `REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', '')` in `init_schema.sql` and add leading-zero normalization in `customer_service.go` for `CreateCustomer`, `UpdateCustomer`, and `UpdateGridCell`.
2. **Runtime Auto-Launch**:
   - Verified present and active in `server/cmd/server/main.go:222-246`, opening `http://localhost:3000` via Windows `rundll32` after 800ms.
3. **Database Lifecycle & Restart Preservation**:
   - Implemented in `server/internal/database/db_lifecycle.go` with `.db_initialized` check, stale PID removal, and `pg_ctl` management.
   - Requires wiring into `server/cmd/server/main.go` so that `SmartPower.exe` initializes embedded PostgreSQL on port `15432` on startup and gracefully stops on exit.
4. **Test Infrastructure**:
   - High-quality automated suites exist: `test_financial_suite.py` for API/ExcelGrid E2E verification, `test_whatsapp_and_ui.py` for WhatsApp/audit verification, `database/tests/*.sql` for PostgreSQL constraints, and `server/internal/services/financial_test.go` for arithmetic/formatting unit tests.

---

## 5. Verification Method

To independently verify these findings:
1. **Inspect Unique Index**:
   ```powershell
   Select-String -Path "d:\elctercity\dist_portable\schema\init_schema.sql" -Pattern "uq_customers_subscriber_number_clean" -Context 0,2
   ```
2. **Inspect Backend Duplicate Checks**:
   View lines 145-155, 321-330, and 418-430 in `d:\elctercity\server\internal\services\customer_service.go`.
3. **Inspect Main Go Entrypoint & Database Connection**:
   View lines 30-40, 220-246 in `d:\elctercity\server\cmd\server\main.go`.
4. **Run Customer Verification Script**:
   ```powershell
   python d:\elctercity\.agents\explorer_survey_3\check_customers.py
   ```
5. **Run Existing Test Suites** (when application is running on port 3000):
   ```powershell
   python d:\elctercity\test_financial_suite.py
   python d:\elctercity\test_whatsapp_and_ui.py
   ```
