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


require([
	'backbone',
        'jquery',
	'jqueryui'
], function (
) {
        'use strict';

	$("#block_menu").menu();
	$(".block .menu_button a").on("click", show_block_menu);



	function show_block_menu(e) {
		console.log("show block menu");
		$("#block_menu").menu().show().position({
			my: "left top",
			at: "left bottom",
			of: this
		});

		/* Clicking outside the menu closes it */
		$(document).on("click", function() {
			$("#block_menu").menu().hide();
		});

		/* Stop this event propogating down to the document */
		return false;
	};

	

	console.log("loaded frame.js");
});



