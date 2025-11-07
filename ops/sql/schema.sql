/* ======================================================================
   Accounting Notes + Lightweight Approvals
   Final Optimized Schema (OLTP write tier: Azure SQL DB / SQL Server)
   ----------------------------------------------------------------------
   Design goals:
   - Append-only for audit-heavy tables (notes, actions)
   - Low-latency writes with stable seeks on (EntityType, BusinessKey)
   - Scale via computed 64-bit hash + composite indexes (addr → recent)
   - Idempotency (RequestId) to prevent duplicate inserts from retries
   - Provenance fields (SourceSystem/CorrelationId) for tracing
   - Concurrency safety on mutable rows (rowversion)
   ====================================================================== */

-- (Optional) Dedicated schema for isolation
-- CREATE SCHEMA ops AUTHORIZATION dbo;

---------------------------------------------------------------------------
-- 0) Core entity anchor: generic address for any business record
--    (e.g., 'Invoice' + 'INV-00012345'). You may pre-populate this table
--    or use the address pair directly in child tables without FK.
---------------------------------------------------------------------------
IF OBJECT_ID('dbo.Entity','U') IS NOT NULL DROP TABLE dbo.Entity;
CREATE TABLE dbo.Entity (
    EntityID        BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY, -- internal surrogate
    EntityType      VARCHAR(64)  NOT NULL,                     -- 'Invoice','Deal','Customer', etc.
    BusinessKey     VARCHAR(128) NOT NULL,                     -- business-meaningful key
    SurrogateKey    BIGINT       NULL,                         -- optional pointer to DW key
    CreatedUTC      DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_Entity UNIQUE (EntityType, BusinessKey)      -- fast lookup / no dupes
);

---------------------------------------------------------------------------
-- 1) Entity-level ACL (optional but common in accounting)
--    Fine-grained read/write visibility that can feed PBI RLS.
---------------------------------------------------------------------------
IF OBJECT_ID('dbo.EntityAcl','U') IS NOT NULL DROP TABLE dbo.EntityAcl;
CREATE TABLE dbo.EntityAcl (
    EntityType    VARCHAR(64)  NOT NULL,
    BusinessKey   VARCHAR(128) NOT NULL,
    PrincipalUPN  VARCHAR(256) NOT NULL,  -- person/group identity
    CanView       BIT NOT NULL DEFAULT 0, -- read permission
    CanComment    BIT NOT NULL DEFAULT 0, -- write note/approve/comment
    PRIMARY KEY (EntityType, BusinessKey, PrincipalUPN)
);

---------------------------------------------------------------------------
-- 2) NOTES: append-only commentary per entity
--    High volume expected. Narrow, index-friendly row; attachments via URL.
---------------------------------------------------------------------------
IF OBJECT_ID('dbo.EntityNote','U') IS NOT NULL DROP TABLE dbo.EntityNote;
CREATE TABLE dbo.EntityNote (
    NoteID              BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    -- Address (duplicated for fast filters; FK to dbo.Entity optional)
    EntityType          VARCHAR(64)  NOT NULL,
    BusinessKey         VARCHAR(128) NOT NULL,

    -- Hash key for fast seeks/joins; deterministic 64-bit (CHECKSUM)
    EntityAddrHash AS CONVERT(BIGINT, CHECKSUM(CONCAT(EntityType, '#', BusinessKey))) PERSISTED,

    -- Content (keep narrow for hot paths; expand to NVARCHAR(MAX) only if truly needed)
    NoteText            NVARCHAR(2000) NOT NULL,               -- short narrative note text
    TagsCsv             NVARCHAR(512)  NULL,                   -- comma-separated tags (quick filter)
    AttachmentUrl       NVARCHAR(1024) NULL,                   -- SAS/SharePoint/OneDrive link

    -- Authorship / provenance
    CreatedByUPN        VARCHAR(256)  NOT NULL,                -- user principal (email-like)
    CreatedByDisplay    NVARCHAR(256) NULL,                    -- display name (optional)
    CreatedUTC          DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedIPAddress    VARCHAR(64)   NULL,                    -- optional IP for audit trail
    ClientReportName    NVARCHAR(256) NULL,                    -- optional originating report/page

    -- Visibility
    VisibilityScope     VARCHAR(32)   NOT NULL DEFAULT 'Private', -- 'Private'|'Team'|'Org'

    -- Idempotency & tracing (prevents dupes on retries, supports lineage)
    RequestId           UNIQUEIDENTIFIER NULL,                 -- client-generated GUID
    SourceSystem        VARCHAR(64)     NULL,                  -- 'PBI','API','BOT', etc.
    CorrelationId       UNIQUEIDENTIFIER NULL                   -- tie multiple related writes
);

