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


define([
        'jquery'
], function (
) {
        'use strict';

	function get_parameters() {

		var rv = {
			show_complete: $("#checkbox_show_complete").prop("checked"),
			show_incomplete: $("#checkbox_show_incomplete").prop("checked"),
			show_jumpers: $("#checkbox_show_jumpering").prop("checked"),
			show_blocks: $("#checkbox_show_blocks").prop("checked"),
			show_other: $("#checkbox_show_other").prop("checked")
		};
	
		/* No user_id parameter means show entries for all users */	
		if($("#select_user").val()) {
			rv.user_id = $("#select_user").val();
		}

		return rv;
	}


	console.log("loaded filter.js");

	return {
		get_parameters: get_parameters
	};
});


