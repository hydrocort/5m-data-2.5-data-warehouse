# Complete Step-by-Step Guide: Building the Liquor Sales dbt Project

## Step 1: Initialize dbt Project

### Command:
```bash
dbt init liquor_sales
cd liquor_sales
```

### What it produces:
- Creates directory structure with folders: `models/`, `snapshots/`, `seeds/`, `tests/`, `macros/`, `analyses/`
- Creates basic `dbt_project.yml`
- Creates basic `profiles.yml` template

## Step 2: Configure Connection to BigQuery

### Files to CREATE/EDIT:

#### **`profiles.yml`** (you create/edit this)
```yaml
liquor_sales:
  target: jaffle_sql
  outputs:
    threads: 1
    location: US
    priority: interactive
    jaffle_sql:
      type: bigquery
      method: oauth
      project: "YOUR-PROJECT-NAME"  # Replace with your GCP project ID
      dataset: "liquor_demo"
      retries: 2
  config:
    send_anonymous_usage_stats: False
```

#### **`dbt_project.yml`** (edit the generated file)
```yaml
name: "liquor_sales"
version: "1.0.0"
config-version: 2

profile: "liquor_sales"

model-paths: ["models"]
analysis-paths: ["analyses"]
test-paths: ["tests"]
seed-paths: ["seeds"]
macro-paths: ["macros"]
snapshot-paths: ["snapshots"]

clean-targets:
  - "target"
  - "dbt_packages"

models:
  liquor_sales:
    star:
      +materialized: table
      +schema: star
```

### Command to test:
```bash
dbt debug
```
### What it produces:
- Validates connection to BigQuery
- Shows "All checks passed!" if successful

## Step 3: Define Data Sources
Note: You can remove any default `models/example` directory holding default templates

### File to CREATE: **`models/sources.yml`**
```yaml
version: 2

sources:
  - name: iowa_liquor_sales
    database: bigquery-public-data
    tables:
      - name: sales
```

## Step 4: Create Snapshot for SCD Type 2

### File to CREATE: **`snapshots/store_snapshot.sql`**
```sql
{% snapshot store_snapshot %}

{{
  config(
    target_schema='snapshots',
    unique_key='store_number',
    strategy='timestamp',
    updated_at='updated_at',
  )
}}

WITH 
store AS (
    SELECT
        store_number,
        store_name,
        address,
        city,
        REGEXP_REPLACE(zip_code, r"\.0$", "") zip_code,
        county_number,
        county,
        date
    FROM
        {{ source('iowa_liquor_sales', 'sales') }}
),
grouped_data AS (
    SELECT DISTINCT
        store_number,
        store_name,
        address,
        city,
        zip_code,
        county_number,
        county,
        FIRST_VALUE(date) OVER (PARTITION BY store_number, store_name, address, city, zip_code, county_number, county ORDER BY date) start_date,
        LAST_VALUE(date) OVER (PARTITION BY store_number, store_name, address, city, zip_code, county_number, county ORDER BY date) end_date,
    FROM
        store
    QUALIFY RANK() OVER (PARTITION BY store_number, store_name, address, city, zip_code, county_number, county ORDER BY date) = 1
)
SELECT
    store_number,
    store_name,
    address,
    city,
    zip_code,
    county_number,
    county,
    CAST(start_date AS TIMESTAMP) start_at,
    CAST(LEAD(start_date) OVER (PARTITION BY store_number ORDER BY start_date) AS TIMESTAMP) as end_at,
    IF(LEAD(start_date) OVER (PARTITION BY store_number ORDER BY start_date) IS NULL, CURRENT_TIMESTAMP(), NULL) as updated_at,
FROM
    grouped_data
ORDER BY store_number, start_at, end_at

{% endsnapshot %}
```