-- Prevent duplicated notes on retried requests (allows NULLs)
CREATE UNIQUE INDEX UX_EntityNote_Idem
    ON dbo.EntityNote (RequestId)
    WHERE RequestId IS NOT NULL;

-- Hot path: "notes for this record, newest first"
CREATE NONCLUSTERED INDEX IX_EntityNote_Addr_Recent
    ON dbo.EntityNote (EntityAddrHash, EntityType, BusinessKey, CreatedUTC DESC)
    INCLUDE (CreatedByUPN, CreatedByDisplay, VisibilityScope, TagsCsv, AttachmentUrl);

-- Optional FK if you pre-seed dbo.Entity for every address used:
-- ALTER TABLE dbo.EntityNote
--   ADD CONSTRAINT FK_EntityNote_Entity
--   FOREIGN KEY (EntityType, BusinessKey) REFERENCES dbo.Entity(EntityType, BusinessKey);

---------------------------------------------------------------------------
-- 3) APPROVALS: lightweight workflow (rules, exceptions, instances, actions)
---------------------------------------------------------------------------

-- 3.1 Approver rules: who needs to approve a given EntityType (and optional stage)
IF OBJECT_ID('dbo.ApproverRule','U') IS NOT NULL DROP TABLE dbo.ApproverRule;
CREATE TABLE dbo.ApproverRule (
    RuleID            BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    EntityType        VARCHAR(64)  NOT NULL,               -- e.g., 'Invoice'
    StageCode         VARCHAR(64)  NOT NULL,               -- 'Submit','Finance','Final', etc.
    ApproverScope     VARCHAR(16)  NOT NULL,               -- 'User'|'Team'|'Role'
    ApproverRef       NVARCHAR(256) NOT NULL,              -- UPN / TeamId / RoleName
    RequireMode       VARCHAR(16)  NOT NULL DEFAULT 'Any', -- 'Any' | 'All' (All ⇒ required approvers)
    ThresholdType     VARCHAR(16)  NULL,                   -- NULL|'Count'|'Percent' (quorum math)
    ThresholdValue    DECIMAL(9,4) NULL,                   -- e.g., 2 or 0.60 (60%)
    ConditionJson     NVARCHAR(2000) NULL,                 -- optional predicates (amount > 100k)
    IsActive          BIT NOT NULL DEFAULT 1,              -- soft enable/disable
    Priority          INT NOT NULL DEFAULT 100,            -- lower first if overlaps
    CreatedUTC        DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
);
CREATE NONCLUSTERED INDEX IX_ApproverRule_Admin
  ON dbo.ApproverRule (EntityType, StageCode, IsActive, Priority);

-- 3.2 Exceptions: add/replace/waive approvers for scopes or specific records
IF OBJECT_ID('dbo.ApprovalException','U') IS NOT NULL DROP TABLE dbo.ApprovalException;
CREATE TABLE dbo.ApprovalException (
    ExceptionID       BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    EntityType        VARCHAR(64)  NOT NULL,
    BusinessKey       VARCHAR(128) NULL,               -- NULL = broad; set for a specific record
    StageCode         VARCHAR(64)  NULL,               -- NULL = applies across stages
    ExceptionKind     VARCHAR(16)  NOT NULL,           -- 'Waive'|'Add'|'Replace'
    ApproverScope     VARCHAR(16)  NULL,               -- needed for Add/Replace
    ApproverRef       NVARCHAR(256) NULL,              -- needed for Add/Replace
    Reason            NVARCHAR(1000) NULL,             -- human rationale
    EffectiveFromUTC  DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    EffectiveToUTC    DATETIME2(3) NULL,
    EnteredByUPN      VARCHAR(256) NOT NULL,           -- who entered the exception
    EnteredUTC        DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    IsActive          BIT NOT NULL DEFAULT 1
);
CREATE NONCLUSTERED INDEX IX_ApprovalException_Admin
  ON dbo.ApprovalException (EntityType, BusinessKey, StageCode, IsActive, EffectiveFromUTC)
  INCLUDE (EffectiveToUTC, ExceptionKind, ApproverScope, ApproverRef);

