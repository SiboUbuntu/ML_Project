WITH Leads AS (
    SELECT 
        c.Id AS ACC_Id,
        CAST(c.CreatedOn AS DATE) AS Registration_date,
        CONCAT(c.CountryName, ' ', c.Campaign) AS Country_Campaign
    FROM [crm-ubuntumarkets-replica].crm.customers c
    WHERE c.CreatedOn >= '2025-12-01'
),

First_deposit_raw AS (
    SELECT 
        t.CustomerId,
        t.ApprovedDate,
        t.Amount,
        dt.PspPaymentMethod,
        cd.UpdatedOn AS KYC_Completion_Date,
        ROW_NUMBER() OVER (
            PARTITION BY t.CustomerId 
            ORDER BY t.ApprovedDate ASC
        ) AS rn
    FROM [crm-ubuntumarkets-replica].crm.Transactions t
    INNER JOIN [crm-ubuntumarkets-replica].crm.DepositTransactions dt 
        ON t.Id = dt.TransactionId
    LEFT JOIN [crm-ubuntumarkets-replica].crm.CustomerDocuments cd
        ON TRY_CAST(REPLACE(cd.AccountNo, 'ACC', '') AS INT) = t.CustomerId
    WHERE 
        dt.IsFtd = 1
        AND t.TransactionStatusId = 2
        AND t.TransactionTypeId = 1
        AND dt.PaymentMethodId <> 9
),

First_deposit AS (
    SELECT 
        CustomerId,
        FORMAT(ApprovedDate, 'yyyy-MM-dd') AS First_Approved_Date,
        Amount AS First_deposit_Amount,
        PspPaymentMethod,
        FORMAT(KYC_Completion_Date,'yyyy-MM-dd') AS KYC_Completion_Date
    FROM First_deposit_raw
    WHERE rn = 1
    GROUP BY 
        CustomerId,
        ApprovedDate,
        Amount,
        PspPaymentMethod, KYC_Completion_Date
),

Deposit_30D AS (
    SELECT
        t.CustomerId,
        COUNT(t.Id) AS Deposit_Count_30D
    FROM [crm-ubuntumarkets-replica].crm.Transactions t
    INNER JOIN First_deposit fd
        ON t.CustomerId = fd.CustomerId
    LEFT JOIN [crm-ubuntumarkets-replica].crm.DepositTransactions dt
        ON t.Id = dt.TransactionId
    WHERE 
        t.TransactionTypeId = 1
        AND t.TransactionStatusId = 2
        AND dt.PaymentMethodId <> 9
        AND t.ApprovedDate > fd.First_Approved_Date
        AND t.ApprovedDate < DATEADD(DAY, 30, fd.First_Approved_Date)
    GROUP BY 
        t.CustomerId
),

All_Deposits AS (
    SELECT
        t.CustomerId,
        COUNT(t.Id) AS Total_Deposit_Count,
        SUM(t.Amount) AS Total_deposits
    FROM [crm-ubuntumarkets-replica].crm.Transactions t
    LEFT JOIN [crm-ubuntumarkets-replica].crm.DepositTransactions dt
        ON t.Id = dt.TransactionId
    WHERE 
        t.TransactionTypeId = 1
        AND t.TransactionStatusId = 2
        AND dt.PaymentMethodId <> 9
    GROUP BY 
        t.CustomerId
),

Withdrawals AS (
    SELECT 
        t.CustomerId,
        SUM(ABS(t.Amount)) AS Total_Withdrawals
    FROM [crm-ubuntumarkets-replica].crm.Transactions t 
    WHERE t.TransactionTypeId = 4
    GROUP BY 
        t.CustomerId
)

SELECT 
    l.ACC_Id,
    l.Registration_date,
    fd.First_Approved_Date,
    fd.KYC_Completion_Date,
    l.Country_Campaign,
    fd.PspPaymentMethod,
    fd.First_deposit_Amount,
    COALESCE(wd.Total_Withdrawals, 0) AS Total_Withdrawals,
    fd.First_deposit_Amount - COALESCE(wd.Total_Withdrawals, 0) AS Net_Amount,
    COALESCE(d30.Deposit_Count_30D, 1) AS Deposit_Count_30D,
    CASE 
        WHEN COALESCE(d30.Deposit_Count_30D, 1) = 1 THEN 1 
        ELSE 0 
    END AS single_deposit_churn,
    COALESCE(wd.Total_Withdrawals, 0) 
        / NULLIF(ad.Total_deposits, 0) AS Withdrawal_ratio
FROM Leads l
INNER JOIN First_deposit fd 
    ON l.ACC_Id = fd.CustomerId
LEFT JOIN Withdrawals wd 
    ON l.ACC_Id = wd.CustomerId
LEFT JOIN Deposit_30D d30 
    ON l.ACC_Id = d30.CustomerId
LEFT JOIN All_Deposits ad 
    ON l.ACC_Id = ad.CustomerId;