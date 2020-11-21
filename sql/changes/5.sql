-- Schema changes v4 to v5
UPDATE kronekeeper_data SET value=5 WHERE key='db_version';
RAISE NOTICE 'Now reload frame.sql, grant_permisions.sql';
