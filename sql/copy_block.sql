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


CREATE OR REPLACE FUNCTION al_log_activity(
	p_by_person_id INTEGER,
	p_to_frame_id INTEGER,
	p_function TEXT,
	p_note TEXT,
	p_to_block_id INTEGER,
	p_circuit_id INTEGER,
	p_jumper_id INTEGER
)
RETURNS VOID AS $$
DECLARE p_account_id INTEGER;
BEGIN

	/* Look up account_id */
	SELECT account_id
	INTO p_account_id
	FROM person
	WHERE id = p_by_person_id;

	/* Write log entry */
	INSERT INTO activity_log(
		by_person_id,
		account_id,
		frame_id,
		function,
		note,
		block_id_a,
		circuit_id_a,
		jumper_id
	) VALUES (
		p_by_person_id,
		p_account_id,
		p_to_frame_id,
		p_function,
		p_note,
		p_to_block_id,
		p_circuit_id,
		p_jumper_id
	);

END
$$ LANGUAGE plpgsql;




CREATE OR REPLACE FUNCTION copy_block(
	p_from_block_id INTEGER,
	p_to_block_id INTEGER
)
RETURNS INTEGER AS $$
BEGIN

	/* Validation */
	CASE
		WHEN block_is_free(p_from_block_id) THEN
			RAISE EXCEPTION 'Cannot copy block id % - it is not in use', p_from_block_id;
		WHEN NOT block_is_free(p_to_block_id) THEN
			RAISE EXCEPTION 'Cannot place block for id % - it is already in use', p_to_block_id;
		ELSE -- validation OK
	END CASE;


	/* Copy basic Block */
	UPDATE block SET
		name = template.name,
		block_type_id = template.block_type_id,
		colour_html_code = template.colour_html_code
	FROM block AS template
	WHERE template.id = p_from_block_id
	AND block.id = p_to_block_id;

	/* Create matching circuits */
	INSERT INTO circuit (
		block_id,
		position,
		designation,
		name,
		cable_reference,
		connection,
		note
	)
	SELECT
		p_to_block_id,
		position,
		designation,
		name,
		cable_reference,
		connection,
		note
	FROM circuit AS template
	WHERE template.block_id = p_from_block_id;


	/* Create matching pins */
	INSERT INTO pin (
		circuit_id,
		position,
		designation,
		name,
		wire_reference
	)
	SELECT 
		circuit.id,
		pin_template.position,
		pin_template.designation,
		pin_template.name,
		pin_template.wire_reference
	FROM circuit
	JOIN circuit AS circuit_template ON (
		circuit_template.block_id = p_from_block_id
		AND circuit_template.position = circuit.position
	)
	JOIN pin AS pin_template ON (
		pin_template.circuit_id = circuit_template.id
	)
	AND circuit.block_id = p_to_block_id;


	RETURN p_to_block_id;
END
$$ LANGUAGE plpgsql;



/* This can be called when a block has been copied or
 * placed to log all of the activity needed to create
 * it. Most operations are single-steps which are logged
 * individually. But for a block copy or template place,
 * the operations are done as bulk queries without recording
 * in the activity log. Calling this function afterwards
 * fills in the log
 */