-- 3.3 Live approval instance: one per (EntityType, BusinessKey)
IF OBJECT_ID('dbo.ApprovalInstance','U') IS NOT NULL DROP TABLE dbo.ApprovalInstance;
CREATE TABLE dbo.ApprovalInstance (
    InstanceID        BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    EntityType        VARCHAR(64)  NOT NULL,
    BusinessKey       VARCHAR(128) NOT NULL,

    -- Hash for fast lookups / DW distribution
    EntityAddrHash AS CONVERT(BIGINT, CHECKSUM(CONCAT(EntityType, '#', BusinessKey))) PERSISTED,

    StageCode         VARCHAR(64)  NOT NULL DEFAULT 'Submit',              -- current stage
    Status            VARCHAR(16)  NOT NULL DEFAULT 'Pending',             -- 'Pending'|'InProgress'|'Approved'|'Rejected'|'Expired'
    ExceptionState    VARCHAR(16)  NOT NULL DEFAULT 'None',                -- 'None'|'HasActive'|'Ignored'
    SnapshotJson      NVARCHAR(2000) NULL,                                 -- materialized ruleset (post exceptions)
    RequestedByUPN    VARCHAR(256)  NOT NULL,                              -- who started/last reopened
    RequestedUTC      DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    LastRecalcUTC     DATETIME2(3)  NULL,                                  -- last assignment rebuild
    DueUTC            DATETIME2(3)  NULL,                                  -- optional SLA/expiry
    ClosedUTC         DATETIME2(3)  NULL,                                  -- set at terminal states

    -- Concurrency: detect write conflicts in UI/API
    RowVer            rowversion,

    CONSTRAINT UQ_ApprovalInstance UNIQUE (EntityType, BusinessKey)
);
CREATE NONCLUSTERED INDEX IX_ApprovalInstance_Addr
  ON dbo.ApprovalInstance (EntityAddrHash, EntityType, BusinessKey)
  INCLUDE (StageCode, Status, RequestedUTC, ClosedUTC, ExceptionState);

-- 3.4 Current assignments (expanded approvers)
IF OBJECT_ID('dbo.ApprovalAssignment','U') IS NOT NULL DROP TABLE dbo.ApprovalAssignment;
CREATE TABLE dbo.ApprovalAssignment (
    AssignmentID      BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    InstanceID        BIGINT NOT NULL
                      REFERENCES dbo.ApprovalInstance(InstanceID) ON DELETE CASCADE,
    ApproverScope     VARCHAR(16)  NOT NULL,             -- 'User'|'Team'|'Role'
    ApproverRef       NVARCHAR(256) NOT NULL,            -- UPN / TeamId / RoleName
    Required          BIT NOT NULL DEFAULT 1,            -- 1=required, 0=optional (threshold/quorum)
    Satisfied         BIT NOT NULL DEFAULT 0,            -- set when approvals satisfied
    SatisfiedUTC      DATETIME2(3) NULL,                 -- when satisfied

    -- Concurrency on mutable row
    RowVer            rowversion,

    CONSTRAINT UQ_ApprovalAssignment UNIQUE (InstanceID, ApproverScope, ApproverRef)
);
-- "My work" queue & dashboards: who still owes an action
CREATE NONCLUSTERED INDEX IX_ApprovalAssignment_MyWork
  ON dbo.ApprovalAssignment (ApproverScope, ApproverRef, Satisfied, Required, InstanceID)
  INCLUDE (SatisfiedUTC);

