\set ON_ERROR_STOP on
CREATE EXTENSION pg_trgm;
CREATE TABLE searchable_document(id bigint PRIMARY KEY, body text NOT NULL);
INSERT INTO searchable_document
SELECT g, CASE WHEN g = 4242 THEN 'postgresql atlas searchable phrase' ELSE md5(g::text) END
FROM generate_series(1, 20000) AS g;
CREATE INDEX searchable_document_body_trgm_idx ON searchable_document USING gin (body gin_trgm_ops);
ANALYZE searchable_document;

CREATE TEMP TABLE extension_plan(index_used boolean);
DO $$
DECLARE
  plan jsonb;
BEGIN
  EXECUTE $q$EXPLAIN (FORMAT JSON) SELECT * FROM searchable_document WHERE body LIKE '%searchable phrase%'$q$ INTO plan;
  INSERT INTO extension_plan VALUES (plan::text LIKE '%searchable_document_body_trgm_idx%');
END $$;

SELECT json_build_object(
  'lab', 'extension',
  'server_version', current_setting('server_version'),
  'extension_version', (SELECT extversion FROM pg_extension WHERE extname = 'pg_trgm'),
  'similarity', similarity('postgresql atlas', 'postgres atlas'),
  'matching_rows', (SELECT count(*) FROM searchable_document WHERE body LIKE '%searchable phrase%'),
  'index_used', bool_and(index_used),
  'verdict', CASE WHEN bool_and(index_used) AND
    (SELECT count(*) FROM searchable_document WHERE body LIKE '%searchable phrase%') = 1 THEN 'pass' ELSE 'fail' END
) FROM extension_plan;
