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


CREATE OR REPLACE FUNCTION create_account(
	p_account_name TEXT
)
RETURNS INTEGER AS $$
DECLARE p_account_id INTEGER;
BEGIN

	INSERT INTO account(name)
	VALUES(p_account_name)
	RETURNING id INTO p_account_id;


	-- insert initial block types
	INSERT INTO block_type(account_id, name, colour_html_code, circuit_count, circuit_pin_count) VALUES
		(p_account_id, '237A',  E'\\xfffacd', 10, 2),
		(p_account_id, '237B',  E'\\xd6dddd', 10, 2),
		(p_account_id, 'EARTH', E'\\xffcccc', 10, 2),
		(p_account_id, 'ABS',   E'\\xd6dddd', 6,  3);

	-- insert initial jumper templates
	PERFORM create_jumper_template(p_account_id, 'Analogue Right', 'R',     ARRAY['blu','y']);
	PERFORM create_jumper_template(p_account_id, 'Analogue Left',  'L',     ARRAY['blu','red']);
	PERFORM create_jumper_template(p_account_id, 'Analogue Mono',  'M',     ARRAY['red','white']);
	PERFORM create_jumper_template(p_account_id, 'DC',             'DC',    ARRAY['green','yellow']);
	PERFORM create_jumper_template(p_account_id, 'AES/EBU',        'AES',   ARRAY['blue','white']);
	PERFORM create_jumper_template(p_account_id, 'Communications', 'COMMS', ARRAY['green','red']);
	PERFORM create_jumper_template(p_account_id, 'ABS',            'ABS',   ARRAY['black','red','green']);

	RETURN p_account_id;
END
$$ LANGUAGE plpgsql;


