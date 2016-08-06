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


/* A simple jumper connects two circuits, each having an identical
 * number of pins, connected by jumper wires with a 1:1 mapping, so
 * a->a, b->b, s->s for example. Most jumpers are like this.
 * 
 * This function returns true if the specified jumper_id represents
 * a simple jumper, false otherwise.
 */
CREATE OR REPLACE FUNCTION is_simple_jumper(
	p_jumper_id INTEGER
)
RETURNS BOOLEAN AS $$
DECLARE row_count INTEGER;
DECLARE max_pin_count INTEGER;
DECLARE min_pin_count INTEGER;
BEGIN

	/* How many pins do the circuits connected by this jumper have? */
	SELECT
		MIN(count_pins_for_circuit_id(pin.circuit_id)) AS min_pin_count,
		MAX(count_pins_for_circuit_id(pin.circuit_id)) AS max_pin_count 
	INTO max_pin_count, min_pin_count
	FROM jumper_wire
	JOIN connection ON (connection.jumper_wire_id = jumper_wire.id)
	JOIN pin ON (pin.id = connection.pin_id)
	WHERE jumper_wire.jumper_id = p_jumper_id;

	/* Do all circuits have the same number of pins?
	 * If this is a simple jumper, all circuits connected by it
	 * will have the same number of pins. In that case, this 
	 * max_pin_count and min_pin_count will be identical.
	 */
	IF max_pin_count != min_pin_count THEN
		RETURN FALSE;
	END IF;

	/* Counting the number of connections for each jumper wire,
	 * linking pin positions 1:1 should yield a count 
	 * matching the pin count of each circuit.
	 */
	SELECT COUNT(*) INTO row_count
	FROM (
		SELECT DISTINCT jumper_wire.id
		FROM jumper_wire
		JOIN connection AS connection1 ON (connection1.jumper_wire_id = jumper_wire.id)
		JOIN pin AS pin1 ON (pin1.id = connection1.pin_id)
		JOIN connection AS connection2 ON (connection2.jumper_wire_id = jumper_wire.id AND connection2.id != connection1.id)
		JOIN pin AS pin2 ON (pin2.id = connection2.pin_id)
		WHERE pin1.position = pin2.position
		AND jumper_wire.jumper_id = p_jumper_id
	) AS t;

	IF row_count != max_pin_count THEN
		RETURN FALSE;
	END IF;

	RETURN TRUE;

END
$$ LANGUAGE plpgsql;



/* Extract jumpers and which circuits they connect */
CREATE OR REPLACE VIEW jumper_circuits AS
SELECT DISTINCT 
	jumper_wire.jumper_id,
	is_simple_jumper(jumper_wire.jumper_id),
	pin1.circuit_id AS a_circuit_id,
	pin2.circuit_id AS b_circuit_id
FROM jumper_wire
JOIN connection AS connection1 ON (connection1.jumper_wire_id = jumper_wire.id)
JOIN pin AS pin1 ON (pin1.id = connection1.pin_id)
JOIN connection AS connection2 ON (
	connection2.jumper_wire_id = connection1.jumper_wire_id
	AND connection2.id != connection1.id
)
JOIN pin AS pin2 ON (pin2.id = connection2.pin_id);



/* Shows every node connected by a jumper wire
 * with designations
 */
CREATE OR REPLACE VIEW jumper_wire_nodes AS
SELECT
	jumper_wire.jumper_id AS jumper_id,
	jumper_wire.id AS jumper_wire_id,
	vertical.frame_id AS frame_id,
	CONCAT(vertical.designation, block.designation, '.', circuit.designation, pin.designation) AS full_pin_designation,
	CONCAT(vertical.designation, block.designation, '.', circuit.designation) AS full_circuit_designation,
	pin.designation AS pin_designation,
	pin.position AS pin_position
FROM connection
JOIN jumper_wire ON (jumper_wire.id = connection.jumper_wire_id)
JOIN pin ON (pin.id = connection.pin_id)
JOIN circuit ON (circuit.id = pin.circuit_id)
JOIN block ON (block.id = circuit.block_id)
JOIN vertical ON (vertical.id = block.vertical_id)
ORDER BY
  jumper_id ASC,
  jumper_wire_id ASC,
  vertical.position ASC,
  block.position ASC,
  circuit.position ASC,
  pin.position ASC;



/* Shows the connections made by each jumper wire
 */
CREATE OR REPLACE VIEW jumper_wire_connections AS
SELECT DISTINCT
	j1.jumper_id,
	j1.jumper_wire_id,
	j1.frame_id,
	colour.id AS colour_id,
	colour.name AS colour_name,
	colour.short_name AS colour_short_name,
	colour.html_code AS colour_html_code,
	ARRAY(
		SELECT full_pin_designation 
		FROM jumper_wire_nodes AS j2 
		WHERE j2.jumper_wire_id=j1.jumper_wire_id
	) AS full_pin_designations,
	ARRAY(
		SELECT full_circuit_designation 
		FROM jumper_wire_nodes AS j2 
		WHERE j2.jumper_wire_id=j1.jumper_wire_id
	) AS full_circuit_designations,
	ARRAY(
		SELECT pin_designation
		FROM jumper_wire_nodes AS j3
		WHERE j3.jumper_wire_id = j1.jumper_wire_id
	) AS pin_designations,
	is_simple_jumper(j1.jumper_id)
