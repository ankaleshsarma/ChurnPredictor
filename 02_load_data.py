"""
Script: To Load Kaggle Telco Dataset into SQL Server
Purpose: Importing raw CSV data into Docker SQL Server for feature engineering
Author: Ankalesh sarmah
Date: March 2025
"""

import pandas as pd
from sqlalchemy import create_engine
from pathlib import Path
import os

PROJECT_ROOT = Path(__file__).parent.parent
CSV_PATH = PROJECT_ROOT / 'data' / 'WA_Fn-UseC_-Telco-Customer-Churn.csv'

import urllib.parse
password = urllib.parse.quote_plus('YourStrong@Password123')
SQL_CONNECTION = f'mssql+pymssql://sa:{password}@localhost:1433/SaaSChurnProject'

def load_data_to_sql():
    """Load CSV data into SQL Server"""
    
    
    if not CSV_PATH.exists():
        print(f" ERROR: CSV file not found at {CSV_PATH}")
        return False
    
    try:
        
        print("📂 Reading CSV file...")
        df = pd.read_csv(CSV_PATH)
        print(f"✅ Loaded {len(df):,} rows × {len(df.columns)} columns")
        
        print("\n📊 Data Preview:")
        print(df.head(3))
        print(f"\n📋 Columns: {df.columns.tolist()}")
        missing = df.isnull().sum()[df.isnull().sum() > 0]
        if len(missing) > 0:
            print(f"\n Missing Values:\n{missing}")
        
        print("\n🔌 Connecting to SQL Server...")
        engine = create_engine(SQL_CONNECTION)
        
        with engine.connect() as conn:
            print(" Connected to SQL Server")
        
        print("⏳ Uploading to SQL Server (dbo.Customers)...")
        df.to_sql('Customers', engine, schema='dbo', if_exists='append', index=False)
        
        print(f"\n SUCCESS! Uploaded {len(df):,} rows to dbo.Customers")
        print(" Ready for feature engineering in SQL")
        return True
        
    except Exception as e:
        print(f" ERROR: {str(e)}")
        return False

if __name__ == "__main__":
    import subprocess
    import sys
    
    print(" Installing required packages...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "pandas", "sqlalchemy", "pymssql"])

    print("\n" + "="*60)
    print("SaaS CHURN PROJECT - DATA LOADER")
    print("="*60)
    success = load_data_to_sql()
    print("="*60)
    if success:
        print(" Data loading completed successfully!")
    else:
        print(" Data loading failed. Check the errors above.")