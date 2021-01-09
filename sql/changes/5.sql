-- Schema changes v4 to v5
ALTER TABLE block
ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE block
ADD CONSTRAINT inactive_block_must_be_empty
CHECK (
	is_active IS TRUE
	OR (
		name IS NULL
		AND block_type_id IS NULL
		AND colour_html_code IS NULL
	)
);

UPDATE kronekeeper_data SET value=5 WHERE key='db_version';

RAISE NOTICE 'Now reload frame.sql, block.sql, grant_permisions.sql';
