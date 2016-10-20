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



CREATE OR REPLACE FUNCTION place_generic_block_type(
	p_block_id INTEGER,
	p_block_type_id INTEGER
)
RETURNS INTEGER AS $$
DECLARE p_circuit_id INTEGER;
DECLARE p_circuit_count INTEGER;
DECLARE p_circuit_pin_count INTEGER;
BEGIN

	/* Get parameters for the block we are placing */
	SELECT
		circuit_count, circuit_pin_count
		INTO p_circuit_count, p_circuit_pin_count
	FROM block_type
	WHERE block_type.id = p_block_type_id;

	/* Validation */
	CASE
		WHEN NOT block_is_free(p_block_id) THEN
			RAISE EXCEPTION 'Cannot place block for id % - it is already in use', p_block_id;
		WHEN p_circuit_count IS NULL OR p_circuit_count < 0 THEN
			RAISE EXCEPTION 'Invalid block_type_id (yielded invalid circuit_count)';
		WHEN p_circuit_count > 1 AND (p_circuit_pin_count IS NULL OR p_circuit_pin_count  < 1) THEN
			RAISE EXCEPTION 'when circuit_count > 1, circuit_pin_count cannot be null or less than 1';
		WHEN p_circuit_pin_count > 3 THEN
			RAISE EXCEPTION 'circuit_pin_count > 3 is not currently supported as further pin designations are not yet defined';
		ELSE -- validation OK
	END CASE;


	UPDATE block SET
		name = '',
		block_type_id = p_block_type_id
	WHERE id = p_block_id;


	FOR p_circuit_position IN 1..p_circuit_count LOOP

		INSERT INTO circuit(block_id, position, designation)
		VALUES(
			p_block_id,
			p_circuit_position,
			RIGHT(CAST(p_circuit_position AS TEXT), 1)
		)
		RETURNING id INTO p_circuit_id;

		FOR p_pin_position IN 1..p_circuit_pin_count LOOP
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