FROM jumper_wire_nodes AS j1
JOIN jumper_wire ON (jumper_wire.id = j1.jumper_wire_id)
JOIN colour ON (colour.id = jumper_wire.colour_id)
ORDER BY jumper_id, jumper_wire_id;
 
 

/* Shows connections info for each wire making up a jumper */
CREATE OR REPLACE VIEW jumper_wire_info AS
SELECT
	jumper_wire.jumper_id,
	jumper_wire.id AS jumper_wire_id,
	pin1.designation AS a_pin_designation,
	pin2.designation AS b_pin_designation,
	circuit1.id AS a_circuit_id,
	circuit2.id AS b_circuit_id,
	CONCAT(vertical1.designation, block1.designation, '.', circuit1.designation) AS a_circuit_full_designation,
	CONCAT(vertical2.designation, block2.designation, '.', circuit2.designation) AS b_circuit_full_designation,
	CONCAT(vertical1.designation, block1.designation, '.', circuit1.designation, pin1.designation) AS a_full_designation,
	CONCAT(vertical2.designation, block2.designation, '.', circuit2.designation, pin2.designation) AS b_full_designation,
	is_simple_jumper(jumper_wire.jumper_id),
	colour.id AS colour_id,
	colour.name AS colour_name,
	colour.short_name AS colour_short_name,
	CONCAT('#', ENCODE(colour.html_code, 'hex')) AS html_colour,
	CONCAT('#', ENCODE(colour.contrasting_html_code, 'hex')) AS contrasting_html_colour
FROM connection AS connection1
JOIN pin AS pin1 ON (pin1.id = connection1.pin_id)
JOIN circuit AS circuit1 ON (circuit1.id = pin1.circuit_id)
JOIN block AS block1 ON (block1.id = circuit1.block_id)
JOIN vertical AS vertical1 ON (vertical1.id = block1.vertical_id)
JOIN connection AS connection2 ON (
        connection2.jumper_wire_id = connection1.jumper_wire_id
        AND connection2.id != connection1.id
)
JOIN pin AS pin2 ON (pin2.id = connection2.pin_id)
JOIN circuit AS circuit2 ON (circuit2.id = pin2.circuit_id)
JOIN block AS block2 ON (block2.id = circuit2.block_id)
JOIN vertical AS vertical2 ON (vertical2.id = block2.vertical_id)
JOIN jumper_wire ON (jumper_wire.id = connection1.jumper_wire_id)
JOIN colour ON (colour.id = jumper_wire.colour_id)
ORDER BY (
	vertical1.position, block1.position, circuit1.position, pin1.position,
	vertical2.position, block2.position, circuit2.position, pin2.position,
	jumper_wire.jumper_id
);



/* Returns a nested json array describing a jumper and it's wires
 * from the point-of-view of the given circuit_id
 */
CREATE OR REPLACE FUNCTION json_jumper_info(
	p_jumper_id INTEGER,
	p_a_circuit_id INTEGER
)
RETURNS TABLE(json_data JSON) AS $$
BEGIN

	RETURN QUERY
	SELECT json_agg(u) FROM (
		SELECT
			jumper_circuits.jumper_id AS jumper_id,
			is_simple_jumper(jumper_circuits.jumper_id),
			(SELECT json_agg(t) FROM (
				SELECT *
				FROM jumper_wire_info 
				WHERE jumper_wire_info.jumper_id = jumper_circuits.jumper_id
				AND jumper_wire_info.a_circuit_id = jumper_circuits.a_circuit_id
			) AS t) AS wires
		FROM jumper_circuits
		WHERE jumper_circuits.jumper_id = p_jumper_id
		AND jumper_circuits.a_circuit_id = p_a_circuit_id
		ORDER BY jumper_circuits.jumper_id
	) AS u;

END
$$ LANGUAGE plpgsql;




/* Returns the number of wires contained within a jumper template */
CREATE OR REPLACE FUNCTION jumper_template_wire_count(
	p_jumper_template_id INTEGER
)
RETURNS INTEGER AS $$
BEGIN

	RETURN COUNT(*)
	FROM jumper_template_wire
	WHERE jumper_template_id = p_jumper_template_id;
END
$$ LANGUAGE plpgsql;



/* Inserts a new, empty jumper and returns its id */
CREATE OR REPLACE FUNCTION add_empty_jumper(
)
RETURNS INTEGER AS $$
DECLARE rv INTEGER;
BEGIN

	INSERT INTO jumper(id)
	VALUES(DEFAULT)
	RETURNING id INTO rv;

	RETURN rv;
END
$$ LANGUAGE plpgsql;



