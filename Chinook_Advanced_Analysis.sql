-- CHINOOK MUSIC STORE ADVANCED ANALYSIS - MOHAMED KHALID
-- All 5 Queries - Run in SQLiteStudio

1.  Top Artists with Window Functions

WITH ArtistRevenue AS (
    SELECT 
        a.Name AS Artist,
        COUNT(DISTINCT al.AlbumId) AS Albums,
        COUNT(il.InvoiceLineId) AS TracksSold,
        ROUND(SUM(il.Quantity * il.UnitPrice), 2) AS Revenue,
        -- Moving average of revenue (3-artist window)
        AVG(SUM(il.Quantity * il.UnitPrice)) OVER (
            ORDER BY COUNT(il.InvoiceLineId) DESC 
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ) AS RevenueMovingAvg,
        -- Percentile rank
        PERCENT_RANK() OVER (ORDER BY SUM(il.Quantity * il.UnitPrice) DESC) AS RevenuePercentile,
        -- Running total
        SUM(SUM(il.Quantity * il.UnitPrice)) OVER (ORDER BY SUM(il.Quantity * il.UnitPrice) DESC) AS CumulativeRevenue
    FROM Artist a
    JOIN Album al ON a.ArtistId = al.ArtistId
    JOIN Track t ON al.AlbumId = t.AlbumId
    JOIN InvoiceLine il ON t.TrackId = il.TrackId  -- FIXED: Clear table reference
    GROUP BY a.ArtistId, a.Name
)
SELECT 
    Artist,
    Albums,
    TracksSold,
    Revenue,
    ROUND(RevenueMovingAvg, 2) AS MovingAvgRevenue,
    ROUND(RevenuePercentile * 100, 1) AS RevenuePercentile,
    CumulativeRevenue,
    CASE 
        WHEN RevenuePercentile >= 0.8 THEN '🏆 Elite Performer'
        WHEN RevenuePercentile >= 0.5 THEN '⭐ Strong Performer'
        ELSE '📊 Average'
    END AS PerformanceTier
FROM ArtistRevenue
ORDER BY Revenue DESC
LIMIT 10;



2. Customer Cohort Analysis with Retention Rates

WITH CustomerFirstPurchase AS (
    SELECT 
        c.CustomerId,
        c.FirstName || ' ' || c.LastName AS CustomerName,
        c.Country,
        MIN(i.InvoiceDate) AS FirstPurchaseDate,
        strftime('%Y-%m', MIN(i.InvoiceDate)) AS CohortMonth
    FROM Customer c
    JOIN Invoice i ON c.CustomerId = i.CustomerId
    GROUP BY c.CustomerId, c.FirstName, c.LastName, c.Country
),
CustomerActivity AS (
    SELECT 
        cfp.CohortMonth,
        cfp.CustomerId,
        COUNT(DISTINCT i.InvoiceId) AS OrdersInMonth,
        strftime('%Y-%m', i.InvoiceDate) AS ActivityMonth,
        -- Calculate months since first purchase
        (strftime('%Y', i.InvoiceDate) - strftime('%Y', cfp.FirstPurchaseDate)) * 12 + 
        (strftime('%m', i.InvoiceDate) - strftime('%m', cfp.FirstPurchaseDate)) AS MonthsSinceFirst
    FROM CustomerFirstPurchase cfp
    JOIN Invoice i ON cfp.CustomerId = i.CustomerId
    GROUP BY cfp.CohortMonth, cfp.CustomerId, ActivityMonth, MonthsSinceFirst
),
CohortRetention AS (
    SELECT 
        CohortMonth,
        MonthsSinceFirst,
        COUNT(DISTINCT CustomerId) AS CustomersActive,
        -- Total customers in this cohort
        (SELECT COUNT(DISTINCT CustomerId) 
         FROM CustomerFirstPurchase cfp2 
         WHERE cfp2.CohortMonth = cr.CohortMonth) AS CohortSize,
        -- Retention rate
        ROUND(
            COUNT(DISTINCT CustomerId) * 100.0 / 
            (SELECT COUNT(DISTINCT CustomerId) 
             FROM CustomerFirstPurchase cfp2 
             WHERE cfp2.CohortMonth = cr.CohortMonth), 1
        ) AS RetentionRate,
        -- Average orders per active customer
        ROUND(SUM(OrdersInMonth) * 1.0 / COUNT(DISTINCT CustomerId), 1) AS AvgOrdersPerCustomer
    FROM CustomerActivity cr
    GROUP BY CohortMonth, MonthsSinceFirst
)
SELECT 
    CohortMonth,
    MonthsSinceFirst,
    CohortSize,
    CustomersActive,
    RetentionRate,
    AvgOrdersPerCustomer,
    -- Advanced: Churn rate
    ROUND(100 - RetentionRate, 1) AS ChurnRate,
    -- Advanced: Cohort quality score
    ROUND(RetentionRate * 0.6 + (AvgOrdersPerCustomer * 10), 1) AS CohortScore,
    CASE 
        WHEN RetentionRate >= 40 THEN '🟢 Excellent Retention'
        WHEN RetentionRate >= 25 THEN '🟡 Good Retention'
        ELSE '🔴 High Churn'
    END AS RetentionStatus
