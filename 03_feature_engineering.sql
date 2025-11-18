/*
=============================================================================
SaaS Churn Prediction - Feature Engineering (CORRECTED)
=============================================================================
Purpose: Transform raw customer data into ML-ready features
Author: [Your Name]
Date: November 2025

Table: dbo.Customers

Business Logic:
- Convert text fields to binary indicators (0/1)
- Calculate engagement metrics (feature adoption score)
- Clean financial data (handle missing TotalCharges)
- Create risk indicators (monthly contracts, payment issues)

Data Quality Checks:
- Validates all required columns exist
- Handles NULL values explicitly
- Filters invalid records
=============================================================================
*/

USE SaaSChurnProject;
GO

-- ============================================================
-- DATA QUALITY VALIDATION: Check table and columns exist
-- ============================================================

-- Check 1: Table exists
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.TABLES 
    WHERE TABLE_NAME = 'Customers' AND TABLE_SCHEMA = 'dbo'
)
BEGIN
    RAISERROR('ERROR: Table dbo.Customers does not exist!', 16, 1);
    RETURN;
END;

-- Check 2: Required columns exist
DECLARE @MissingColumns NVARCHAR(MAX);

SELECT @MissingColumns = STRING_AGG(RequiredColumn, ', ')
FROM (VALUES 
    ('customerID'),
    ('gender'),
    ('tenure'),
    ('MonthlyCharges'),
    ('TotalCharges'),
    ('Contract'),
    ('PaymentMethod'),
    ('PaperlessBilling'),
    ('InternetService'),
    ('OnlineSecurity'),
    ('OnlineBackup'),
    ('TechSupport'),
    ('Churn')
) AS Required(RequiredColumn)
WHERE RequiredColumn NOT IN (
    SELECT COLUMN_NAME 
    FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'Customers' AND TABLE_SCHEMA = 'dbo'
);

IF @MissingColumns IS NOT NULL
BEGIN
    DECLARE @ErrorMsg NVARCHAR(500) = 'ERROR: Missing columns in Customers: ' + @MissingColumns;
    RAISERROR(@ErrorMsg, 16, 1);
    RETURN;
END;

PRINT '✅ All required columns present';
GO

-- ============================================================
-- DATA QUALITY REPORT
-- ============================================================
PRINT '================================================';
PRINT 'DATA QUALITY REPORT';
PRINT '================================================';

SELECT 
    'Total Records' AS Metric,
    COUNT(*) AS Value
FROM dbo.Customers

UNION ALL

SELECT 'Missing customerID', COUNT(*) 
FROM dbo.Customers 
WHERE customerID IS NULL OR customerID = ''

UNION ALL

SELECT 'Missing Contract', COUNT(*) 
FROM dbo.Customers 
WHERE Contract IS NULL OR Contract = ''

UNION ALL

SELECT 'Invalid tenure (≤0 or NULL)', COUNT(*) 
FROM dbo.Customers 
WHERE tenure IS NULL OR tenure <= 0

UNION ALL

SELECT 'Blank TotalCharges', COUNT(*) 
FROM dbo.Customers 
WHERE TotalCharges IS NULL OR LTRIM(RTRIM(TotalCharges)) = ''

UNION ALL

SELECT 'Missing Churn label', COUNT(*) 
FROM dbo.Customers 
WHERE Churn IS NULL OR Churn = ''

ORDER BY Metric;

GO

