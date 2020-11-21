-- Schema changes v4 to v5
CREATE OR REPLACE VIEW vertical_info AS
SELECT
        vertical.id AS id,
        vertical.position AS position,
        vertical.designation AS designation,
        frame.id AS frame_id,
        frame.name AS frame_name,
        frame.account_id AS account_id
FROM vertical
JOIN frame ON (vertical.frame_id = frame.id);

UPDATE kronekeeper_data SET value=5 WHERE key='db_version';

RAISE NOTICE 'Now reload grant_permisions.sql';
