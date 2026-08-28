\set ON_ERROR_STOP on
CREATE DOMAIN positive_money AS numeric(12,2) CHECK (VALUE > 0);
CREATE TYPE order_status AS ENUM ('draft', 'confirmed', 'cancelled');
CREATE TABLE typed_order (
  id uuid PRIMARY KEY DEFAULT uuidv7(),
  status order_status NOT NULL,
  amount positive_money NOT NULL,
  tags text[] NOT NULL CHECK (cardinality(tags) > 0),
  metadata jsonb NOT NULL CHECK (jsonb_typeof(metadata) = 'object'),
  valid_during tstzrange NOT NULL CHECK (NOT isempty(valid_during)),
  service_days datemultirange NOT NULL,
  client_network inet NOT NULL,
  display_name text GENERATED ALWAYS AS (metadata ->> 'name') STORED
);
INSERT INTO typed_order(status, amount, tags, metadata, valid_during, service_days, client_network)
VALUES (
  'confirmed', 1200.00, ARRAY['priority', 'export'], '{"name":"atlas-order","region":"jp"}',
  tstzrange('2026-08-28 00:00:00+00', '2026-08-29 00:00:00+00', '[)'),
  datemultirange(daterange('2026-08-28', '2026-08-30', '[)')),
  '192.0.2.10/24'
);

DO $$
BEGIN
  BEGIN
    INSERT INTO typed_order(status, amount, tags, metadata, valid_during, service_days, client_network)
    VALUES ('draft', -1, ARRAY['invalid'], '{}', tstzrange('2026-01-01', '2026-01-02'), '{}', '192.0.2.1');
    RAISE EXCEPTION 'domain violation was not raised';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
END $$;

SELECT json_build_object(
  'lab', 'types-constraints',
  'server_version', current_setting('server_version'),
  'row_count', count(*),
  'uuid_version', uuid_extract_version((SELECT id FROM typed_order LIMIT 1)),
  'array_contains', bool_and(tags @> ARRAY['priority']),
  'json_path', bool_and(jsonb_path_exists(metadata, '$.region ? (@ == "jp")')),
  'range_contains', bool_and(valid_during @> timestamptz '2026-08-28 12:00:00+00'),
  'generated_value', max(display_name),
  'verdict', CASE WHEN count(*) = 1 AND max(display_name) = 'atlas-order' THEN 'pass' ELSE 'fail' END
) FROM typed_order;
