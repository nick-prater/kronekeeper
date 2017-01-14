/*
This file is part of Kronekeeper, a web based application for 
recording and managing wiring frame records.

Copyright (C) 2016-2017 NP Broadcast Limited

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



/* Functions used to manipulate krone records from the command
 * line. Those functions pre-fixed with c_ use the human-readable
 * combined designation to indentify blocks, rather than the internal
 * database ids. For this to work, it's assumed that blocks and verticals
 * have been designated using the common UK commercial radio convention
 * where 'A07' refers to the seventh block in the first vertical. If this
 * default convention has been overridden, the functions will not work.
 */



/* Given a combined human-readable block designation (e.g. 'B12'), return
 * the column designation part (e.g. 'B').
 */
CREATE OR REPLACE FUNCTION c_designation_to_vertical_designation(
	c_designation TEXT
)
RETURNS TEXT AS $$
BEGIN
	RETURN (regexp_matches(c_designation, '^([A-Z]+)([0-9]+)(?:\.([0-9]+))?$'))[1];
END 
$$ LANGUAGE plpgsql;



/* Given a combined human-readable block designation (e.g. 'B12'), return
 * the block designation part (e.g. '12').
 */
CREATE OR REPLACE FUNCTION c_designation_to_block_designation(
	c_designation TEXT
)
RETURNS TEXT AS $$
BEGIN
	RETURN (regexp_matches(c_designation, '^([A-Z]+)([0-9]+)(?:\.([0-9]+))?$'))[2];
END 
$$ LANGUAGE plpgsql;


/* Given a combined human-readable block designation (e.g. 'B12.9'), return
 * the circuit designation part (e.g. '9').
 */
CREATE OR REPLACE FUNCTION c_designation_to_circuit_designation(
	c_designation TEXT
)
RETURNS TEXT AS $$
BEGIN
	RETURN (regexp_matches(c_designation, '^([A-Z]+)([0-9]+)(?:\.([0-9]+))?$'))[3];
END 
$$ LANGUAGE plpgsql;


/* Given a combined human-readable block designation (e.g. 'B12'), return
 * the database block.id
 */
CREATE OR REPLACE FUNCTION c_designation_to_block_id(
	p_frame_id INTEGER,
	c_designation TEXT
)
RETURNS INTEGER AS $$
DECLARE rv INTEGER;
BEGIN

	SELECT block.id INTO rv
	FROM block
	JOIN vertical ON (vertical.id = block.vertical_id)
	WHERE vertical.frame_id = p_frame_id
	AND vertical.designation = c_designation_to_vertical_designation(c_designation)
	AND (
		TRIM(LEADING '0' FROM block.designation) = 
		TRIM(LEADING '0' FROM c_designation_to_block_designation(c_designation))
	);

	RETURN rv;
END 
$$ LANGUAGE plpgsql;


/* Given a combined human-readable block designation (e.g. 'B12.9'), return
 * a one-row table the database circuit, block and frame ids
 */
CREATE OR REPLACE FUNCTION c_designation_to_circuit(
	p_frame_id INTEGER,
	c_designation TEXT
)
RETURNS TABLE (
	vertical_id INTEGER,
	block_id INTEGER,
	circuit_id INTEGER
) AS $$
BEGIN

	RETURN QUERY SELECT
		vertical.id AS vertical_id,
		block.id AS block_id,
		circuit.id AS circuit_id
	FROM circuit
	JOIN block ON (block.id = circuit.block_id)
	JOIN vertical ON (vertical.id = block.vertical_id)
	WHERE vertical.frame_id = p_frame_id
	AND vertical.designation = c_designation_to_vertical_designation(c_designation)
	AND (
		TRIM(LEADING '0' FROM block.designation) = 
		TRIM(LEADING '0' FROM c_designation_to_block_designation(c_designation))
	)
	AND circuit.designation = c_designation_to_circuit_designation(c_designation);
	
END 
$$ LANGUAGE plpgsql;


/* Given a combined human-readable block designation (e.g. 'B12.9'), return
 * the corresponding circuit_id. Raise an exception if there is no corresponding
 * circuit_id
 */
