-- =============================================================================
-- Master build script: run everything end-to-end in one shot.
-- =============================================================================
-- Usage:
--   createdb ecommerce_analytics
--   psql -d ecommerce_analytics -f run_all.sql
--
-- This builds the schema, loads ~50k orders of synthetic data, and creates the
-- views/functions. After it finishes, run any file in /analysis.
-- =============================================================================

\echo '>> Building schema...'
\i schema/01_create_tables.sql
\i schema/02_indexes.sql

\echo '>> Loading reference data...'
\i data/01_seed_reference_data.sql

\echo '>> Generating transactional data (this takes ~10-30s)...'
\i data/02_seed_transactions.sql

\echo '>> Creating views...'
\i schema/03_views.sql

\echo '>> Creating functions + materialized view...'
\i functions/rfm_segment_function.sql

\echo '>> Done. Try:  \\i analysis/02_customer_rfm_segmentation.sql'