-- ============================================================
-- MAIN FEATURE ENGINEERING QUERY
-- ============================================================
SELECT 
    -- ============================================
    -- IDENTIFIERS
    -- ============================================
    customerID,
    
    -- ============================================
    -- TIME & ENGAGEMENT METRICS
    -- ============================================
    tenure AS MonthsActive,
    
    -- ============================================
    -- FINANCIAL METRICS
    -- ============================================
    MonthlyCharges AS SubscriptionPrice,
    
    -- Clean TotalCharges: Handle blanks and convert to numeric
    -- NOTE: This is CUMULATIVE charges from the data
    CASE 
        WHEN LTRIM(RTRIM(TotalCharges)) = '' THEN NULL
        WHEN ISNUMERIC(TotalCharges) = 1 THEN CAST(TotalCharges AS FLOAT)
        ELSE NULL
    END AS LifetimeValue,
    
    -- ============================================
    -- RISK INDICATORS (1 = Higher Risk)
    -- ============================================
    
    -- Monthly contracts have 3.8x higher churn than annual
    CASE 
        WHEN Contract = 'Month-to-month' THEN 1 
        ELSE 0 
    END AS IsMonthly,
    
    -- Electronic check = MANUAL payment (no auto-pay) = higher risk
    CASE 
        WHEN PaymentMethod = 'Electronic check' THEN 1 
        ELSE 0 
    END AS HasManualPayment,
    
    -- Paperless billing off indicates lower digital engagement
    CASE 
        WHEN PaperlessBilling = 'No' THEN 1 
        ELSE 0 
    END AS IsLowEngagement,
    
    -- ============================================
    -- FEATURE ADOPTION (Product Usage Depth)
    -- ============================================
    
    -- Premium features indicate higher commitment
    CASE 
        WHEN InternetService = 'Fiber optic' THEN 1 
        WHEN InternetService IS NULL THEN 0
        ELSE 0 
    END AS UsesPremiumFeatures,
    
    -- Security features
    CASE 
        WHEN OnlineSecurity = 'Yes' THEN 1 
        WHEN OnlineSecurity IS NULL THEN 0
        ELSE 0 
    END AS UsesFeature1,
    
    -- Backup features
    CASE 
        WHEN OnlineBackup = 'Yes' THEN 1 
        WHEN OnlineBackup IS NULL THEN 0
        ELSE 0 
    END AS UsesFeature2,
    
    -- Tech support indicates engagement with product
    CASE 
        WHEN TechSupport = 'Yes' THEN 1 
        WHEN TechSupport IS NULL THEN 0
        ELSE 0 
    END AS ContactedSupport,
    
    -- ============================================
    -- CALCULATED METRICS
    -- ============================================
    
    -- Feature Adoption Score (0-3): More features = Lower churn risk
    (
        CASE WHEN OnlineSecurity = 'Yes' THEN 1 ELSE 0 END +
        CASE WHEN OnlineBackup = 'Yes' THEN 1 ELSE 0 END +
        CASE WHEN InternetService = 'Fiber optic' THEN 1 ELSE 0 END
    ) AS FeatureAdoptionScore,
    
    -- ============================================
    -- TARGET VARIABLE (What We're Predicting)
    -- ============================================
    CASE 
        WHEN Churn = 'Yes' THEN 1 
        ELSE 0 
    END AS Churned

FROM dbo.Customers

-- ============================================
-- DATA QUALITY FILTERS (STRICT)
-- ============================================
WHERE 
    -- Critical fields must not be NULL or empty
    customerID IS NOT NULL 
    AND LTRIM(RTRIM(customerID)) != ''
    AND Contract IS NOT NULL 
    AND LTRIM(RTRIM(Contract)) != ''
    AND tenure IS NOT NULL 
    AND MonthlyCharges IS NOT NULL
    AND Churn IS NOT NULL
    AND LTRIM(RTRIM(Churn)) != ''
    
    -- Remove records with missing or invalid financial data
    AND TotalCharges IS NOT NULL 
    AND LTRIM(RTRIM(TotalCharges)) != ''
    AND ISNUMERIC(TotalCharges) = 1  -- Ensure it's actually numeric
    
    -- Business logic validation
    AND tenure > 0  -- Must have at least 1 month
    AND MonthlyCharges >= 0  -- Can't have negative charges
    AND CAST(TotalCharges AS FLOAT) >= 0;  -- Cumulative charges must be positive

GO

/*
=============================================================================
EXPECTED OUTPUT:
- ~7,032 rows (some removed due to data quality issues)
- 14 columns total:
  * customerID (string)
  * MonthsActive (1-72)
  * SubscriptionPrice (positive float)
  * LifetimeValue (positive float)
  * IsMonthly (0 or 1)
  * HasManualPayment (0 or 1)
  * IsLowEngagement (0 or 1)
  * UsesPremiumFeatures (0 or 1)
  * UsesFeature1 (0 or 1)
  * UsesFeature2 (0 or 1)
  * ContactedSupport (0 or 1)
  * FeatureAdoptionScore (0, 1, 2, or 3)
  * Churned (0 or 1)
- All binary columns contain only 0 or 1
- No NULL values in any column

AFTER RUNNING:
1. Execute this entire query in VS Code
2. You should see the Data Quality Report first
3. Then the main results grid with ~7,032 rows
4. Right-click results → Save Results As → saas_clean_data.csv
=============================================================================
*/