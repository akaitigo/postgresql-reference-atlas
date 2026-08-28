\set ON_ERROR_STOP on
CREATE TABLE ledger_entry (
  id bigint PRIMARY KEY,
  account_id integer NOT NULL,
  amount numeric(12,2) NOT NULL CHECK (amount <> 0),
  booked_at timestamptz NOT NULL
);
INSERT INTO ledger_entry
SELECT g, (g % 97) + 1, ((g % 200) - 100)::numeric(12,2),
       timestamptz '2026-01-01 00:00:00+00' + g * interval '1 minute'
FROM generate_series(1, 10000) AS g
WHERE g % 200 <> 100;
