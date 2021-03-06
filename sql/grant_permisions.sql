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



/*--------------------------------------------------------------------------*/
/* PERMISSIONS */
/*--------------------------------------------------------------------------*/

GRANT USAGE ON SCHEMA kris TO kkdancer;
GRANT SELECT, INSERT, DELETE, UPDATE ON ALL TABLES IN SCHEMA public TO kkdancer;
GRANT SELECT, INSERT, DELETE, UPDATE ON ALL TABLES IN SCHEMA kris TO kkdancer;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO kkdancer;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA kris TO kkdancer;


