## 2026-09-02T16:45:00Z
Received mission: Backend Specialist Survey on Interactive Excel Grid View & WhatsApp Auto-Approval Engine.
Covering:
1. `backend/src/controllers/todayReadings.controller.ts` and related routes/models/services.
2. What fields exist and what changes are needed to support `lost_units`, `service_fee` (monthly fixed fee), `current_reading`, `previous_reading`, `arrears`, and `paid_amount` inline updates.
3. The exact formula calculations:
   - Consumption = Current - Previous
   - Lost Units Cost = Lost Units * Unit Price
   - Consumption Cost = Consumption * Unit Price (or tariff slabs if applicable)
   - Total Due = Consumption Cost + Fixed Fee + Lost Units Cost + Arrears
   - Remaining = Total Due - Paid
4. The approval flow / RPC controller:
   - Updating reading & invoice status to 'APPROVED'
   - Updating customer total due balance
   - Rendering & queuing WhatsApp invoice image / notification upon clicking approval
5. Any existing database schemas/migrations, constraints, or transaction logic involved.
