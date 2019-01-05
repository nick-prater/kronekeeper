-- Schema changes v2 to v3
INSERT INTO role (role, rank) VALUES ('manage_accounts', 2000);
DROP FUNCTION create_account(TEXT);
UPDATE kronekeeper_data SET value=3 WHERE key='db_version';

RAISE NOTICE "Now reload sql/create_account.sql";
