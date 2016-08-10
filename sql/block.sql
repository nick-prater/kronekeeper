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




/* This function returns a table with a single row, containing a nested json array 
 * structure representing the circuits on the given block, along with their
 * jumpers and the wires making up those jumpers...
 *
 * In other words, nested array of circuits->jumpers->wires
 *
 * This combines everything into a single query, the result of which can be returned
 * straight to the browser. Otherwise, we'd be using middleware to individually
 * query jumpers and wires to build a data structure. On the minus side, this required
 * at least postgresql 9.4 and is possibly harder to read?
 */
CREATE OR REPLACE FUNCTION json_block_circuits(
	p_block_id INTEGER
)
RETURNS TABLE(json_data JSON) AS $$
BEGIN

	RETURN QUERY
	SELECT json_agg(v) FROM (
		SELECT
			block.id AS block_id,
			circuit.id AS circuit_id,
			circuit.designation,
			circuit.name,
			circuit.cable_reference,
			circuit.connection,
			(
				SELECT json_agg(u) FROM (
					SELECT
						jumper_circuits.jumper_id AS jumper_id,
						is_simple_jumper(jumper_circuits.jumper_id),
						(SELECT json_agg(t) FROM (
							SELECT *
							FROM jumper_wire_info 
							WHERE jumper_wire_info.jumper_id = jumper_circuits.jumper_id
							AND jumper_wire_info.a_circuit_id = jumper_circuits.a_circuit_id
						) AS t)	AS wires
					FROM jumper_circuits
					WHERE jumper_circuits.a_circuit_id = circuit.id
					ORDER BY jumper_circuits.jumper_id
				) AS u
			) AS jumpers
		FROM block
		JOIN circuit ON (circuit.block_id = block.id)
		WHERE block.id = p_block_id
		ORDER BY block_id ASC, block.position ASC, circuit.position ASC
	) AS v;
END
$$ LANGUAGE plpgsql;



/* Removes the given block_id and it's associated pins and circuits.
 * But note this leaves the block position itself intact, so it reains
 * available for a new block to be placed there later
 */
CREATE OR REPLACE FUNCTION remove_block(
	p_block_id INTEGER
)
RETURNS BOOLEAN AS $$
BEGIN

	DELETE FROM pin
	USING circuit
	WHERE circuit.block_id = p_block_id
	AND pin.circuit_id = circuit.id;

	DELETE FROM circuit
	WHERE circuit.block_id = p_block_id;

	/* Setting a block's name to NULL means it
	 * is considered as an available position
	 */
	UPDATE block
	SET name = NULL
	WHERE block.id = p_block_id;

	RETURN FOUND;
END
$$ LANGUAGE plpgsql;



