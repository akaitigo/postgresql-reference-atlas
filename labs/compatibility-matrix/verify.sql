\set ON_ERROR_STOP on
CREATE TABLE compatibility_probe(
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payload text NOT NULL,
  payload_normalized text GENERATED ALWAYS AS (lower(payload)) STORED,
  metadata jsonb NOT NULL CHECK (jsonb_typeof(metadata) = 'object')
);
INSERT INTO compatibility_probe(payload, metadata)
SELECT 'VALUE-' || g, jsonb_build_object('sequence', g)
FROM generate_series(1, 1000) AS g;

SELECT json_build_object(
  'server_version', current_setting('server_version'),
  'server_version_num', current_setting('server_version_num')::integer,
  'rows', count(*),
  'logical_digest', md5(string_agg(id::text || ':' || payload_normalized || ':' || metadata::text, ',' ORDER BY id)),
  'password_encryption', current_setting('password_encryption'),
  'has_uuidv7', to_regprocedure('pg_catalog.uuidv7()') IS NOT NULL
) FROM compatibility_probe;
