/*
 Demo setup for Fabric warehouse writeback scenario.
 Creates a sample data table plus an activity log that Azure Logic Apps will update.
 Note: Fabric Warehouse (Synapse SQL) has limited constraint support, so we use rowstore indexes and supply keys ourselves.
*/

IF OBJECT_ID('dbo.vw_exceptioncomments_with_feedback', 'V') IS NOT NULL
    DROP VIEW dbo.vw_exceptioncomments_with_feedback;

IF OBJECT_ID('dbo.ExceptionCommentActivity', 'U') IS NOT NULL
    DROP TABLE dbo.ExceptionCommentActivity;

IF OBJECT_ID('dbo.ExceptionComments', 'U') IS NOT NULL
    DROP TABLE dbo.ExceptionComments;

GO

CREATE TABLE dbo.ExceptionComments (
    CaseId INT NOT NULL,
    Title VARCHAR(100),
    Owner VARCHAR(50),
    DueDate DATE,
    CurrentStatus VARCHAR(20)
);

GO

INSERT INTO dbo.ExceptionComments VALUES
(1001, 'VAT Reconciliation', 'Lionel Messi', '2024-05-31', 'Pending'),
(1002, 'Intercompany Match', 'Cristiano Ronaldo', '2024-05-30', 'Pending'),
(1003, 'Accrual True-Up', 'LeBron James', '2024-06-02', 'Pending'),
(1004, 'FX Exposure Review', 'Tom Brady', '2024-06-04', 'Pending'),
(1005, 'P&L Attribution Review', 'Max Verstappen', '2024-06-05', 'Pending'),
(1006, 'Liquidity Stress Test', 'Lewis Hamilton', '2024-06-06', 'Pending');

GO

CREATE TABLE dbo.ExceptionCommentActivity (
    ActivityId UNIQUEIDENTIFIER NOT NULL,
    CaseId INT NOT NULL,
    ActionType VARCHAR(20) NOT NULL,      -- Comment | Approve | Reject
    CommentText VARCHAR(400),
    ActionBy VARCHAR(60),
    ActionAt DATETIME2(6) NOT NULL
);

GO

-- Optional seed entry to validate the view logic. Remove if you prefer a clean activity log.
INSERT INTO dbo.ExceptionCommentActivity (ActivityId, CaseId, ActionType, CommentText, ActionBy, ActionAt)
VALUES (NEWID(), 1001, 'Comment', 'Initial review created during setup.', 'Lionel Messi', SYSDATETIME());

GO

CREATE OR ALTER VIEW dbo.vw_exceptioncomments_with_feedback AS
SELECT  c.CaseId,
        c.Title,
        c.Owner,
        c.DueDate,
        c.CurrentStatus,
        last_action.ActionType AS LastActionType,
        last_action.CommentText AS LastComment,
        ISNULL(activity_counts.ActivityCount, 0) AS ActivityCount
FROM dbo.ExceptionComments c
OUTER APPLY (
    SELECT TOP 1 a.ActionType, a.CommentText
    FROM dbo.ExceptionCommentActivity a
    WHERE a.CaseId = c.CaseId
    ORDER BY a.ActionAt DESC
) AS last_action
LEFT JOIN (
    SELECT CaseId, COUNT(*) AS ActivityCount
    FROM dbo.ExceptionCommentActivity
    GROUP BY CaseId
) AS activity_counts
    ON activity_counts.CaseId = c.CaseId;
