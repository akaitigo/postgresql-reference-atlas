\set ON_ERROR_STOP on
WITH
types AS (
  SELECT count(*) AS count, md5(string_agg(oid::text || ':' || typname || ':' || typtype::text || ':' || typcategory::text, ',' ORDER BY oid)) AS digest
  FROM pg_type WHERE typnamespace = 'pg_catalog'::regnamespace
),
functions AS (
  SELECT count(*) AS count, md5(string_agg(oid::text || ':' || proname || ':' || pg_get_function_identity_arguments(oid) || ':' || prorettype::text || ':' || provolatile::text || ':' || proparallel::text, ',' ORDER BY oid)) AS digest
  FROM pg_proc WHERE pronamespace = 'pg_catalog'::regnamespace
),
operators AS (
  SELECT count(*) AS count, md5(string_agg(oid::text || ':' || oprname || ':' || oprleft::text || ':' || oprright::text || ':' || oprresult::text, ',' ORDER BY oid)) AS digest
  FROM pg_operator WHERE oprnamespace = 'pg_catalog'::regnamespace
),
casts AS (
  SELECT count(*) AS count, md5(string_agg(oid::text || ':' || castsource::text || ':' || casttarget::text || ':' || castcontext::text || ':' || castmethod::text, ',' ORDER BY oid)) AS digest
  FROM pg_cast
),
access_methods AS (
  SELECT count(*) AS count, md5(string_agg(oid::text || ':' || amname || ':' || amtype::text, ',' ORDER BY oid)) AS digest
  FROM pg_am
),
collations AS (
  SELECT count(*) AS count, md5(string_agg(oid::text || ':' || collname || ':' || collprovider::text || ':' || collencoding::text, ',' ORDER BY oid)) AS digest
  FROM pg_collation
),
extensions AS (
  SELECT count(*) AS count, md5(string_agg(name || ':' || default_version || ':' || (installed_version IS NOT NULL)::text, ',' ORDER BY name)) AS digest
  FROM pg_available_extensions
),
catalog_relations AS (
  SELECT count(*) AS count, md5(string_agg(c.oid::text || ':' || c.relname || ':' || c.relkind::text, ',' ORDER BY c.oid)) AS digest
  FROM pg_class c WHERE c.relnamespace = 'pg_catalog'::regnamespace AND c.relkind IN ('r','v','m','S')
)
SELECT json_build_object(
  'lab', 'catalog-inventory',
  'server_version', current_setting('server_version'),
  'types', (SELECT json_build_object('count', count, 'digest', digest) FROM types),
  'functions', (SELECT json_build_object('count', count, 'digest', digest) FROM functions),
  'operators', (SELECT json_build_object('count', count, 'digest', digest) FROM operators),
  'casts', (SELECT json_build_object('count', count, 'digest', digest) FROM casts),
  'access_methods', (SELECT json_build_object('count', count, 'digest', digest) FROM access_methods),
  'collations', (SELECT json_build_object('count', count, 'digest', digest) FROM collations),
  'available_extensions', (SELECT json_build_object('count', count, 'digest', digest) FROM extensions),
  'catalog_relations', (SELECT json_build_object('count', count, 'digest', digest) FROM catalog_relations),
  'verdict', CASE WHEN
    (SELECT count FROM types) > 100 AND (SELECT count FROM functions) > 1000 AND
    (SELECT count FROM operators) > 500 AND (SELECT count FROM casts) > 100 AND
    (SELECT count FROM access_methods) >= 7 AND (SELECT count FROM extensions) > 20 AND
    (SELECT count FROM catalog_relations) > 50
    THEN 'pass' ELSE 'fail' END
);