### Command:
```bash
dbt snapshot
```
### What it produces:
- Creates `snapshots` dataset in BigQuery (if it doesn't exist, create manually)
- Creates `store_snapshot` table in the `snapshots` dataset
- Implements SCD Type 2 tracking with `dbt_valid_from`, `dbt_valid_to` columns

## Step 5: Create Star Schema Models

### File to CREATE: **`models/star/dim_store.sql`**
```sql
SELECT
    store_number,
    store_name,
    address,
    city,
    zip_code,
    county_number,
    county,
FROM {{ ref('store_snapshot') }}
WHERE CURRENT_TIMESTAMP > dbt_valid_from and dbt_valid_to IS NULL
```

### File to CREATE: **`models/star/dim_item.sql`**
```sql
SELECT DISTINCT
    item_number,
    item_description,
    category,
    category_name,
    vendor_number,
    vendor_name,
    pack,
    bottle_volume_ml
FROM {{ source('iowa_liquor_sales', 'sales') }}
```

### File to CREATE: **`models/fact_sales.sql`**
```sql
SELECT
    invoice_and_item_number,
    date,
    store_number,
    item_number,
    state_bottle_cost,
    state_bottle_retail,
    bottles_sold,
    sale_dollars,
    volume_sold_liters,
    volume_sold_gallons
FROM {{ source('iowa_liquor_sales', 'sales') }}
```

## Step 6: Create Schema Documentation and Tests

### File to CREATE: **`models/star/schema.yml`**
```yaml
version: 2

models:
  - name: dim_store
    description: "Dimension table for store."
    columns:
      - name: store_number
        description: "The primary key for this table"
        tests:
          - unique
          - not_null
  - name: dim_item
    description: "Dimension table for item."
    columns:
      - name: item_number
        description: "The primary key for this table"
        tests:
          - unique
          - not_null
```

### File to CREATE: **`models/schema.yml`**
```yaml
version: 2

models:
  - name: fact_sales
    description: "Fact table for item."
    columns:
      - name: invoice_and_item_number
        description: "The primary key for this table"
        tests:
          - unique
          - not_null
      - name: store_number
        description: "The foreign key to the store dimension table"
        tests:
          - relationships:
              to: ref('dim_store')
              field: store_number
```

## Step 7: Build the Star Schema

### Command:
```bash
dbt run
```
### What it produces:
- Creates `dim_store` and `dim_item` tables in `star` dataset in BigQuery
- Creates `fact_sales` table/view in main `liquor_demo` dataset
- Shows: "Done. PASS=3 WARN=0 ERROR=0 SKIP=0 TOTAL=3"

## Step 8: Run Tests

### Command:
```bash
dbt test
```
### What it produces:
- Validates data quality (unique, not_null, relationships)
- Shows test results: "Done. PASS=X WARN=0 ERROR=0 SKIP=0 TOTAL=X"

## Complete Command Sequence

```bash
# 1. Initialize project
dbt init liquor_sales
cd liquor_sales

# 2. Test connection (after creating profiles.yml)
dbt debug

# 3. Create snapshot first (creates historical tracking)
dbt snapshot

# 4. Build all models (creates star schema)
dbt run

# 5. Run tests (validates data quality)
dbt test

# 6. Generate documentation (optional)
dbt docs generate
dbt docs serve
```

## Files You Must Create Yourself

1. **`profiles.yml`** - Database connection configuration
2. **`models/sources.yml`** - External data source definitions
3. **`snapshots/store_snapshot.sql`** - SCD Type 2 snapshot logic
4. **`models/star/dim_store.sql`** - Store dimension model
5. **`models/star/dim_item.sql`** - Item dimension model  
6. **`models/fact_sales.sql`** - Sales fact model
7. **`models/star/schema.yml`** - Tests and documentation for star schema
8. **`models/schema.yml`** - Tests and documentation for fact table
9. **Edit `dbt_project.yml`** - Configure materialization strategies

## BigQuery Datasets Created

- **`liquor_demo`** - Main dataset (fact_sales)
- **`liquor_demo_star`** - Star schema dataset (dim_store, dim_item)
- **`snapshots`** - Snapshot dataset (store_snapshot)

This creates a complete dimensional model with historical tracking for analytics!