-- 3.5 Immutable action audit (append-only)
IF OBJECT_ID('dbo.ApprovalAction','U') IS NOT NULL DROP TABLE dbo.ApprovalAction;
CREATE TABLE dbo.ApprovalAction (
    ActionID          BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    InstanceID        BIGINT NOT NULL
                      REFERENCES dbo.ApprovalInstance(InstanceID) ON DELETE CASCADE,
    ActorUPN          VARCHAR(256) NOT NULL,            -- who did it
    ActionType        VARCHAR(16)  NOT NULL,            -- 'Approve'|'Reject'|'IgnoreException'|'Unignore'|'Comment'
    Comment           NVARCHAR(1000) NULL,              -- rationale / additional info
    CreatedUTC        DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),

    -- Idempotency & lineage for high-throughput pipelines
    RequestId         UNIQUEIDENTIFIER NULL,
    SourceSystem      VARCHAR(64)     NULL,
    CorrelationId     UNIQUEIDENTIFIER NULL
);
-- Prevent duplicate actions on retries
CREATE UNIQUE INDEX UX_ApprovalAction_Idem
  ON dbo.ApprovalAction (RequestId)
  WHERE RequestId IS NOT NULL;

-- Common query: latest actions by actor (audit / inbox)
CREATE NONCLUSTERED INDEX IX_ApprovalAction_ByActorRecent
  ON dbo.ApprovalAction (ActorUPN, CreatedUTC DESC)
  INCLUDE (ActionType, InstanceID, Comment);

---------------------------------------------------------------------------
-- 4) Lightweight reference maps (for Team/Role → User expansions if needed)
---------------------------------------------------------------------------
IF OBJECT_ID('dbo.TeamMember','U') IS NOT NULL DROP TABLE dbo.TeamMember;
CREATE TABLE dbo.TeamMember (
    TeamId      NVARCHAR(128) NOT NULL,
    MemberUPN   VARCHAR(256)  NOT NULL,
    IsActive    BIT NOT NULL DEFAULT 1,
    PRIMARY KEY (TeamId, MemberUPN)
);

IF OBJECT_ID('dbo.RoleMember','U') IS NOT NULL DROP TABLE dbo.RoleMember;
CREATE TABLE dbo.RoleMember (
    RoleName    NVARCHAR(128) NOT NULL,
    MemberUPN   VARCHAR(256)  NOT NULL,
    IsActive    BIT NOT NULL DEFAULT 1,
    PRIMARY KEY (RoleName, MemberUPN)
);

---------------------------------------------------------------------------
-- 5) Convenience views (BI/ops)
---------------------------------------------------------------------------

-- Notes joined to Entity (if you populate dbo.Entity)
IF OBJECT_ID('dbo.vEntityNote_ByEntity','V') IS NOT NULL DROP VIEW dbo.vEntityNote_ByEntity;
GO
CREATE VIEW dbo.vEntityNote_ByEntity AS
SELECT
  n.NoteID, n.EntityType, n.BusinessKey, n.EntityAddrHash,
  n.NoteText, n.TagsCsv, n.AttachmentUrl,
  n.CreatedByUPN, n.CreatedByDisplay, n.CreatedUTC, n.CreatedIPAddress, n.ClientReportName,
  n.VisibilityScope, n.RequestId, n.SourceSystem, n.CorrelationId,
  e.EntityID, e.SurrogateKey
FROM dbo.EntityNote AS n
LEFT JOIN dbo.Entity AS e
  ON e.EntityType = n.EntityType
 AND e.BusinessKey = n.BusinessKey;
GO

-- Status roll-up for approvals (counts of required/optional satisfied)
IF OBJECT_ID('dbo.vApprovalStatus','V') IS NOT NULL DROP VIEW dbo.vApprovalStatus;
GO
CREATE VIEW dbo.vApprovalStatus AS
SELECT
    i.EntityType,
    i.BusinessKey,
    i.EntityAddrHash,
    i.StageCode,
    i.Status,
    i.ExceptionState,
    i.RequestedByUPN,
    i.RequestedUTC,
    i.ClosedUTC,
    SUM(CASE WHEN a.Required = 1 THEN 1 ELSE 0 END) AS RequiredCount,
    SUM(CASE WHEN a.Required = 1 AND a.Satisfied = 1 THEN 1 ELSE 0 END) AS RequiredSatisfied,
    SUM(CASE WHEN a.Required = 0 THEN 1 ELSE 0 END) AS OptionalCount,
    SUM(CASE WHEN a.Required = 0 AND a.Satisfied = 1 THEN 1 ELSE 0 END) AS OptionalSatisfied
