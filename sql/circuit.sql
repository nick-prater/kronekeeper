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

CREATE OR REPLACE VIEW circuit_info AS
SELECT
	circuit.id,
	circuit.name,
	circuit.cable_reference,
	circuit.note,
	block.id AS block_id,
	block.name AS block_name,
	vertical.designation AS vertical_designation,
	block.designation AS block_designation,
	circuit.designation AS circuit_designation,
	CONCAT(vertical.designation, block.designation, '.', circuit.designation) AS full_designation,
	frame.id AS frame_id,
	frame.name AS frame_name,
	circuit.connection,
	count_pins_for_circuit_id(circuit.id) AS pin_count
FROM circuit
JOIN block ON (block.id = circuit.block_id)
JOIN vertical ON (vertical.id = block.vertical_id)
JOIN frame ON (frame.id = vertical.frame_id);


CREATE OR REPLACE FUNCTION frame_id_for_circuit_id(
	p_circuit_id INTEGER
)
RETURNS INTEGER AS $$
BEGIN

	RETURN vertical.frame_id
	FROM circuit
	JOIN block ON (block.id = circuit.block_id)
	JOIN vertical ON (vertical.id = block.vertical_id)
	WHERE circuit.id = p_circuit_id;
END
$$ LANGUAGE plpgsql;


/* This function returns a table with a single row, containing a nested json array 
 * structure representing the jumpers for the given circuit, along with the
 * wires making up those jumpers...
 */
CREATE OR REPLACE FUNCTION json_circuit_jumpers(
	p_circuit_id INTEGER
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
		WHERE jumper_circuits.a_circuit_id = p_circuit_id
		ORDER BY jumper_circuits.jumper_id
	) AS u;
END
$$ LANGUAGE plpgsql;



/* Given a circuit id, return a list of all the circuit
 * ids linked with it by jumpers. The returned list
 * includes the given circuit_id. All jumpers are followed
 * even as they are linked through other circuits, giving
 * a complete picture of the circuit net.
 */
CREATE OR REPLACE FUNCTION connected_circuit_ids(
	p_circuit_id INTEGER
)
RETURNS SETOF INTEGER AS $$
DECLARE p_iteration_count INTEGER;
DECLARE p_max_iterations INTEGER;
DECLARE p_row_count INTEGER;
BEGIN
	/* We'll build a list of linked circuits in this temporary table */
	CREATE TEMPORARY TABLE t_linked_circuits (
		id INTEGER PRIMARY KEY
	)
	ON COMMIT DROP;

	/* Seed with the circuit we're interested in */
	INSERT INTO t_linked_circuits(id) VALUES (p_circuit_id);

	/* Iterate looking for other connected circuits */
	p_max_iterations := 100;
	LOOP
		/* Runaway protection */
		p_iteration_count := p_iteration_count + 1;
		IF p_iteration_count > p_max_iterations THEN
			RAISE EXCEPTION 'Failed to resolve all circuits linked to % after % iterations',
				p_circuit_id,
				p_max_iterations;
		END IF;

		/* Look for circuits jumpered to those already in our temporary table */
		INSERT INTO t_linked_circuits(id)
		SELECT DISTINCT 
			pin2.circuit_id
		FROM jumper_wire
		JOIN connection AS connection1 ON (connection1.jumper_wire_id = jumper_wire.id)
		JOIN pin AS pin1 ON (pin1.id = connection1.pin_id)
		JOIN connection AS connection2 ON (
			connection2.jumper_wire_id = connection1.jumper_wire_id
			AND connection2.id != connection1.id
		)
		JOIN pin AS pin2 ON (pin2.id = connection2.pin_id)
		WHERE pin1.circuit_id IN (
			SELECT id FROM t_linked_circuits
		)
		AND NOT EXISTS (
			SELECT 1 FROM t_linked_circuits AS u
			WHERE pin2.circuit_id = u.id
		);
		
		GET DIAGNOSTICS p_row_count = ROW_COUNT;
		EXIT WHEN p_row_count = 0;	
	END LOOP;

	RETURN QUERY
	SELECT id FROM t_linked_circuits;

	/* Must clean up temporary table */
	DROP TABLE t_linked_circuits;

	RETURN;
END
$$ LANGUAGE plpgsql;



/* Renames a circuit and all connected circuits */
CREATE OR REPLACE FUNCTION update_circuit_name_cascade(
	p_circuit_id INTEGER,
	p_name TEXT
)
RETURNS VOID AS $$
BEGIN
	UPDATE circuit
	SET name = p_name
	WHERE circuit.id IN (
		SELECT connected_circuit_ids FROM connected_circuit_ids(p_circuit_id)
	);
END
$$ LANGUAGE plpgsql;






