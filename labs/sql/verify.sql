\set ON_ERROR_STOP on
CREATE TABLE account (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  external_id text NOT NULL UNIQUE,
  balance numeric(12,2) NOT NULL CHECK (balance >= 0)
);

DO $$
DECLARE
  inserted_id bigint;
  observed_state text;
BEGIN
  INSERT INTO account(external_id, balance)
  VALUES ('acct-001', 100.00)
  RETURNING id INTO inserted_id;
  IF inserted_id IS NULL THEN
    RAISE EXCEPTION 'RETURNING did not produce id';
  END IF;

  BEGIN
    INSERT INTO account(external_id, balance) VALUES ('acct-001', 10.00);
    RAISE EXCEPTION 'unique violation was not raised';
  EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS observed_state = RETURNED_SQLSTATE;
    IF observed_state <> '23505' THEN
      RAISE EXCEPTION 'unexpected SQLSTATE: %', observed_state;
    END IF;
  END;

  BEGIN
    INSERT INTO account(external_id, balance) VALUES ('acct-002', -1.00);
    RAISE EXCEPTION 'check violation was not raised';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS observed_state = RETURNED_SQLSTATE;
    IF observed_state <> '23514' THEN
      RAISE EXCEPTION 'unexpected SQLSTATE: %', observed_state;
    END IF;
  END;
END $$;

SELECT json_build_object(
  'lab', 'sql',
  'server_version', current_setting('server_version'),
  'accepted_rows', count(*),
  'balance', sum(balance),
  'verdict', CASE WHEN count(*) = 1 AND sum(balance) = 100.00 THEN 'pass' ELSE 'fail' END
) FROM account;
