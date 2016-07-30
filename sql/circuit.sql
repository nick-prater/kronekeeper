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