FROM CohortRetention
ORDER BY CohortMonth, MonthsSinceFirst;


3. Customer Benchmarking vs Peers

WITH CustomerMetrics AS (
    SELECT 
        c.CustomerId,
        c.FirstName || ' ' || c.LastName AS CustomerName,
        c.Country,
        COUNT(DISTINCT i.InvoiceId) AS OrderCount,
        ROUND(SUM(i.Total), 2) AS TotalSpent,
        ROUND(AVG(i.Total), 2) AS AvgOrderValue,
        MAX(i.InvoiceDate) AS LastPurchase,
        -- Recency in days
        (JULIANDAY('now') - JULIANDAY(MAX(i.InvoiceDate))) AS RecencyDays
    FROM Customer c  -- FIXED: Start with Customer table
    LEFT JOIN Invoice i ON c.CustomerId = i.CustomerId  -- FIXED: Clear CustomerId reference
    GROUP BY c.CustomerId, c.FirstName, c.LastName, c.Country
    HAVING OrderCount >= 3  -- Active customers only
),
CountryAverages AS (
    SELECT 
        Country,
        AVG(OrderCount) AS AvgOrdersCountry,
        AVG(TotalSpent) AS AvgSpendCountry,
        AVG(RecencyDays) AS AvgRecencyCountry
    FROM CustomerMetrics
    GROUP BY Country
)
SELECT 
    cm.CustomerName,
    cm.Country,
    cm.OrderCount,
    cm.TotalSpent,
    cm.AvgOrderValue,
    cm.RecencyDays,
    -- FIXED: Proper correlated subquery for benchmarking
    ROUND((cm.OrderCount - ca.AvgOrdersCountry) / NULLIF(ca.AvgOrdersCountry, 0) * 100, 1) AS OrdersVsCountry,
    ROUND((cm.TotalSpent - ca.AvgSpendCountry) / NULLIF(ca.AvgSpendCountry, 0) * 100, 1) AS SpendVsCountry,
    CASE 
        WHEN cm.RecencyDays < ca.AvgRecencyCountry * 0.5 THEN '🟢 Very Active'
        WHEN cm.RecencyDays < ca.AvgRecencyCountry THEN '🟡 Active'
        ELSE '🔴 At Risk'
    END AS ActivityStatus
FROM CustomerMetrics cm
JOIN CountryAverages ca ON cm.Country = ca.Country
WHERE cm.TotalSpent > 25  -- Significant customers
ORDER BY cm.TotalSpent DESC
LIMIT 15;



4. Playlist Performance Analysis

WITH PlaylistMetrics AS (
    SELECT 
        p.Name AS PlaylistName,
        p.PlaylistId,
        COUNT(pt.TrackId) AS TrackCount,
        COUNT(DISTINCT t.GenreId) AS UniqueGenres,
        -- Advanced: Diversity score
        ROUND(COUNT(DISTINCT t.GenreId) * 1.0 / COUNT(pt.TrackId), 2) AS GenreDiversity,
        -- Sales performance of playlist tracks
        ROUND(SUM(il.Quantity * il.UnitPrice), 2) AS TotalRevenue,
        COUNT(il.InvoiceLineId) AS TimesSold,
        -- Advanced: Revenue per track
        ROUND(SUM(il.Quantity * il.UnitPrice) * 1.0 / COUNT(DISTINCT pt.TrackId), 2) AS RevenuePerTrack,
        -- Advanced: Sales rank
        ROW_NUMBER() OVER (ORDER BY SUM(il.Quantity * il.UnitPrice) DESC) AS SalesRank
    FROM Playlist p
    JOIN PlaylistTrack pt ON p.PlaylistId = pt.PlaylistId  -- FIXED: Clear references
    JOIN Track t ON pt.TrackId = t.TrackId
    LEFT JOIN InvoiceLine il ON t.TrackId = il.TrackId
    GROUP BY p.PlaylistId, p.Name
)
SELECT 
    PlaylistName,
    TrackCount,
    UniqueGenres,
    GenreDiversity,
    TotalRevenue,
    TimesSold,
    RevenuePerTrack,
    SalesRank,
    -- Advanced: Performance tier
    CASE 
        WHEN SalesRank <= 5 THEN '🏆 Top Performer'
        WHEN SalesRank <= 20 THEN '⭐ Good'
        WHEN TotalRevenue = 0 THEN '⚠️ No Sales'
        ELSE '📊 Monitor'
    END AS PerformanceTier
