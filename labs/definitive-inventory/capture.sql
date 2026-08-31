\set ON_ERROR_STOP on
SELECT json_build_object('domain','runtime-type','key',t.oid::text,'title',n.nspname||'.'||t.typname,'locator','pg_type:'||t.oid)::text
FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname IN ('pg_catalog','information_schema') ORDER BY t.oid;
SELECT json_build_object('domain','runtime-function','key',p.oid::text,'title',n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')','locator','pg_proc:'||p.oid)::text
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='pg_catalog' ORDER BY p.oid;
SELECT json_build_object('domain','runtime-operator','key',o.oid::text,'title',n.nspname||'.'||o.oprname||'('||o.oprleft::regtype::text||','||o.oprright::regtype::text||')','locator','pg_operator:'||o.oid)::text
FROM pg_operator o JOIN pg_namespace n ON n.oid=o.oprnamespace WHERE n.nspname='pg_catalog' ORDER BY o.oid;
SELECT json_build_object('domain','runtime-cast','key',c.oid::text,'title',c.castsource::regtype::text||' -> '||c.casttarget::regtype::text||' ['||c.castcontext::text||'/'||c.castmethod::text||']','locator','pg_cast:'||c.oid)::text FROM pg_cast c ORDER BY c.oid;
SELECT json_build_object('domain','system-catalog','key',c.oid::text,'title',n.nspname||'.'||c.relname,'locator','pg_class:'||c.oid)::text
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('pg_catalog','information_schema') AND c.relkind IN ('r','v','m','S') ORDER BY c.oid;
SELECT json_build_object('domain','guc','key',name,'title',name||' ['||context||'; '||vartype||']','locator','pg_settings:'||name)::text FROM pg_settings ORDER BY name;
SELECT json_build_object('domain','extension','key',name,'title',name||' '||default_version,'locator','pg_available_extensions:'||name)::text FROM pg_available_extensions ORDER BY name;
SELECT json_build_object('domain','access-method','key',oid::text,'title',amname||' ['||amtype::text||']','locator','pg_am:'||oid)::text FROM pg_am ORDER BY oid;
SELECT json_build_object('domain','collation','key',c.oid::text,'title',n.nspname||'.'||c.collname||' ['||c.collprovider::text||']','locator','pg_collation:'||c.oid)::text
FROM pg_collation c JOIN pg_namespace n ON n.oid=c.collnamespace ORDER BY c.oid;
