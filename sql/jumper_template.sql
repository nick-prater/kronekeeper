/*
This file is part of Kronekeeper, a web based application for 
recording and managing wiring frame records.

Copyright (C) 2020 NP Broadcast Limited

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


/* Jumper templates can be deleted without affecting wiring records,
 * as they are referenced only at the time of inserting jumpers, or
 * importing KRIS records. Once applied, wiring jumpers stand
 * alone without any reference to the original template (and
 * can be inserted manually without reference to a template).
 *
 * This function removes the specified jumper template from any
 * KRIS wiretype association, deletes the template wires, then
 * deletes the overall jumper template record.
 * 
 * Returns TRUE if deletion of the jumper_template record is successful.
 */
CREATE OR REPLACE FUNCTION delete_jumper_template(
	p_jumper_template_id INTEGER
)
RETURNS BOOLEAN AS $$
BEGIN

	DELETE FROM kris.jumper_type
	WHERE jumper_template_id = p_jumper_template_id;

	DELETE FROM jumper_template_wire
	WHERE jumper_template_id = p_jumper_template_id;

	DELETE FROM jumper_template
	WHERE id = p_jumper_template_id;

	RETURN FOUND;

END
$$ LANGUAGE plpgsql;

