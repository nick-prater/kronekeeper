-- Schema changes v3 to v4
INSERT INTO role (role, rank) VALUES ('configure_block_types', 500);
INSERT INTO role (role, rank) VALUES ('configure_jumper_templates', 500);

UPDATE kronekeeper_data SET value=4 WHERE key='db_version';

RAISE NOTICE "Now reload sql/block_type.sql";
RAISE NOTICE "Now reload sql/create_account.sql";
