  SELECT CONCAT(c.CountryName, ' ', c.Campaign) AS Country_Campaign,
          COUNT(t.Id) AS FTDs,
          Sum(t.amount) AS Total_deposits,
          Sum(t.amount)/ Count(t.Id) AS PLV
   FROM [crm-ubuntumarkets-replica].crm.customers c
   LEFT JOIN [crm-ubuntumarkets-replica].crm.Transactions t ON t.CustomerId = c.Id
   WHERE t.ApprovedDate >= '2026-01-01' AND t.TransactionTypeId = 1 AND t.TransactionStatusId = 2 
   GROUP BY CONCAT(c.CountryName, ' ', c.Campaign)