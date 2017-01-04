/*
This file is part of Kronekeeper, a web based application for 
recording and managing wiring frame records.

Copyright (C) 2017 NP Broadcast Limited

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



/* This function is unusual in that it will udapte the activity_log
 * table using the supplied person_id. In most other cases, we
 * currently handle activity_log updates outside the database
 * 
 * It returns the block copies we created in the same format as block_info()
 */
CREATE OR REPLACE FUNCTION place_template(
	p_block_id INTEGER,
	p_template_id INTEGER,
	p_person_id INTEGER
)
RETURNS SETOF block_info AS $$
DECLARE
	p_frame_id INTEGER;
	p_vertical_offset INTEGER;
	p_block_offset INTEGER;
	p_template_name TEXT;
	p_destination_designation TEXT;
BEGIN


	/* Get position offset within frame for destination block */
	SELECT
		vertical.frame_id,
		CONCAT(vertical.designation, block.designation),
		(vertical.position - 1),
		(block.position - 1)
	INTO
		p_frame_id,
		p_destination_designation,
		p_vertical_offset,
		p_block_offset
	FROM block
	JOIN vertical ON (
		vertical.id = block.vertical_id
	)
	WHERE block.id = p_block_id;
	
	/* Get name of the template */
	SELECT name
	INTO p_template_name
	FROM frame
	WHERE id = p_template_id;


	/* Record start of operation */
	PERFORM al_log_activity(
		p_person_id,
		p_frame_id,
		'place_template',
		CONCAT('--- BEGIN PLACING TEMPLATE "', p_template_name, '" at ', p_destination_designation, ' ---'),
		p_block_id,
		NULL
	);


	/* Copy template blocks, updating activity log as we go */
	PERFORM
		copy_block(s.id, d.id),
		al_record_block_copy(s.id, d.id, p_person_id, 'place_template')
	FROM
		block AS s,
		vertical AS s_vertical,
		block AS d,
		vertical AS d_vertical
	WHERE s_vertical.frame_id = p_template_id
	AND   d_vertical.frame_id = p_frame_id
	AND   s_vertical.id = s.vertical_id
	AND   d_vertical.id = d.vertical_id
	AND   d_vertical.position = s_vertical.position + p_vertical_offset
	AND   d.position = s.position + p_block_offset
	AND NOT block_is_free(s.id)  /* Don't copy empty blocks */
	ORDER BY s_vertical.position, s.position;


	/* Copy jumpers */
	PERFORM copy_template_jumpers(
		p_template_id,
		p_frame_id,
		p_vertical_offset,
		p_block_offset,
		p_person_id
	);


	/* Record end of operation */
	PERFORM al_log_activity(
		p_person_id,
		p_frame_id,
		'place_template',
		CONCAT('--- END PLACING TEMPLATE "', p_template_name, '" at ', p_destination_designation, ' ---'),
		p_block_id,
		NULL
	);


	/* Return the blocks we copied */
	RETURN QUERY
	SELECT
		d.id,
		d.name,
		d.position,
		d.designation,
		block_is_free(d.id) AS is_free,
		CONCAT(d_vertical.designation, d.designation) AS full_designation,
		d_frame.id AS frame_id,
		d_frame.name AS frame_name,

		block_type.id AS block_type_id,
		block_type.name AS block_type_name,
		CONCAT('#', ENCODE(
			COALESCE(d.colour_html_code, block_type.colour_html_code),
			'hex'
		)) AS html_colour,
		CONCAT('#', ENCODE(block_type.colour_html_code, 'hex')) AS default_html_colour,
		d_vertical.id AS vertical_id,
		ENCODE(d.colour_html_code,'hex') AS block_html_colour
	FROM frame as s_frame
	JOIN vertical AS s_vertical ON (
		s_vertical.frame_id = s_frame.id
	)
	JOIN block AS s ON (
		s.vertical_id = s_vertical.id
		AND NOT block_is_free(s.id)  /* Don't return empty blocks */
	)
	JOIN vertical AS d_vertical ON (
		d_vertical.frame_id = p_frame_id
		AND d_vertical.position = s_vertical.position + p_vertical_offset
	)
	JOIN block AS d ON (
		d.vertical_id = d_vertical.id
		AND d.position = s.position + p_block_offset
	)
	JOIN frame AS d_frame ON (
		d_frame.id = d_vertical.frame_id
	)
	LEFT JOIN block_type ON (block_type.id = d.block_type_id)
	WHERE s_frame.id = p_template_id
	ORDER BY s_vertical.position, s.position;

END
$$ LANGUAGE plpgsql;




CREATE OR REPLACE FUNCTION copy_template_jumpers(
	p_template_id INTEGER,
	p_frame_id INTEGER,
	p_vertical_offset INTEGER,
	p_block_offset INTEGER,
	p_person_id INTEGER
)
RETURNS INTEGER AS $$
DECLARE
	r_jumper RECORD;
	r_wire RECORD;
	r_connection RECORD;
	v_jumper_id INTEGER;
	v_jumper_wire_id INTEGER;
