
# SaaS Churn Risk Platform — Technical README

Version: 1.1

Purpose

This repository implements an end-to-end churn risk pipeline for a SaaS product. It focuses on converting customer account and behavior data into actionable risk scores and a curated contact table that operational teams (Sales, Customer Success) can use to prioritize outreach. The document describes what the system does, the technical choices made, and the business impact these choices enable.

Design principles

- Predictability: produce well-calibrated probabilities that teams can act upon.
- Explainability: ensure model outputs are interpretable to non-technical stakeholders.
- Reproducibility: preserve preprocessing and feature ordering so scoring is consistent across environments.
- Operational readiness: artifacts are serialized for straightforward integration into reporting and automation tools.

Repository layout

- `data/` — source datasets (example: `WA_Fn-UseC_-Telco-Customer-Churn.csv`).
- `notebooks/` — exploratory analysis and reproducible training notebook (`churn_model.ipynb`).
- `sql/` — ETL and feature SQL scripts and loader (`01_create_database.sql`, `02_load_data.py`, `03_feature_engineering.sql`).
- `outputs/` — serialized model and outputs (`churn_model.joblib`, `churn_predictions.csv`, `model_features.json`, `churn_model_metadata.json`).
- `dashboard/` — Power BI artifacts and notes (report files or templates when present).

Data model and required fields

The core scoring table requires a stable primary key and features that capture account state and recent behavior. Common fields used in the pipeline:

- `customerID` (string): stable key used for joins and downstream lookup.
- `email`, `phone` (string): contact channels. Treated as PII and only surfaced to authorized roles.
- `tenure`, `monthly_charges`, `total_charges` (numeric): financial and lifetime indicators.
- `contract_type`, `payment_method`, `internet_service` (categorical): product and billing signals.
- `last_login`, `support_tickets_last_30d` (temporal/behavioral): recency metrics.
- `Churn` (binary label): historical churn indicator for supervised learning.

Preprocessing & feature engineering (technical)

The pipeline executes deterministic preprocessing steps so model inputs remain consistent between training and production scoring. Key transformations:

- Missing-value handling: numeric imputation using median per feature; categorical missing as a dedicated category `"MISSING"` so models can treat it as signal.
- Categorical encoding: a mix of techniques is used depending on cardinality:
	- low-cardinality: one-hot encoding (sparse representation avoided where infeasible).
	- medium/high-cardinality: target encoding with leave-one-out adjustments to reduce leakage.
- Numeric scaling: robust scaling (median and IQR) to limit influence of outliers when linear models are used.
- Temporal features: extract tenure buckets and churn-lag features (e.g., recent payment failures, increase in support volume).
- Interaction terms: a small set of domain-driven interactions (e.g., `tenure * monthly_charges`) included to capture multiplicative risk.

Modeling choices and rationale

Three model classes are part of the evaluation suite; a single primary model is chosen for production scoring based on trade-offs between accuracy, interpretability, latency, and stability.

1) Logistic Regression (baseline)
- Purpose: interpretable baseline and fast iteration.
- Rationale: coefficients are directly communicable to stakeholders and useful for establishing a conservative production threshold.

2) Random Forest
- Purpose: capture non-linearities and robust feature importance estimates.
- Rationale: stable out-of-the-box performance, built-in handling for mixed feature types, and low hyperparameter sensitivity make it a strong candidate when interpretability via variable importance suffices.

3) Gradient Boosting (XGBoost / LightGBM)
- Purpose: provide the best predictive performance on tabular data.
- Rationale: gradient-boosted trees (XGBoost or LightGBM) are chosen for final scoring in many settings because they:
	- consistently produce high AUC on tabular business datasets,
	- handle heterogeneous feature types after minimal encoding,
	- support fast inference and straightforward serialization,
	- work well with SHAP for local and global explainability.

Model selection summary

The production artifact in `outputs/churn_model.joblib` reflects the selected model balancing accuracy and interpretability. The chosen approach uses a gradient-boosted tree model for scoring and a calibrated logistic model for threshold-sensitive business decisions when interpretability of risk drivers is paramount.

Calibration and thresholding (technical)

Predicted probabilities are calibrated using isotonic regression or Platt scaling depending on cross-validation results. Business thresholds are derived from precision-recall trade-offs rather than raw accuracy—this preserves outreach capacity and prioritizes high-confidence calls.

- Example thresholds applied in outputs:
	- High risk: `probability >= 0.70` — immediate outreach.
	- Medium risk: `0.50 <= probability < 0.70` — monitoring and automated touchpoints.
	- Low risk: `probability < 0.50` — standard retention cadence.

Explainability and auditing

To make model outputs actionable, the pipeline includes model explanations saved alongside predictions:

- Global explanations: feature importances (gain and permutation-based) and SHAP summary plots.
- Local explanations: SHAP values for each flagged customer to provide the outreach team with the top 3 drivers for that customer’s risk score.

Model artifact format and reproducibility

Artifacts in `outputs/` include:

- `churn_model.joblib` — serialized model pipeline (preprocessing + model) compatible with scikit-learn pipelines.
- `model_features.json` — exact feature ordering and any encoding maps required for one-hot/target encodings.
- `churn_model_metadata.json` — training environment, library versions, evaluation metrics, and the calibration method used.
- `churn_predictions.csv` — scored customers with `customerID`, `churn_probability`, `risk_bucket`, and optional top SHAP drivers.

Persistence of preprocessing maps and feature ordering ensures that production scoring consumes the identical inputs as training and that stored predictions can be reinterpreted reliably.

Technical stack and justification

The stack is intentionally pragmatic and aligned with enterprise data platforms:

