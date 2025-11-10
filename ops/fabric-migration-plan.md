# Fabric-Only Target Architecture & Migration Playbook

Last updated: <!-- TODO: update when doc changes -->

## 1. Goals & Non-Goals
- **Goals**: run the entire write-back flow inside Microsoft Fabric, push all business logic into Fabric SQL (warehouse) stored procedures/triggers, surface curated data through Power BI only, and keep the solution “RPA friendly” via SQL event surfaces.
- **Non-Goals**: reusing Azure Logic Apps, Azure SQL, or Terraform modules from `infra/`; keeping non-Fabric resource groups; supporting on-premises runtimes (these can be revisited later).

## 2. Target-State Overview

| Layer | Fabric Service | Responsibilities |
| --- | --- | --- |
| Workspace & Capacity | Fabric F64 (dev/test) / F128 (prod) | Host Lakehouse, Warehouse, Power BI artifacts, notebooks, pipelines. |
| Ingestion | Dataflows Gen2, Event Streams, Pipelines | Land source data into OneLake delta tables; standardize writes into staging tables. |
| Core Data | Fabric Warehouse (`ot_writeback_wh`) | Canonical SQL endpoint; houses staging, curated, and operational tables plus stored procedures and triggers. |
| Business Logic | Warehouse stored procedures + AFTER/INSTEAD OF triggers | Enforce validation, orchestration, and downstream notifications previously handled by Logic Apps. |
| Analytics | Power BI semantic model (Direct Lake or DirectQuery on Warehouse) | Serves reports, write-back experiences, and Teams embed. |
| Automation | Fabric Pipelines + Fabric CI/CD (deployment pipelines or Git integration) | Refresh metadata, run regression test queries, publish PBIX/semantic models. |
| Security | Purview (optional), Azure AD groups synced to Fabric roles, Dynamic Data Masking inside Warehouse | Row-level security for write-back scenarios, auditing via Warehouse audit logs to Log Analytics workspace in Defender for Cloud Apps. |

## 3. Component Architecture

1. **Fabric Workspace Topology**
   - `ot-writeback-dev`, `ot-writeback-test`, `ot-writeback-prod` workspaces, each bound to the matching Fabric capacity.
   - Enable Git integration (main branch) so workspace items map back into this repo under `/fabric/<workspace>/<item>`.
2. **OneLake & Storage**
   - Create a Lakehouse to land raw files if upstream systems drop CSV/Parquet; optionally skip if all sources are SQL-like.
   - Use shortcut folders for any external ADLS data that the Warehouse must read.
3. **Fabric Warehouse (SQL Endpoint)**
   - Database name: `ot_writeback_wh`.
   - Schemas: `stg`, `ops`, `dim`, `fact`, `meta`, mirroring `ops/sql/schema.sql`.
   - Use Fabric-native features (Result Set Caching, Warehouse Mirroring) for scale-out.
4. **Business Logic Migration**
   - Stored procedures implement workflows (`usp_submit_writeback`, `usp_route_approval`, `usp_notify_rpa`).
   - Triggers fire on insert/update for operational tables to call orchestration procs and populate audit/log tables.
   - Replace Logic App connectors with `sp_invoke_external_rest_endpoint` (preview) or queue table plus Fabric Event Streams if external calls remain necessary.
5. **Power BI Layer**
   - Dataset: `ot_writeback_model` pointing to Warehouse via Direct Lake (preferred) or DirectQuery.
   - Reports: `ot_writeback_app.pbix` stored under `/bi/`.
   - Use write-back pattern through Power BI Power Apps visual or TMDL editing to connect to stored procs via Fabric SQL endpoint.
6. **Operational Monitoring**
   - Use Warehouse Query Insights for performance; push audit/query history into Defender for DevOps or Log Analytics via Export Rules.
   - Create Fabric metric rules/alerts for failed pipelines, long-running procs, stale refreshes.

## 4. Development & Deployment Approach

1. **Source Control Layout**
   - Add `/fabric/` folder to mirror workspace items (Warehouse schema scripts, Dataflows, Pipelines definitions exported via Git integration).
   - Keep SQL canonical definitions under `ops/sql/` and generate Fabric Warehouse migrations using `sqlcmd` or `.dsql` files executed via Fabric Pipeline notebook.
2. **Environment Promotion**
   - Use Fabric Deployment Pipelines (Dev → Test → Prod); map workspace items (Warehouse, Lakehouse, Pipelines, Power BI dataset & reports).
   - For SQL schema, push via stage-specific Fabric Pipelines that run `EXEC` scripts stored in this repo and parameterized with environment metadata tables.
3. **Testing**
   - Create stored procedure unit tests using T-SQL (e.g., `tSQLt`) or simple assert scripts executed inside Fabric Warehouse.
   - Data quality checks run as Warehouse jobs scheduled daily.
4. **Operational Runbooks**
   - Document refresh cadence, scaling rules, and rollback steps under `ops/runbooks/` (to be created).

## 5. Detailed Migration To-Do List

