/*
This file is part of Kronekeeper, a web based application for 
recording and managing wiring frame records.

Copyright (C) 2016 NP Broadcast Limited

Kronekeeper is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Kronekeeper is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with Kronekeeper.  If not, see <http://www.gnu.org/licenses/>.
*/



/* Returns true if the specified block.id position is free for use, 
 * confirming that:
 *  1) it exists
 *  2) it is not in use as a label position (check block.name IS NULL)
 *  3) it has no associated circuits
 */
CREATE OR REPLACE FUNCTION block_is_free(
	p_block_id INTEGER
)
RETURNS BOOLEAN AS $$
DECLARE circuit_count INTEGER;
BEGIN

	IF NOT EXISTS (SELECT 1 FROM block WHERE id = p_block_id) THEN
		RAISE NOTICE 'block_id % does not exist', p_block_id;
		RETURN FALSE;
	END IF;

	IF EXISTS (SELECT 1 FROM block WHERE id = p_block_id AND name IS NOT NULL) THEN
		RAISE NOTICE 'block_id % is in use - it has a name.', p_block_id;
		RETURN FALSE;
	END IF;

	SELECT COUNT(*) INTO circuit_count
	FROM circuit
	WHERE block_id = p_block_id;

	IF circuit_count != 0 THEN
		RAISE NOTICE 'block_id %u is in use - it has %u associated circuits.', p_block_id, circuit_count;
		RETURN FALSE;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;