CREATE OR REPLACE FUNCTION al_record_block_copy(
	p_from_block_id INTEGER,
	p_to_block_id INTEGER,
	p_by_person_id INTEGER,
	p_function TEXT
)
RETURNS VOID AS $$
DECLARE p_to_frame_id INTEGER;
DECLARE p_from_frame_name TEXT;
DECLARE p_to_frame_name TEXT;
DECLARE p_from_block_designation TEXT;
DECLARE p_to_block_designation TEXT;
BEGIN

	/* Get info about the block we've copied */
	SELECT frame_name, full_designation
	INTO p_from_frame_name, p_from_block_designation
	FROM block_info
	WHERE id = p_from_block_id;

	/* Get info about the block we've placed */
	SELECT frame_id, frame_name, full_designation
	INTO p_to_frame_id, p_to_frame_name, p_to_block_designation
	FROM block_info
	WHERE id = p_to_block_id;

	/* Log start of activity */
	PERFORM al_log_activity(
		p_by_person_id,
		p_to_frame_id,
		p_function,
		CONCAT(
			'--- BEGIN COPY [',
			p_from_frame_name,
			'].',
			p_from_block_designation,
			' to [',
			p_to_frame_name,
			'].',
			p_to_block_designation,
			' ---'
		),
		p_to_block_id,
		NULL,
		NULL
	);

	/* Log block changes */
	PERFORM al_log_activity(
		p_by_person_id,
		p_to_frame_id,
		p_function,
		CONCAT(
			'Placed ',
			COALESCE(block_type.name, 'unspecified'),
			' block at ', 
			p_to_block_designation
		),
		p_to_block_id,
		NULL,
		NULL
	)
	FROM block
	LEFT JOIN block_type ON (block_type.id = block.block_type_id)
	WHERE block.id = p_to_block_id;

	PERFORM al_log_activity(
		p_by_person_id,
		p_to_frame_id,
		p_function,
		CONCAT(
			'block ',
			p_to_block_designation,
			' renamed "',
			block.name,
			'" (was "")' 
		),
		p_to_block_id,
		NULL,
		NULL
	)
	FROM block
	WHERE block.id = p_to_block_id
	AND block.name IS NOT NULL
	AND block.name != '';

	PERFORM al_log_activity(
		p_by_person_id,
		p_to_frame_id,
		p_function,
		CONCAT(
			'block ',
			p_to_block_designation,
			' colour set to #',
			ENCODE(block.colour_html_code, 'hex'),
			' (was default)' 
		),
		p_to_block_id,
		NULL,
		NULL
	)
	FROM block
	WHERE block.id = p_to_block_id
	AND block.colour_html_code IS NOT NULL;


	/* Log circuit changes */
	PERFORM al_log_activity(
		p_by_person_id,
		p_to_frame_id,
		p_function,
		CONCAT(
			'circuit ',
			CONCAT(vertical.designation, block.designation, '.', circuit.designation),
			' name changed to  "',
			circuit.name,
			'" (was "")' 
		),
		p_to_block_id,
		circuit.id,
		NULL
	)
	FROM block
	JOIN circuit ON (circuit.block_id = block.id)
	JOIN vertical ON (vertical.id = block.vertical_id)
	WHERE block.id = p_to_block_id
	AND circuit.name IS NOT NULL
	AND circuit.name != ''
	ORDER BY circuit.position ASC;

	PERFORM al_log_activity(
		p_by_person_id,
		p_to_frame_id,
		p_function,
		CONCAT(
			'circuit ',
			CONCAT(vertical.designation, block.designation, '.', circuit.designation),
			' cable reference changed to  "',
			circuit.cable_reference,
			'" (was "")' 
		),
		p_to_block_id,
		circuit.id,
		NULL
	)
	FROM block
	JOIN circuit ON (circuit.block_id = block.id)
	JOIN vertical ON (vertical.id = block.vertical_id)
	WHERE block.id = p_to_block_id
	AND circuit.cable_reference IS NOT NULL
	AND circuit.cable_reference != ''
	ORDER BY circuit.position ASC;

	PERFORM al_log_activity(
		p_by_person_id,
		p_to_frame_id,
		p_function,
		CONCAT(
			'circuit ',
			CONCAT(vertical.designation, block.designation, '.', circuit.designation),
			' connection changed to  "',
			circuit.connection,
			'" (was "")' 
		),
		p_to_block_id,
		circuit.id,
		NULL
	)
	FROM block
	JOIN circuit ON (circuit.block_id = block.id)
	JOIN vertical ON (vertical.id = block.vertical_id)
	WHERE block.id = p_to_block_id
	AND circuit.connection IS NOT NULL
	AND circuit.connection != ''
	ORDER BY circuit.position ASC;

	PERFORM al_log_activity(
		p_by_person_id,
		p_to_frame_id,
		p_function,
		CONCAT(
			'circuit ',
			CONCAT(vertical.designation, block.designation, '.', circuit.designation),
			' note changed to  "',
			circuit.note,
			'" (was "")' 
		),
		p_to_block_id,
		circuit.id,
		NULL
	)
	FROM block
	JOIN circuit ON (circuit.block_id = block.id)
	JOIN vertical ON (vertical.id = block.vertical_id)
	WHERE block.id = p_to_block_id
	AND circuit.note IS NOT NULL
	AND circuit.note != ''
	ORDER BY circuit.position ASC;


	/* Log pin changes */
	PERFORM al_log_activity(
		p_by_person_id,
		p_to_frame_id,
		p_function,
		CONCAT(
			'pin ',
			CONCAT(vertical.designation, block.designation, '.', circuit.designation, pin.designation),
			' name changed to  "',
			pin.name,
			'" (was "")' 
		),
		p_to_block_id,
		circuit.id,
		NULL
	)
	FROM block
	JOIN circuit ON (circuit.block_id = block.id)
	JOIN pin ON (pin.circuit_id = circuit.id)
	JOIN vertical ON (vertical.id = block.vertical_id)
	WHERE block.id = p_to_block_id
	AND pin.name IS NOT NULL
	AND pin.name != ''
	ORDER BY circuit.position ASC, pin.position ASC;

	PERFORM al_log_activity(
		p_by_person_id,
		p_to_frame_id,
		p_function,
		CONCAT(
			'pin ',
			CONCAT(vertical.designation, block.designation, '.', circuit.designation, pin.designation),
			' wire_reference changed to  "',
			pin.wire_reference,
			'" (was "")' 
		),
		p_to_block_id,
		circuit.id,
		NULL
	)
	FROM block
	JOIN circuit ON (circuit.block_id = block.id)
	JOIN pin ON (pin.circuit_id = circuit.id)
	JOIN vertical ON (vertical.id = block.vertical_id)
	WHERE block.id = p_to_block_id
	AND pin.wire_reference IS NOT NULL
	AND pin.wire_reference != ''
	ORDER BY circuit.position ASC, pin.position ASC;


	/* Log end of activity */
	PERFORM al_log_activity(
		p_by_person_id,
		p_to_frame_id,
		p_function,
		CONCAT(
			'--- END COPY [',
			p_from_frame_name,
			'].',
			p_from_block_designation,
			' to [',
			p_to_frame_name,
			'].',
			p_to_block_designation,
			' ---'
		),
		p_to_block_id,
		NULL,
		NULL
	);

END
$$ LANGUAGE plpgsql;