CREATE OR REPLACE FUNCTION c_designation_to_circuit_id(
	p_frame_id INTEGER,
	c_designation TEXT
)
RETURNS INTEGER AS $$
DECLARE rv INTEGER;
BEGIN

	SELECT circuit_id INTO rv FROM c_designation_to_circuit(p_frame_id, c_designation);
	IF rv IS NULL THEN
		RAISE EXCEPTION '% does not map to a valid circuit_id', c_designation;
	END IF;

	RETURN rv;
END
$$ LANGUAGE plpgsql;


/* Renames a block.
 * Returns the block_id of the renamed block
 * Raises an exception if the specified designation doesn't map to a valid block 
 */
CREATE OR REPLACE FUNCTION c_rename_block(
	p_frame_id INTEGER,
	c_designation TEXT,
	p_name TEXT
)
RETURNS INTEGER AS $$
DECLARE p_block_id INTEGER;
BEGIN

	p_block_id := c_designation_to_block_id(p_frame_id, c_designation);

	UPDATE block
	SET name = p_name
	WHERE id = p_block_id;

	RETURN p_block_id;
END
$$ LANGUAGE plpgsql;


/* Renames a circuit.
 * Returns the circuit_id of the renamed block
 * Raises an exception if the specified designation doesn't map to a valid circuit 
 */
CREATE OR REPLACE FUNCTION c_rename_circuit(
	p_frame_id INTEGER,
	c_designation TEXT,
	p_name TEXT
)
RETURNS INTEGER AS $$
DECLARE p_circuit_id INTEGER;
BEGIN

	p_circuit_id := c_designation_to_circuit_id(p_frame_id, c_designation);

	UPDATE circuit
	SET name = p_name
	WHERE id = p_circuit_id;

	RETURN p_circuit_id;
END
$$ LANGUAGE plpgsql;




/* Returns true if a block position free for use, 
 * confirming that:
 *  1) it is valid for the given frame
 *  2) it is not in use as a label position (check block.name IS NULL)
 *  3) it has no associated circuits
 */
CREATE OR REPLACE FUNCTION c_block_is_free(
	p_frame_id INTEGER,
	c_designation TEXT	
)
RETURNS BOOLEAN AS $$
DECLARE p_block_id INTEGER;
DECLARE circuit_count INTEGER;
BEGIN

	SELECT c_designation_to_block_id(p_frame_id, c_designation) INTO p_block_id;
	IF p_block_id IS NULL THEN
		RAISE EXCEPTION 'Block % is not valid for this frame', c_designation;
	END IF;

	IF NOT EXISTS (SELECT 1 FROM block WHERE id = p_block_id AND name IS NULL) THEN
		RAISE NOTICE 'Block % is in use - it has a name.', c_designation;
		RETURN FALSE;
	END IF;

	SELECT COUNT(*) INTO circuit_count
	FROM circuit
	WHERE block_id = p_block_id;

	IF circuit_count != 0 THEN
		RAISE NOTICE 'Block %u is in use - it has %u associated circuits.', c_designation, circuit_count;
		RETURN FALSE;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;



/* Initialises a regular, 237A block in the specified position
 * creating the appropriate circuits and pins. Position is 
 * specified by human-readable designation, rather than by 
 * database ids. This is a helper function for command-line
 * manipulation of the database.
 * 
 * Returns the id of the created block.
 */
CREATE OR REPLACE FUNCTION create_237_block(
	p_frame_id INTEGER,
	c_designation TEXT,
	p_name TEXT
)
RETURNS INTEGER AS $$
DECLARE p_block_id INTEGER;
DECLARE p_circuit_id INTEGER;
DECLARE p_pin_id INTEGER;
BEGIN
	
	IF NOT c_block_is_free(p_frame_id, c_designation) THEN
		RAISE EXCEPTION 'Cannot create block in position % it is already in use', c_designation;
	END IF;

	p_block_id := c_designation_to_block_id(p_frame_id, c_designation);

	UPDATE block
	SET name = p_name
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
				CASE WHEN p_pin_position = 1 THEN 'a' ELSE 'b' END
			);
		END LOOP;
	END LOOP;

	RETURN p_block_id;
