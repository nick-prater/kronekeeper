-- Schema changes v1 to v2
ALTER TABLE account ADD COLUMN max_frame_count INTEGER;
ALTER TABLE account ADD COLUMN max_frame_width INTEGER;
ALTER TABLE account ADD COLUMN max_frame_height INTEGER;
ALTER TABLE activity_log ADD COLUMN jumper_id INTEGER;

DROP FUNCTION IF EXISTS al_log_activity(
	INTEGER,
	INTEGER,
	TEXT,
	TEXT,
	INTEGER,
	INTEGER
);

DROP FUNCTION IF EXISTS al_log_activity(
	INTEGER,
	INTEGER,
	INTEGER,
	TEXT,
	TEXT,
	INTEGER,
	INTEGER
);

UPDATE kronekeeper_data SET value=2 WHERE key='db_version';

RAISE NOTICE "Now reload copy_block.sql, place_template.sql";