### Phase 0 — Discovery & Fabric Setup
1. Inventory current Logic App workflows, connectors, secrets, and SQL dependencies (`app/logicapp/**`, `ops/sql/*`).
2. Identify all SQL objects required for write-back, including procs referenced in Logic App HTTP actions.
3. Provision Fabric capacities & workspaces; enable Git integration against this repo.
4. Create Fabric Warehouse skeleton (schemas only) using scripts converted from `ops/sql/schema.sql`.

### Phase 1 — Data & Schema Migration
1. Map every table/view in `ops/sql/schema.sql` to Fabric Warehouse-compatible DDL; adjust data types (e.g., `NVARCHAR` vs `VARCHAR`, `DATETIME2` vs `DATETIME`).
2. Move seed data (`deploy.sql`, `smoke.sql`) into Fabric scripts; create Fabric Pipeline activity `Deploy-Core-Schema`.
3. Configure Fabric shortcuts/external sources for any upstream operational systems; document connection secrets in Fabric workspace parameters.
4. Validate DDL parity by running regression queries from `ops/sql/smoke.sql` inside Warehouse.

### Phase 2 — Business Logic Refactor
1. Translate Logic App steps into stored procedures:
   - HTTP calls → `sp_invoke_external_rest_endpoint` or queue table processed by Power BI / Fabric pipeline.
   - Condition branches → procedural logic inside `BEGIN ... END`.
   - Parallel actions → split procedures invoked by Service Broker-like queue tables or scheduled jobs.
2. Build triggers on the main write-back tables to call the new orchestration procs.
3. Encode validations as scalar/table-valued functions referenced by the triggers/procs.
4. Implement audit tables mirroring Logic App run history (status, duration, payload hash).
5. Write regression harness in `ops/sql/tests/*.sql` that simulates inserts/updates and asserts downstream results.

### Phase 3 — Fabric Pipelines & Automation
1. Recreate any Logic App timers or recurrence triggers as Fabric Pipeline schedules.
2. Implement deployment pipeline stages:
   - Stage task to run schema migrations via Warehouse connection.
   - Stage task to copy Dataflow/Data Pipeline definitions.
   - Stage task to refresh semantic models post-deploy.
3. Configure notifications (Teams/Email) via Fabric Pipeline alerting or `sp_send_dbmail` equivalent (currently not native—use external REST endpoint to call Graph).

### Phase 4 — Power BI Alignment
1. Update PBIX files under `/bi/` to point to Fabric Warehouse using Direct Lake.
2. Refactor dataset parameters to use Fabric workspace connection strings.
3. Adjust write-back visuals to call Warehouse stored procedures (Power Apps visual or custom visuals hitting Fabric SQL endpoint).
4. Update deployment pipelines for Power BI items and test cross-environment parameter swaps.

### Phase 5 — Security & Governance
1. Create Fabric-native security groups (e.g., `SG_OT_Writeback_Authors`, `SG_OT_Writeback_Operators`, `SG_OT_Writeback_Consumers`) and map them to Warehouse roles.
2. Implement row-level security policies in Warehouse and propagate them to Power BI model.
3. Configure audit/export rules to Log Analytics (Defender for Cloud Apps) for compliance.
4. Document break-glass procedures and key rotation strategy (Key Vault references replaced by Fabric workspace connections).

### Phase 6 — Cut-Over & Decommissioning
1. Run parallel tests comparing Azure SQL + Logic App outputs vs Fabric Warehouse procs for at least one full business cycle.
2. Update DNS/connection strings used by downstream tools (RPA, Power Apps) to point to Fabric Warehouse SQL endpoint.
3. Disable Logic Apps and Azure SQL after sign-off; archive Terraform state and infra modules for reference.
4. Monitor Fabric workloads closely (capacity metrics, query performance) for two weeks; tune as needed.

## 6. Deliverables Checklist
- [ ] Fabric workspace Git-backed folder structure checked into `/fabric/`.
- [ ] Warehouse DDL + migrations under `ops/sql/fabric/`.
- [ ] Stored procedure + trigger library with automated tests.
- [ ] Fabric Pipeline definitions (`fabric/pipelines/`) and deployment pipeline configuration doc.
- [ ] Updated Power BI dataset/report files with Fabric connections.
- [ ] Runbooks for operations, monitoring, and incident response in `ops/runbooks/`.
- [ ] Updated README pointing to Fabric-only approach (future task).

## 7. Suggested Work Breakdown for a Junior Developer
1. **Week 1:** Stand up Fabric dev workspace, import schema, run smoke tests.
2. **Week 2:** Translate Logic App sequence into `usp_submit_writeback` procedure; add triggers and unit tests.
3. **Week 3:** Build Fabric Pipeline automation and hook up Power BI dataset to Warehouse.
4. **Week 4:** Harden security, finalize deployment pipeline, rehearse cut-over.

## 8. Reference Patterns
- Fabric Warehouse stored proc calling external endpoint: [sp_invoke_external_rest_endpoint](https://learn.microsoft.com/fabric/data-warehouse/external-rest-endpoint).
- Power BI Direct Lake write-back guidance: [Microsoft docs link placeholder].
- Fabric Git integration workflow: `https://learn.microsoft.com/fabric/cicd/git-integration/`.

> Keep this document living—update each section as tasks complete or scope changes.
