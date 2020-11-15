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


CREATE OR REPLACE VIEW block_type_info AS
SELECT
	block_type.id,
	block_type.account_id,
	block_type.name,
	block_type.circuit_count,
	block_type.circuit_pin_count,
        CONCAT('#', ENCODE(block_type.colour_html_code, 'hex')) AS html_colour
FROM block_type;


