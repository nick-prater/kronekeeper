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
DECLARE circuit_count INTEGER;
DECLARE row_count INTEGER;
BEGIN
	/* Do all circuits have the same number of pins?
	 * If this is a simple jumper, all circuits connected by it
	 * will have the same number of pins. In that case, this 
	 * will return a row count of 1
	 */
	SELECT COUNT(*) INTO row_count
	FROM (
	    SELECT DISTINCT count_pins_for_circuit_id(pin.circuit_id)
	    FROM jumper_wire
	    JOIN connection ON (connection.jumper_wire_id = jumper_wire.id)
	    JOIN pin ON (pin.id = connection.pin_id)
	    WHERE jumper_wire.jumper_id = p_jumper_id
	) AS t;

	IF row_count != 1 THEN
		RETURN FALSE;
	END IF;


	/* How many circuits are connected by this jumper?
	 * Usually just 2 - the user interface doesn't support a jumper
	 * with 'mid-point' connections, although this function handles
	 * that possiblity.
	 */
	SELECT count(*) INTO circuit_count
	FROM jumper_wire
	JOIN connection ON (connection.jumper_wire_id = jumper_wire.id)
	JOIN pin ON (pin.id = connection.pin_id)
	WHERE jumper_wire.jumper_id = p_jumper_id
	GROUP BY pin.circuit_id;


	/* Counting the number of connections for each jumper wire,
	 * grouped by pin position should yield a count 
	 * matching the number of circuits connected. Here we return
	 * only rows not matching this criteria. A simple jumper should
	 * therefore return 0
	 */
	SELECT COUNT(*) INTO row_count
	FROM (
		SELECT 1
		    FROM jumper_wire
		    JOIN connection ON (connection.jumper_wire_id = jumper_wire.id)
		    JOIN pin ON (pin.id = connection.pin_id)
		    WHERE jumper_wire.jumper_id = p_jumper_id
		GROUP BY pin.position, jumper_wire.id
		HAVING count(*) != circuit_count
	) AS t;

	IF row_count != 0 THEN
		RETURN FALSE;
	END IF;

	RETURN TRUE;

END
$$ LANGUAGE plpgsql;



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





