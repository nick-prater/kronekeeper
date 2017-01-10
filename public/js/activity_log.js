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


require([
	'datatables.net'
], function (
) {
        'use strict';

	/* Table is hidden until it is processed by Data */
	$("#activity_log_table").on("draw.dt", function () {
		console.log("table redrawn");
		$("#activity_log_table").off("draw.dt");
		$("#activity_log_table").show();
	});

	$("#activity_log_table").DataTable({
		serverSide: true,
		searching: false, /* Not yet implemented in our perl api */
		ordering: false,  /* Not yet implemented in our perl api */
		ajax: {
			url: "activity_log/query",
			type: "POST",
			data: function(d) {
				return JSON.stringify(d);
			}
		},
		columns: [
			{ data: 'log_timestamp'  },
			{ data: 'by_person_name' },
			{ data: 'note'           }
		]
	});
});
