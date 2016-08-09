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




/* Initialises a regular, 237A block in the specified position
 * creating the appropriate circuits and pins.
 * 
 * Returns the id of the placed block.
 */
CREATE OR REPLACE FUNCTION place_237A_block(
	p_block_id INTEGER
)
RETURNS INTEGER AS $$
DECLARE p_circuit_id INTEGER;
BEGIN
	
	IF NOT block_is_free(p_block_id) THEN
		RAISE EXCEPTION 'Cannot place block for id % - it is already in use', p_block_id;
	END IF;

	UPDATE block
	SET name = ''
	WHERE id = p_block_id;

	FOR p_circuit_position IN 1..10 LOOP

		INSERT INTO circuit(block_id, position, designation)
		VALUES(
			p_block_id,
			p_circuit_position,
			RIGHT(CAST(p_circuit_position AS TEXT), 1)
		)
		RETURNING id INTO p_circuit_id;

		FOR p_pin_position IN 1..2 LOOP
			INSERT INTO pin(circuit_id, position, designation)
			VALUES(
				p_circuit_id,
				p_pin_position,
				CASE
					WHEN p_pin_position = 1 THEN 'a'
					ELSE 'b' 
				END
			);
		END LOOP;
	END LOOP;

	RETURN p_block_id;
END
$$ LANGUAGE plpgsql;



/* Initialises a regular, ABS block in the specified position
 * creating the appropriate circuits and pins.
 * 
 * Returns the id of the placed block.
 */

CREATE OR REPLACE FUNCTION place_ABS_block(
	p_block_id INTEGER
)
RETURNS INTEGER AS $$
DECLARE p_circuit_id INTEGER;
BEGIN
	
	IF NOT block_is_free(p_block_id) THEN
		RAISE EXCEPTION 'Cannot place block for id % - it is already in use', p_block_id;
	END IF;

	UPDATE block
	SET name = ''
	WHERE id = p_block_id;

	FOR p_circuit_position IN 1..10 LOOP

		INSERT INTO circuit(block_id, position, designation)
		VALUES(
			p_block_id,
			p_circuit_position,
			RIGHT(CAST(p_circuit_position AS TEXT), 1)
		)
		RETURNING id INTO p_circuit_id;

		FOR p_pin_position IN 1..3 LOOP
			INSERT INTO pin(circuit_id, position, designation)
			VALUES(
				p_circuit_id,
				p_pin_position,
				CASE
					WHEN p_pin_position = 1 THEN 'a'
					WHEN p_pin_position = 2 THEN 'b'
					ELSE 's' 
				END
			);
		END LOOP;
	END LOOP;

	RETURN p_block_id;
END
$$ LANGUAGE plpgsql;


