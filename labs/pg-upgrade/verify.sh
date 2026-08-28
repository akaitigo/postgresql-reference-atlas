#!/usr/bin/env sh
set -eu
old_bindir=/opt/postgresql/17/bin
new_bindir=/usr/local/bin
old_data=/work/old
new_data=/work/new
mkdir -p "$old_data" "$new_data"
chown -R postgres:postgres /work

gosu postgres "$old_bindir/initdb" -D "$old_data" --no-locale --encoding=UTF8 --auth=trust --data-checksums >/tmp/init-old.log
gosu postgres "$old_bindir/pg_ctl" -D "$old_data" -o "-k /tmp -p 5417 -c listen_addresses=''" -w start >/tmp/start-old.log
gosu postgres "$old_bindir/createdb" -h /tmp -p 5417 atlas
gosu postgres "$old_bindir/psql" -X -q -v ON_ERROR_STOP=1 -h /tmp -p 5417 -d atlas <<'SQL'
CREATE TABLE upgrade_probe(id bigint PRIMARY KEY, payload text NOT NULL);
INSERT INTO upgrade_probe SELECT g, md5(g::text) FROM generate_series(1, 50000) AS g;
SQL
old_version="$(gosu postgres "$old_bindir/psql" -X -qAt -h /tmp -p 5417 -d postgres -c 'SHOW server_version')"
old_digest="$(gosu postgres "$old_bindir/psql" -X -qAt -h /tmp -p 5417 -d atlas -c "SELECT md5(string_agg(id::text || ':' || payload, ',' ORDER BY id)) FROM upgrade_probe")"
gosu postgres "$old_bindir/pg_ctl" -D "$old_data" -m fast -w stop >/tmp/stop-old.log

gosu postgres "$new_bindir/initdb" -D "$new_data" --no-locale --encoding=UTF8 --auth=trust --data-checksums >/tmp/init-new.log
cd /work
gosu postgres "$new_bindir/pg_upgrade" --old-bindir="$old_bindir" --new-bindir="$new_bindir" \
  --old-datadir="$old_data" --new-datadir="$new_data" --socketdir=/tmp --check >&2
gosu postgres "$new_bindir/pg_upgrade" --old-bindir="$old_bindir" --new-bindir="$new_bindir" \
  --old-datadir="$old_data" --new-datadir="$new_data" --socketdir=/tmp >&2
gosu postgres "$new_bindir/pg_ctl" -D "$new_data" -o "-k /tmp -p 5418 -c listen_addresses=''" -w start >/tmp/start-new.log
new_version="$(gosu postgres "$new_bindir/psql" -X -qAt -h /tmp -p 5418 -d postgres -c 'SHOW server_version')"
new_digest="$(gosu postgres "$new_bindir/psql" -X -qAt -h /tmp -p 5418 -d atlas -c "SELECT md5(string_agg(id::text || ':' || payload, ',' ORDER BY id)) FROM upgrade_probe")"
row_count="$(gosu postgres "$new_bindir/psql" -X -qAt -h /tmp -p 5418 -d atlas -c 'SELECT count(*) FROM upgrade_probe')"
gosu postgres "$new_bindir/pg_ctl" -D "$new_data" -m fast -w stop >/tmp/stop-new.log

verdict=fail
case "$old_version:$new_version:$row_count:$old_digest:$new_digest" in
  17.11:18.6:50000:* )
    if [ "$old_digest" = "$new_digest" ]; then verdict=pass; fi
    ;;
esac
printf '{"lab":"pg-upgrade","old_version":"%s","new_version":"%s","rows":%s,"old_digest":"%s","new_digest":"%s","check":"pass","verdict":"%s"}\n' \
  "$old_version" "$new_version" "$row_count" "$old_digest" "$new_digest" "$verdict"
[ "$verdict" = pass ]