BEGIN

	/* Copy jumpers from template */
	FOR r_jumper IN
		SELECT DISTINCT
			jumper_wire.jumper_id,
			is_simple_jumper(jumper_wire.jumper_id)
		FROM vertical
		JOIN block ON (block.vertical_id = vertical.id)
		JOIN circuit ON (circuit.block_id = block.id)
		JOIN pin ON (pin.circuit_id = circuit.id)
		JOIN connection ON (connection.pin_id = pin.id)
		JOIN jumper_wire ON (jumper_wire.id = connection.jumper_wire_id)
		WHERE vertical.frame_id = p_template_id
	LOOP

		/* Insert new empty jumper
		 * corresponding to each on the template form
		 */
		INSERT INTO jumper(id)
		VALUES(DEFAULT)
		RETURNING id INTO v_jumper_id;

		FOR r_wire IN
			SELECT DISTINCT
				jumper_wire.id,
				jumper_wire.colour_id
			FROM jumper_wire
			WHERE jumper_wire.jumper_id = r_jumper.jumper_id
		LOOP

			/* Insert new jumper wire
			 * corresponding to each on the template jumper
			 */
			INSERT INTO jumper_wire(jumper_id, colour_id)
			VALUES(v_jumper_id, r_wire.colour_id)
			RETURNING id INTO v_jumper_wire_id;

			FOR r_connection IN
				SELECT DISTINCT
					connection.id,
					d_pin.id AS pin_id
				FROM connection
				JOIN pin ON (pin.id = connection.pin_id)
				JOIN circuit ON (circuit.id = pin.circuit_id)
				JOIN block ON (block.id = circuit.block_id)
				JOIN vertical ON (vertical.id = block.vertical_id)
				JOIN vertical AS d_vertical ON (
					d_vertical.frame_id = p_frame_id
					AND d_vertical.position = vertical.position + p_vertical_offset
				)
				JOIN block AS d_block ON (
					d_block.vertical_id = d_vertical.id
					AND d_block.position = block.position + p_block_offset
				)
				JOIN circuit AS d_circuit ON (
					d_circuit.block_id = d_block.id
					AND d_circuit.position = circuit.position
				)
				JOIN pin AS d_pin ON (
					d_pin.circuit_id = d_circuit.id
					AND d_pin.position = pin.position
				)
				WHERE connection.jumper_wire_id = r_wire.id
			LOOP

				/* Insert new connection */
				INSERT INTO connection(jumper_wire_id, pin_id)
				VALUES(v_jumper_wire_id, r_connection.pin_id);

			END LOOP;

		END LOOP;

		/* Document new jumper */
		IF r_jumper.is_simple_jumper THEN
			PERFORM document_simple_jumper(v_jumper_id, p_person_id);
		ELSE
			PERFORM document_custom_jumper(v_jumper_id, p_person_id);
		END IF;

	END LOOP;

	RETURN 1;
END
$$ LANGUAGE plpgsql;




CREATE OR REPLACE FUNCTION document_simple_jumper(
	p_jumper_id INTEGER,
	p_person_id INTEGER
)
RETURNS INTEGER AS $$
DECLARE
	a_circuits TEXT;
	a_wire_colours TEXT;
	a_note TEXT;
	a_frame_id INTEGER;
BEGIN

	/* Build list of circuits */
	SELECT array_to_string(full_circuit_designations, '->'), frame_id
	INTO a_circuits, a_frame_id
	FROM jumper_wire_connections
	WHERE jumper_id = p_jumper_id
	LIMIT 1;

	/* Build list of wire colours */
	SELECT ARRAY_TO_STRING(
		ARRAY(SELECT colour_name FROM jumper_wire_connections WHERE jumper_id = p_jumper_id),
		'/'
	)
	INTO a_wire_colours;

	/* Build note for activity log */
	a_note := CONCAT(
		'standard jumper added ',
		a_circuits,
		' [',
		a_wire_colours,
		']'
	);	

	/* Record note */
	PERFORM al_log_activity(
		p_person_id,
		a_frame_id,
		'place_template',
		a_note,
		NULL,
		NULL
	);

	RETURN 1;
END
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION document_custom_jumper(
	p_jumper_id INTEGER,
	p_person_id INTEGER
)
RETURNS INTEGER AS $$
DECLARE
	a_note TEXT;
	a_frame_id INTEGER;
BEGIN

	/* Get frame_id */
	SELECT frame_id
	INTO a_frame_id
	FROM jumper_wire_connections
	WHERE jumper_id = p_jumper_id
	LIMIT 1;

	/* Build note for activity log */
	a_note := CONCAT(
		'custom jumper added ',
		ARRAY_TO_STRING(
			ARRAY(
				SELECT CONCAT(
					ARRAY_TO_STRING(full_pin_designations, '->'),
					' [',
					colour_name,
					']'
				)
				FROM jumper_wire_connections WHERE jumper_id = p_jumper_id
			),
			'; '
		)
	);

	/* Record note */
	PERFORM al_log_activity(
		p_person_id,
		a_frame_id,
		'place_template',
		a_note,
		NULL,
		NULL
	);

	RETURN 1;
END
$$ LANGUAGE plpgsql;