/* Deletes the given jumper_id and it's linked records */
CREATE OR REPLACE FUNCTION delete_jumper(
	p_jumper_id INTEGER
)
RETURNS BOOLEAN AS $$
BEGIN

	DELETE FROM connection
	  USING jumper_wire
	  WHERE jumper_wire.jumper_id = p_jumper_id
	  AND connection.jumper_wire_id = jumper_wire.id;

	DELETE FROM jumper_wire WHERE jumper_id = p_jumper_id;

	DELETE FROM jumper WHERE id = p_jumper_id;

	RETURN FOUND;
END
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION add_simple_jumper(
	p_circuit_id_1 INTEGER,
	p_circuit_id_2 INTEGER,
	p_jumper_template_id INTEGER
)
RETURNS INTEGER AS $$
DECLARE p_jumper_wire_count INTEGER;
DECLARE p_pin_position INTEGER;
DECLARE p_colour_id INTEGER;
DECLARE p_jumper_id INTEGER;
DECLARE p_jumper_wire_id INTEGER;
BEGIN

	/* This function connects two circuits, each having an identical
	 * number of pins, with a jumper template having a corresponding
	 * number of wires. Pins are connected with a 1:1 mapping, so
	 * a->a, b->b, s->s for example. Most jumpers are like this.
	 * This does not handle split pairs or phase reversals.
	 * A check is made to make sure the circuits belong to the same 
	 * frame and are not already connected.
	 * A warning is issued if this action results in more than two wires
	 * being connected to a single jumper pin.
	 *
	 * Returns the jumper_id of the new jumper
	 */

	/* Check circuits belong to the same frame */
	IF frame_id_for_circuit_id(p_circuit_id_1) != frame_id_for_circuit_id(p_circuit_id_2) THEN
		RAISE EXCEPTION 'Cannot add jumper between % and %: circuits are not on same frame',
			p_circuit_id_1,
			p_circuit_id_2;
	END IF;

	/* Check pin count matches on both ends of jumper */
	IF count_pins_for_circuit_id(p_circuit_id_1) != count_pins_for_circuit_id(p_circuit_id_2) THEN
		RAISE EXCEPTION 'Cannot add simple jumper between % and %: number of pins is different on each end',
			p_circuit_id_1,
			p_circuit_id_2;
	END IF;

	/* Get jumper details */
	p_jumper_wire_count := count_wires_for_jumper_template_id(p_jumper_template_id);

	/* Check number of wires for the jumper corresponds to the circuit pins */
	IF p_jumper_wire_count != count_pins_for_circuit_id(p_circuit_id_1) THEN
		RAISE EXCEPTION 'Cannot connect simple jumper: jumper template has different number of wires to connection pins';
	END IF;

	/* Check pins aren't already connected */
	IF circuit_ids_are_connected(p_circuit_id_1, p_circuit_id_2) THEN
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
		AND pin.circuit_id IN (p_circuit_id_1, p_circuit_id_2);

	END LOOP;

	RETURN p_jumper_id;
END
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION add_jumper_wire(
	p_jumper_id INTEGER,
	p_pin_id_1 INTEGER,
	p_pin_id_2 INTEGER,
	p_colour_id INTEGER
)
RETURNS INTEGER AS $$
DECLARE p_jumper_wire_id INTEGER;
BEGIN

	/* Check pins belong to the same frame */
	IF frame_id_for_pin_id(p_pin_id_1) != frame_id_for_pin_id(p_pin_id_2) THEN
		RAISE EXCEPTION 'Cannot add jumper between pins % and %: pins are not on same frame',
			p_pin_id_1,
			p_pin_id_2;
	END IF;

	/* Check any existing wires on this jumper belong to the same frame */
	IF EXISTS (
		SELECT 1
		FROM jumper_wire
		JOIN connection ON (connection.jumper_wire_id = jumper_wire.id)
		WHERE jumper_wire.jumper_id = p_jumper_id
		AND frame_id_for_pin_id(connection.pin_id) != frame_id_for_pin_id(p_pin_id_1)
	) THEN 
		RAISE EXCEPTION 'Cannot add jumper between pins % and %: pins are not on same frame as jumper %',
			p_pin_id_1,
			p_pin_id_2,
			p_jumper_id;
	END IF;

	/* Check pins aren't already connected */
	IF pin_ids_are_connected(p_pin_id_1, p_pin_id_2) THEN
		RAISE EXCEPTION 'Cannot add jumper between pins % and %: pins are already connected',
			p_pin_id_1,
			p_pin_id_2;
	END IF;

	/* Create the jumper wire */
	INSERT INTO jumper_wire(jumper_id, colour_id)
	VALUES(p_jumper_id, p_colour_id)
	RETURNING id INTO p_jumper_wire_id;

	/* Connect each end of the wire */
	INSERT INTO connection (jumper_wire_id, pin_id)
	VALUES 
	(p_jumper_wire_id, p_pin_id_1),
	(p_jumper_wire_id, p_pin_id_2);

	RETURN p_jumper_wire_id;
END
$$ LANGUAGE plpgsql;