FROM PlaylistMetrics
ORDER BY TotalRevenue DESC
LIMIT 15;


5.  Executive Summary Dashboard
WITH ExecutiveMetrics AS (
    -- Overall business metrics
    SELECT 
        'Total Revenue' AS Metric,
        ROUND(SUM(i.Total), 2) AS Value,
        'USD' AS Unit,
        'All Time' AS Period,
        CASE 
            WHEN SUM(i.Total) > 500000 THEN '🟢 Excellent'
            WHEN SUM(i.Total) > 400000 THEN '🟡 Good'
            ELSE '🔴 Needs Attention'
        END AS Status
    FROM Invoice i
    
    UNION ALL
    
    SELECT 
        'Total Customers' AS Metric,
        COUNT(DISTINCT i.CustomerId) AS Value,
        'Customers' AS Unit,
        'All Time' AS Period,
        CASE 
            WHEN COUNT(DISTINCT i.CustomerId) > 350 THEN '🟢 Excellent'
            WHEN COUNT(DISTINCT i.CustomerId) > 300 THEN '🟡 Good'
            ELSE '🔴 Needs Attention'
        END AS Status
    FROM Invoice i
    
    UNION ALL
    
    SELECT 
        'Avg Order Value' AS Metric,
        ROUND(AVG(i.Total), 2) AS Value,
        'USD' AS Unit,
        'All Time' AS Period,
        CASE 
            WHEN AVG(i.Total) > 6 THEN '🟢 Excellent'
            WHEN AVG(i.Total) > 5 THEN '🟡 Good'
            ELSE '🔴 Needs Attention'
        END AS Status
    FROM Invoice i
    
    UNION ALL
    
    -- Top genre performance
    SELECT 
        'Top Genre Revenue' AS Metric,
        ROUND(SUM(il.Quantity * il.UnitPrice), 2) AS Value,
        'USD' AS Unit,
        'Rock Genre' AS Period,
        '🟢 Dominant' AS Status
    FROM Genre g
    JOIN Track t ON g.GenreId = t.GenreId
    JOIN InvoiceLine il ON t.TrackId = il.TrackId
    WHERE g.Name = 'Rock'
),
TopPerformers AS (
    SELECT 
        'Top Artist' AS Category,
        a.Name AS Entity,
        ROW_NUMBER() OVER (ORDER BY SUM(il.Quantity * il.UnitPrice) DESC) AS Rank,
        ROUND(SUM(il.Quantity * il.UnitPrice), 0) AS Revenue
    FROM Artist a
    JOIN Album al ON a.ArtistId = al.ArtistId
    JOIN Track t ON al.AlbumId = t.AlbumId
    JOIN InvoiceLine il ON t.TrackId = il.TrackId
    GROUP BY a.ArtistId, a.Name
    HAVING SUM(il.Quantity * il.UnitPrice) > 50000
)
SELECT 
    em.Metric,
    em.Value,
    em.Unit,
    em.Status,
    -- Add top performers as additional rows
    COALESCE(tp.Entity, '') AS TopPerformer,
    COALESCE(CAST(tp.Rank AS TEXT), '') AS PerformerRank,
    COALESCE(CAST(tp.Revenue AS TEXT), '') AS PerformerRevenue
FROM ExecutiveMetrics em
LEFT JOIN TopPerformers tp ON em.Metric = 'Total Revenue' AND tp.Rank <= 3
ORDER BY 
    CASE em.Metric 
        WHEN 'Total Revenue' THEN 1
        WHEN 'Total Customers' THEN 2
        WHEN 'Avg Order Value' THEN 3
        WHEN 'Top Genre Revenue' THEN 4
        ELSE 5 
    END;