FROM dbo.ApprovalInstance i
LEFT JOIN dbo.ApprovalAssignment a
  ON a.InstanceID = i.InstanceID
GROUP BY
    i.EntityType, i.BusinessKey, i.EntityAddrHash,
    i.StageCode, i.Status, i.ExceptionState,
    i.RequestedByUPN, i.RequestedUTC, i.ClosedUTC;
GO

---------------------------------------------------------------------------
-- 6) (Optional) Partitioning stubs for very large tables (uncomment when ready)
--     Strategy: monthly partitions on CreatedUTC for append-only tables.
-- NOTE: Azure SQL DB supports partitioning on Enterprise/Business Critical SKUs.
--       If you’re on General Purpose and expect 100M+ rows, weigh SKU vs. sharding.
---------------------------------------------------------------------------

/*
-- Example: monthly partitions from 2023-01-01 to 2030-01-01 (extend as needed)
CREATE PARTITION FUNCTION PF_DateMonthly (DATETIME2(3))
AS RANGE RIGHT FOR VALUES (
  '2023-02-01','2023-03-01','2023-04-01','2023-05-01','2023-06-01','2023-07-01','2023-08-01','2023-09-01',
  '2023-10-01','2023-11-01','2023-12-01','2024-01-01','2024-02-01','2024-03-01','2024-04-01','2024-05-01',
  '2024-06-01','2024-07-01','2024-08-01','2024-09-01','2024-10-01','2024-11-01','2024-12-01',
  '2025-01-01','2025-02-01','2025-03-01','2025-04-01','2025-05-01','2025-06-01','2025-07-01','2025-08-01',
  '2025-09-01','2025-10-01','2025-11-01','2025-12-01','2026-01-01','2027-01-01','2028-01-01','2029-01-01','2030-01-01'
);

-- Single filegroup scheme (adjust FG per partition if needed)
CREATE PARTITION SCHEME PS_DateMonthly
AS PARTITION PF_DateMonthly
ALL TO ([PRIMARY]);

-- To place large tables on the scheme:
-- 1) Recreate with partitioned clustered index OR
-- 2) Create a clustered index ON PS_DateMonthly(CreatedUTC) then drop it if you prefer heap/other CI
-- Example (EntityNote):
-- CREATE CLUSTERED INDEX CX_EntityNote_Date
--   ON dbo.EntityNote (CreatedUTC)
--   ON PS_DateMonthly(CreatedUTC);
*/

---------------------------------------------------------------------------
-- 7) Synapse/Fabric DW landing guidance (not executed here)
--    - Use CLUSTERED COLUMNSTORE INDEX for large tables
--    - DISTRIBUTION = HASH(EntityAddrHash) on: EntityNote, ApprovalAction, ApprovalAssignment
--    - DISTRIBUTION = REPLICATE for small reference: ApproverRule, ApprovalException, TeamMember, RoleMember, Entity (if small)
--    - PARTITION BY RANGE (CreatedUTC) MONTHLY for EntityNote, ApprovalAction
---------------------------------------------------------------------------

/* Example Synapse DDL sketch (do this in Synapse, not here)

CREATE TABLE dbo.EntityNote (
  ...
)
WITH (
  DISTRIBUTION = HASH(EntityAddrHash),
  CLUSTERED COLUMNSTORE INDEX,
  PARTITION (CreatedUTC RANGE RIGHT FOR VALUES ('2024-01-01', '2024-02-01', ...))
);
*/

-- End of schema


/* ======================================================================
   STORED PROCEDURES – LIGHTWEIGHT APPROVAL WORKFLOW
   Notes:
   - These assume the tables from your schema.sql exist.
   - This version is GENERIC (no dependency on dbo.Loan). If you later
     add the Loan/IRR conditions, swap in the Oaktree variant of
     usp_Approval_Recalculate we shared earlier.
   ====================================================================== */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- Start or reopen approval instance
