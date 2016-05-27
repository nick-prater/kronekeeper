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


CREATE OR REPLACE VIEW block_info AS
SELECT
	block.id,
	block.name,
	CONCAT(vertical.designation, block.designation) AS full_designation,
	frame.id AS frame_id,
	frame.name AS frame_name
FROM block
JOIN vertical ON (vertical.id = block.vertical_id)
JOIN frame ON (frame.id = vertical.frame_id);



/* Show block circuits */
CREATE OR REPLACE VIEW block_circuits AS
SELECT
	block.id AS block_id,
	circuit.id AS circuit_id,
	circuit.designation,
	circuit.name,
	circuit.cable_reference,
	ARRAY(
		SELECT DISTINCT CONCAT(vertical2.designation, block2.designation, '.', circuit2.designation)
		FROM connection AS connection1
		JOIN pin AS pin1 ON (pin1.id = connection1.pin_id)
		JOIN circuit AS circuit1 ON (circuit1.id = pin1.circuit_id)
		JOIN connection AS connection2 ON (
			connection2.jumper_wire_id = connection1.jumper_wire_id
			AND connection2.id != connection1.id
		)
		JOIN pin AS pin2 ON (pin2.id = connection2.pin_id)
		JOIN circuit AS circuit2 ON (circuit2.id = pin2.circuit_id)
		JOIN block AS block2 ON (block2.id = circuit2.block_id)
		JOIN vertical AS vertical2 ON (vertical2.id = block2.vertical_id)
		WHERE circuit1.id = circuit.id
	) AS jumpers
FROM block
JOIN circuit ON (circuit.block_id = block.id)
ORDER BY block_id ASC, block.position ASC, circuit.position ASC;


