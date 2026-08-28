\set ON_ERROR_STOP on
CREATE TABLE catalog_item (
  id bigint PRIMARY KEY,
  external_ref text NOT NULL,
  active boolean NOT NULL,
  payload text NOT NULL
);
INSERT INTO catalog_item
SELECT g, 'ref-' || g, g % 100 = 0, md5(g::text)
FROM generate_series(1, 50000) AS g;

CREATE TEMP TABLE digest_before AS
SELECT md5(string_agg(id::text || ':' || payload, ',' ORDER BY id)) AS value
FROM catalog_item WHERE active;

CREATE INDEX catalog_item_active_ref_idx ON catalog_item(external_ref) WHERE active;
ANALYZE catalog_item;

DO $$
DECLARE
  plan jsonb;
BEGIN
  EXECUTE $q$EXPLAIN (FORMAT JSON) SELECT * FROM catalog_item WHERE active AND external_ref = 'ref-100'$q$ INTO plan;
  IF plan::text NOT LIKE '%catalog_item_active_ref_idx%' THEN
    RAISE EXCEPTION 'partial index was not selected: %', plan;
  END IF;
END $$;

SELECT json_build_object(
  'lab', 'index',
  'server_version', current_setting('server_version'),
  'matching_rows', count(*),
  'digest_unchanged', (SELECT value FROM digest_before) = md5(string_agg(id::text || ':' || payload, ',' ORDER BY id)),
  'verdict', CASE WHEN (SELECT value FROM digest_before) = md5(string_agg(id::text || ':' || payload, ',' ORDER BY id)) THEN 'pass' ELSE 'fail' END
) FROM catalog_item WHERE active;
