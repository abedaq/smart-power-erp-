## 2026-09-02T07:37:17Z
You are a Worker responsible for Milestone 3 (M3): Final Distribution Package Consolidation & Sanity Verification for Smart Power ERP.
Read the authoritative request at: d:/elctercity/.agents/ORIGINAL_REQUEST.md
Read the project specification at: d:/elctercity/PROJECT.md
Your assigned working directory: d:/elctercity/.agents/worker_m3_dist

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Scope & Tasks:
1. Ensure both distribution directories exist: d:/elctercity/dist_output and d:/elctercity/حزمة_التطبيقات_النهائية.
2. Copy and synchronize the newly compiled Windows Desktop installer from d:/elctercity/build_installer_output/SmartPower_Station_ERP_Desktop_Setup_v1.0.exe to both d:/elctercity/dist_output and d:/elctercity/حزمة_التطبيقات_النهائية.
3. Copy and synchronize the latest Android Mobile Release APK from d:/elctercity/SmartPowerCollector_v2.apk to both d:/elctercity/dist_output and d:/elctercity/حزمة_التطبيقات_النهائية (as SmartPowerCollector_v2.apk and/or SmartPower_Collector_Mobile_v1.0.apk).
4. Update/Create the installation & user guide in Arabic (دليل_التثبيت_والاستخدام.txt) in both distribution directories, including system requirements, installation steps, and verification checksums.
5. Generate a formal SHA256 checksums file (CHECKSUMS.txt / SHA256SUMS.txt) in both distribution directories for all artifacts.
6. Execute automated sanity verification:
   - Backend comprehensive audit test: cd d:/elctercity/backend && npx ts-node src/scripts/run_comprehensive_audit_test.ts
   - Backend RBAC route audit: cd d:/elctercity/backend && npx ts-node src/scripts/test_rbac_routes.ts
   - Mobile test suite: cd d:/elctercity/mobile_app && flutter test
   - File integrity check: Verify SHA256 checksums and exact byte sizes of all final artifacts in dist_output and حزمة_التطبيقات_النهائية.
7. Record all outputs, checksums, sizes, sanity check logs, and verification commands in d:/elctercity/.agents/worker_m3_dist/handoff.md.

Report completion back via send_message.
