/*
===============================================================================
Project: Medical Insurance Pricing Engine
Author: Baasankhuu
Description: This ETL query extracts raw policyholder demographics, medical 
             history, and claims data from the enterprise Data Warehouse to 
             feed the Machine Learning pipeline.
===============================================================================
*/

WITH PolicyholderBase AS (
    -- Extract base demographic information for active policyholders
    SELECT 
        customer_id,
        age,
        gender,
        region,
        children
    FROM 
        enterprise_db.policyholders 
    WHERE 
        policy_status = 'Active'
),

MedicalRecords AS (
    -- Extract medical history and calculate BMI (Data Cleaning & Feature Engineering in SQL)
    SELECT 
        customer_id,
        ROUND(CAST(weight_kg / POWER(height_m, 2) AS NUMERIC), 2) AS bmi,
        CASE 
            WHEN smoking_status = 1 THEN 'yes'
            ELSE 'no' 
        END AS smoker
    FROM 
        enterprise_db.medical_history
),

ClaimsData AS (
    -- Aggregate claims data using Window Functions and Dynamic Date filtering
    SELECT 
        customer_id,
        COALESCE(no_claims_bonus_pct, 0.0) AS noclaimsbonus,
        total_charges AS charges
    FROM (
        SELECT 
            customer_id,
            no_claims_bonus_pct,
            -- Calculate total annual charges per customer (handling multiple claims per year)
            SUM(claim_amount_usd) OVER (PARTITION BY customer_id) AS total_charges,
            -- Assign row numbers to deduplicate and capture the most recent record
            ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY claim_amount_usd DESC) as rn
        FROM 
            enterprise_db.claims_billing
        WHERE 
            -- Dynamic date filter: Always fetch data from the most recent billing year
            billing_year = (SELECT MAX(billing_year) FROM enterprise_db.claims_billing)
			AND claim_amount_usd > 0
    ) subquery
    WHERE 
        rn = 1 -- Keep only the latest, deduplicated record per customer
)

-- Join all CTEs to create the final analytical dataset for the Machine Learning pipeline
SELECT 
    pb.age,
    pb.gender,
    mr.bmi,
    pb.children,
    mr.smoker,
    pb.region,
    cd.noclaimsbonus,
    cd.charges
FROM 
    PolicyholderBase pb
INNER JOIN 
    MedicalRecords mr ON pb.customer_id = mr.customer_id
INNER JOIN 
    ClaimsData cd ON pb.customer_id = cd.customer_id
WHERE 
    cd.charges IS NOT NULL;