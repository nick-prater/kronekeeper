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



CREATE OR REPLACE FUNCTION copy_block(
	p_from_block_id INTEGER,
	p_to_block_id INTEGER
)
RETURNS INTEGER AS $$
BEGIN

	/* Validation */
	CASE
		WHEN block_is_free(p_from_block_id) THEN
			RAISE EXCEPTION 'Cannot copy block id % - it is not in use', p_fromblock_id;
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