CREATE OR ALTER PROC dbo.usp_Approval_Start
  @EntityType VARCHAR(64),
  @BusinessKey VARCHAR(128),
  @RequestedByUPN VARCHAR(256),
  @StageCode VARCHAR(64) = 'Submit'
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @InstanceID BIGINT;

  IF EXISTS (SELECT 1 FROM dbo.ApprovalInstance WHERE EntityType=@EntityType AND BusinessKey=@BusinessKey)
  BEGIN
    UPDATE dbo.ApprovalInstance
      SET StageCode=@StageCode, Status='Pending', RequestedByUPN=@RequestedByUPN,
          RequestedUTC=SYSUTCDATETIME(), ClosedUTC=NULL
      WHERE EntityType=@EntityType AND BusinessKey=@BusinessKey;

    SELECT @InstanceID = InstanceID
    FROM dbo.ApprovalInstance
    WHERE EntityType=@EntityType AND BusinessKey=@BusinessKey;
  END
  ELSE
  BEGIN
    INSERT dbo.ApprovalInstance (EntityType, BusinessKey, StageCode, RequestedByUPN)
    VALUES (@EntityType, @BusinessKey, @StageCode, @RequestedByUPN);
    SET @InstanceID = SCOPE_IDENTITY();
  END

  EXEC dbo.usp_Approval_Recalculate @InstanceID;
  SELECT @InstanceID AS InstanceID;
END;
GO

-- Recalculate assignments and status (generic rules + exceptions)
CREATE OR ALTER PROC dbo.usp_Approval_Recalculate
  @InstanceID BIGINT
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @EntityType VARCHAR(64), @BusinessKey VARCHAR(128), @StageCode VARCHAR(64);
  SELECT @EntityType=EntityType, @BusinessKey=BusinessKey, @StageCode=StageCode
  FROM dbo.ApprovalInstance WHERE InstanceID=@InstanceID;

  -- Clear existing assignments
  DELETE FROM dbo.ApprovalAssignment WHERE InstanceID=@InstanceID;

  ;WITH BaseRules AS (
    SELECT * FROM dbo.ApproverRule
    WHERE EntityType=@EntityType AND StageCode=@StageCode AND IsActive=1
  ),
  ActiveExceptions AS (
    SELECT * FROM dbo.ApprovalException
     WHERE EntityType=@EntityType
       AND (BusinessKey IS NULL OR BusinessKey=@BusinessKey)
       AND (StageCode IS NULL OR StageCode=@StageCode)
       AND IsActive=1
       AND EffectiveFromUTC <= SYSUTCDATETIME()
       AND (EffectiveToUTC IS NULL OR EffectiveToUTC >= SYSUTCDATETIME())
  ),
  RulesAfterExceptions AS (
    -- Remove waived/replaced approvers
    SELECT r.*
    FROM BaseRules r
    WHERE NOT EXISTS (
      SELECT 1 FROM ActiveExceptions ex
      WHERE (ex.ExceptionKind IN ('Replace','Waive'))
        AND ex.ApproverScope=r.ApproverScope AND ex.ApproverRef=r.ApproverRef
    )
    UNION ALL
    -- Add extra approvers
    SELECT
      NULL AS RuleID, @EntityType, COALESCE(ex.StageCode, @StageCode),
      ex.ApproverScope, ex.ApproverRef,
      'Any' AS RequireMode, NULL, NULL, NULL, 1, 50, SYSUTCDATETIME()
    FROM ActiveExceptions ex
    WHERE ex.ExceptionKind='Add'
      AND ex.ApproverScope IS NOT NULL AND ex.ApproverRef IS NOT NULL
  )
  INSERT dbo.ApprovalAssignment (InstanceID, ApproverScope, ApproverRef, Required)
  SELECT DISTINCT
         @InstanceID,
         ApproverScope,
         ApproverRef,
         CASE WHEN RequireMode='All' THEN 1 ELSE 0 END
  FROM RulesAfterExceptions;

  -- Exception flag + status
  DECLARE @HasEx BIT = CASE WHEN EXISTS (SELECT 1 FROM ActiveExceptions) THEN 1 ELSE 0 END;

  UPDATE dbo.ApprovalInstance
    SET ExceptionState = CASE WHEN @HasEx=1 THEN 'HasActive' ELSE 'None' END,
        LastRecalcUTC  = SYSUTCDATETIME(),
        Status         = CASE
                           WHEN EXISTS (SELECT 1 FROM dbo.ApprovalAssignment WHERE InstanceID=@InstanceID)
                             THEN 'InProgress'
                           ELSE 'Approved'
                         END
  WHERE InstanceID=@InstanceID;