END
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION c_add_simple_jumper(
	p_frame_id INTEGER,
	c_designation_1 TEXT,
	c_designation_2 TEXT,
	p_jumper_template_designation TEXT
)
RETURNS INTEGER AS $$
DECLARE circuit_id_1 INTEGER;
DECLARE circuit_id_2 INTEGER;
DECLARE p_jumper_wire_count INTEGER;
DECLARE p_jumper_template_id INTEGER;
DECLARE p_colour_id INTEGER;
DECLARE p_jumper_id INTEGER;
DECLARE p_jumper_wire_id INTEGER;
BEGIN

	/* This function connects two circuits, each having an identical
	 * number of pins, with a jumper template having a corresponding
	 * number of wires. Pins are connected with a 1:1 mapping, so
	 * a->a, b->b, s->s for example. Most jumpers are like this.
	 * This does not handle split pairs or phase reversals.
	 * A check is made to make sure the circuits are not already connected.
	 * A warning is issued if this action results in more than two wires
	 * being connected to a single jumper pin.
	 */

	/* Get underlying circuit_ids for each end */	
	circuit_id_1 := c_designation_to_circuit_id(p_frame_id, c_designation_1);
	circuit_id_2 := c_designation_to_circuit_id(p_frame_id, c_designation_2);

	/* Check pin count matches on both ends of jumper */
	IF count_pins_for_circuit_id(circuit_id_1) != count_pins_for_circuit_id(circuit_id_2) THEN
		RAISE EXCEPTION 'Cannot add simple jumper between % and %: number of pins is different on each end',
			c_designation_1,
			c_designation_2;
	END IF;

	/* Get jumper details */
	p_jumper_template_id := jumper_template_designation_to_id(p_jumper_template_designation);
	p_jumper_wire_count := count_wires_for_jumper_template_id(p_jumper_template_id);

	/* Check number of wires for the jumper corresponds to the circuit pins */
	IF p_jumper_wire_count != count_pins_for_circuit_id(circuit_id_1) THEN
		RAISE EXCEPTION 'Cannot connect simple jumper: jumper template has different number of wires to connection pins';
	END IF;

	/* Check pins aren't already connected */
	IF circuit_ids_are_connected(circuit_id_1, circuit_id_2) THEN
		RAISE EXCEPTION 'A jumper already exists between these circuits';
	END IF;


	/* Create parent jumper */
	INSERT INTO jumper(id)
	VALUES(DEFAULT)
	RETURNING id INTO p_jumper_id;

	FOR p_pin_position IN 1..p_jumper_wire_count LOOP

		p_colour_id := wire_colour_id_for_jumper_template_position(
			p_jumper_template_id,
			p_pin_position
		);

		INSERT INTO jumper_wire(jumper_id, colour_id)
		VALUES(p_jumper_id, p_colour_id)
		RETURNING id INTO p_jumper_wire_id;			
	
		/* Now connect a wire between the corresponding pin of each circuit */
		INSERT INTO connection (jumper_wire_id, pin_id)
		SELECT p_jumper_wire_id, pin.id
		FROM pin
		WHERE pin.position = p_pin_position
		AND pin.circuit_id IN (circuit_id_1, circuit_id_2);

	END LOOP;

	RETURN p_jumper_id;
END
$$ LANGUAGE plpgsql;


/* These commands below are for illustration and were used in testing... */
/* Show block detail */
/*
SELECT
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
FROM vertical
JOIN block ON (block.vertical_id = vertical.id)
JOIN circuit ON (circuit.block_id = block.id)
WHERE vertical.frame_id = 5
AND vertical.designation = 'A'
AND block.designation = '02'
ORDER BY block.position ASC, circuit.position ASC;
*/


/* Show jumpers for given circuit */
/*
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
WHERE circuit1.id = 10;
*/

/* Show frame detail */
/*
SELECT CONCAT(vertical.designation, block.designation) AS designation, block.name
FROM block
JOIN vertical ON (vertical.id = block.vertical_id)
WHERE vertical.frame_id = 5
ORDER BY vertical.position ASC, block.position ASC;
*/