- Python (Pandas, NumPy): primary data manipulation and feature engineering. Rationale: ubiquitous, expressive for tabular ETL, and integrates with model tooling.
- scikit-learn: pipeline orchestration and standard model training utilities. Rationale: stable interface for preprocessing, model selection, and serialization.
- XGBoost / LightGBM: chosen for the production model due to strong performance on structured data and fast inference. LightGBM is preferred when datasets are large and memory-efficient training is required.
- Joblib: model serialization. Rationale: preserves scikit-learn pipelines and is straightforward to load into Python-based scoring services.
- SQL (Postgres, SQL Server, or equivalent): canonical ETL and feature materialization. Rationale: data warehouses are the authoritative source for customer records and enable scheduled, auditable feature computation.
- Power BI: visualization and business distribution. Rationale: integrates with enterprise identity, supports scheduled refreshes, and enables end-users to consume a curated table for outreach without technical skills.
- Jupyter Notebooks: interactive exploration and reproducible training notebook. Rationale: readable analysis artifacts for review and audit.
- Docker (for deployment): containerization for consistent runtime environments. Rationale: reproducible deployments for batch scoring or API services.

## Simple Pipeline Diagram (ASCII)
```
		 +----------------+
		 |  Data Sources  |
		 | (CRM, Billing, | 
		 |  Logs, Events) |
		 +-------+--------+
			 |
			 v
		 +-------+--------+
		 | Ingestion &    |
		 | Cleaning (ETL) |
		 +-------+--------+
			 |
			 v
		 +-------+--------+
		 | Feature Eng.   |
		 | (encodings,    |
		 |  aggregations) |
		 +-------+--------+
			 |
			 v
		 +-------+--------+
		 |  Model Train   |
		 | (CV, selection)|
		 +-------+--------+
			 |
			 v
		 +-------+--------+      +------------------+
		 | Calibration &  |----->| Artifact Storage |
		 | Thresholding   |      | (.joblib, .json) |
		 +-------+--------+      +------------------+
			 |
			 v
		 +-------+--------+
		 | Scoring (API / |
		 | Batch service) |
		 +-------+--------+
			 |
			 v
		 +-------+--------+
		 | Power BI /     |
		 | Reporting      |
		 +-------+--------+
			 |
			 v
		 +-------+--------+
		 | Outreach / CRM |
		 | (Assigned reps,|
		 |  follow-up)    |
		 +----------------+
```


Why this stack changes businesses

This specific combination accelerates the path from data to action by:

- Reducing decision latency: automated scoring refreshes + Power BI distribution put high-risk customers in front of Sales/CS quickly.
- Increasing targeting precision: calibrated probabilities reduce false positives, meaning outreach resources focus on accounts with the highest expected ROI.
- Making interventions auditable: saved feature maps, calibration metadata, and SHAP explanations let stakeholders trace why a customer was flagged.
- Enabling measurable impact: when outreach is tied to the risk table and results are logged, the model’s effect on churn rates and revenue can be quantified and optimized.

Concrete business outcomes expected

- Reduced voluntary churn rate among contacted cohorts (example: 10–30% reduction depending on intervention efficacy).
- Improved Customer Lifetime Value (LTV) by retaining higher-value accounts identified by the model.
- Lowered cost per retention compared to blanket discounting: targeted offers minimize wasted incentives.

Power BI — contact table and operational usage (technical)

The dashboard surfaces a contact table intended for operational use. The table is a filtered view of `churn_predictions.csv` and contains the following columns for operational readiness:

- `customerID` (key)
- `email`, `phone` (PII — apply access controls)
- `churn_probability` (numeric)
- `risk_bucket` (High/Medium/Low)
- `top_drivers` (list or short text from SHAP values)
- `last_contacted`, `assigned_rep`, `recommended_script`

Loading and publishing flow (Power BI technical steps):

1. Get Data → Text/CSV → select `outputs/churn_predictions.csv`.
2. Mark data types explicitly; treat `churn_probability` as decimal (0–1).
3. Create calculated `risk_bucket` measure using the calibrated thresholds.
4. Add a table visual filtered to `risk_bucket = 'High'` and expose `top_drivers` to provide context to the rep.
5. Publish to Power BI Service and secure the dataset using workspace permissions and Row-Level Security when necessary.

SQL snippet: selecting top-risk customers

Assuming scores are loaded to a table `predictions` with the schema `(customerID, churn_probability, email, phone, last_updated)`, the following SQL extracts the immediate outreach list:

```
SELECT customerID, email, phone, churn_probability
FROM predictions
WHERE churn_probability >= 0.70
ORDER BY churn_probability DESC, last_updated DESC;
```

This query can be embedded in a scheduled job that refreshes the Power BI dataset or used to produce CSV exports for CRM ingestion.

Operational contracts and access control

Because contact tables contain PII, the system enforces a separation of duties. The model produces the risk score and the BI layer controls who can see contact details. Access control strategies include dataset-level permissions in Power BI and database roles limiting exports.

Appendix: reproducibility and artifact description

- The model file (`churn_model.joblib`) is a serialized scikit-learn `Pipeline` combining preprocessing and the trained estimator.
- `model_features.json` enumerates features and encodings in the exact order used for training — this file is essential for any external scoring service that uses the model artifact.
- `churn_model_metadata.json` contains training timestamps, package versions, CV metrics (AUC, PR), calibration method, and the chosen decision threshold.

Contact and ownership

The repository and artifacts are owned by the data science team responsible for model maintenance, monitoring, and alignment with business outreach programs. Stakeholders should coordinate with the data science team for changes to thresholds, outreach scripts, or dataset schemas.

---

This README is written to explain technical choices, the expected business impact, and the mechanics of delivering a contact table to operational teams via Power BI. The content is intended to be concrete, auditable, and directly actionable for engineers and business stakeholders.

