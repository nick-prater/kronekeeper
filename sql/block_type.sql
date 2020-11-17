/*
This file is part of Kronekeeper, a web based application for 
recording and managing wiring frame records.

Copyright (C) 2016-2020 NP Broadcast Limited

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


/* Returns true if the specified block type is in use, or false otherwise.
 * Can be used to determine if a block type can be deleted.
 */
CREATE OR REPLACE FUNCTION block_type_is_used(
	p_block_type_id INTEGER
)
RETURNS BOOLEAN AS $$
BEGIN
	IF EXISTS (SELECT 1 FROM block WHERE block.block_type_id = p_block_type_id) THEN
		/* block_type is in use */
		RETURN TRUE;
	END IF;

	/* Otherwise it must be unused */
	RETURN FALSE;
END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION process_in_use_block_type_dimension_change()
RETURNS TRIGGER AS $$
BEGIN
	IF block_type_is_used(OLD.id) AND (
		NEW.circuit_count != OLD.circuit_count OR
		NEW.circuit_pin_count != OLD.circuit_pin_count
	)
	THEN RAISE EXCEPTION 'Cannot update block_type circuit_count or circuit_pin_count when block_type is in use';
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS catch_in_use_block_type_dimension_change ON block_type;
CREATE TRIGGER catch_in_use_block_type_dimension_change
BEFORE UPDATE OF circuit_count, circuit_pin_count
ON block_type
FOR EACH ROW
EXECUTE PROCEDURE process_in_use_block_type_dimension_change();



CREATE OR REPLACE VIEW block_type_info AS
SELECT
	block_type.id,
	block_type.account_id,
	block_type.name,
	block_type.circuit_count,
	block_type.circuit_pin_count,
        CONCAT('#', ENCODE(block_type.colour_html_code, 'hex')) AS html_colour,
	block_type_is_used(block_type.id) AS is_used
FROM block_type;