END;
GO

-- Record action (approve/reject/comment/ignore)
CREATE OR ALTER PROC dbo.usp_Approval_Action
  @InstanceID BIGINT,
  @ActorUPN VARCHAR(256),
  @ActionType VARCHAR(16),
  @Comment NVARCHAR(1000) = NULL,
  @RequestId UNIQUEIDENTIFIER = NULL,
  @SourceSystem VARCHAR(64) = NULL
AS
BEGIN
  SET NOCOUNT ON;

  -- Idempotent retry protection
  IF @RequestId IS NOT NULL AND EXISTS(SELECT 1 FROM dbo.ApprovalAction WHERE RequestId=@RequestId)
    RETURN;

  INSERT dbo.ApprovalAction (InstanceID, ActorUPN, ActionType, Comment, CreatedUTC, RequestId, SourceSystem)
  VALUES (@InstanceID, @ActorUPN, @ActionType, @Comment, SYSUTCDATETIME(), @RequestId, @SourceSystem);

  IF @ActionType IN ('Approve','Reject')
  BEGIN
    -- Mark assignment satisfied for direct user scope (extend to Team/Role in app or via expansion)
    UPDATE a
      SET a.Satisfied=1, a.SatisfiedUTC=SYSUTCDATETIME()
    FROM dbo.ApprovalAssignment a
    WHERE a.InstanceID=@InstanceID
      AND a.ApproverScope='User'
      AND a.ApproverRef=@ActorUPN;

    IF @ActionType='Reject'
      UPDATE dbo.ApprovalInstance SET Status='Rejected', ClosedUTC=SYSUTCDATETIME() WHERE InstanceID=@InstanceID;
    ELSE IF NOT EXISTS (
        SELECT 1 FROM dbo.ApprovalAssignment WHERE InstanceID=@InstanceID AND Required=1 AND Satisfied=0
      )
      UPDATE dbo.ApprovalInstance SET Status='Approved', ClosedUTC=SYSUTCDATETIME() WHERE InstanceID=@InstanceID;
  END
  ELSE IF @ActionType='IgnoreException'
    UPDATE dbo.ApprovalInstance SET ExceptionState='Ignored' WHERE InstanceID=@InstanceID;
  ELSE IF @ActionType='Unignore'
    UPDATE dbo.ApprovalInstance SET ExceptionState='HasActive' WHERE InstanceID=@InstanceID;

  -- Recompute after stateful changes
  EXEC dbo.usp_Approval_Recalculate @InstanceID;
END;
GO

/* ======================================================================
   OPTIONAL: High-throughput helper for notes (TVP bulk insert)
   ====================================================================== */
IF TYPE_ID('dbo.NoteTvp') IS NULL
  EXEC ('CREATE TYPE dbo.NoteTvp AS TABLE
  (
    EntityType VARCHAR(64),
    BusinessKey VARCHAR(128),
    NoteText NVARCHAR(2000),
    CreatedByUPN VARCHAR(256),
    CreatedByDisplay NVARCHAR(256),
    VisibilityScope VARCHAR(32),
    SourceSystem VARCHAR(64)
  );');

CREATE OR ALTER PROC dbo.usp_BulkInsert_EntityNote
  @Notes dbo.NoteTvp READONLY
AS
BEGIN
  SET NOCOUNT ON;
  INSERT dbo.EntityNote (EntityType, BusinessKey, NoteText, CreatedByUPN, CreatedByDisplay, VisibilityScope, SourceSystem)
  SELECT EntityType, BusinessKey, NoteText, CreatedByUPN, CreatedByDisplay, VisibilityScope, SourceSystem
  FROM @Notes;
END;
GO
