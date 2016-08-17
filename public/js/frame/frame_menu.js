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


	/* Initialise the menus and associated events */
	$("#frame_menu").menu({
		select: handle_menu_selection
	});
	$(".frame a.frame_menu_button").on("click", show_menu);

	/* Initialise dialogs */
	var cancel_button = {
		text: "Cancel",
		icon: "ui-icon-close",
		click: function(e) {
			$(this).dialog("close");
		}
	};
	var reverse_button = {
		text: "Reverse",
		icon: "ui-icon-shuffle",
		click: reverse_vertical_designations
	};

	$("#dialog_confirm_reverse_vertical_designations").dialog({
		autoOpen: false,
		modal: true,
		buttons: [cancel_button, reverse_button]
	});

	$("#dialog_reversing_designations").dialog({
		dialogClass: "no-close",
		autoOpen: false,
		modal: true,
		buttons: [],
		closeOnEscape: false
	});


	function show_menu(e) {

		e.stopPropagation();

		$("#frame_menu").menu("collapseAll", null, true);
		$("#frame_menu").menu().show().position({
			my: "left top",
			at: "left bottom",
			of: this,
			collision: "fit flip"
		});

		/* Clicking outside the menu closes it */
		$(document).on("click", function() {
			$("#frame_menu").menu().hide();
		});
	};


	function handle_menu_selection(e, jq_element) {

		console.log(e.currentTarget.dataset.action, "action clicked");

		switch(e.currentTarget.dataset.action) {

			case "reverse_vertical_designations" :
				$("#block_menu").menu().hide();
				$("#dialog_confirm_reverse_vertical_designations").dialog("open");
				break;
		};

	}


	function reverse_vertical_designations () {

		var url = "/api/frame/reverse_designations";

		$("#dialog_confirm_reverse_vertical_designations").dialog("close");
		$("#dialog_reversing_designations").dialog("open");

		var data = {
			frame_id: window.frame_id,
			vertical: true
		};

	console.log(data);

		$.ajax({
			url: url,
			type: "POST",
			dataType: "json",
			data: JSON.stringify(data),
			contentType: 'application/json; charset=utf-8',
			success: function(json) {
				console.log("reversed vertical designations OK");
				window.location.reload();
			},
			error: function(xhr, status) {
				var error_code = xhr.status + " " + xhr.statusText;
				$("#dialog_reversing_designations").dialog("close");
				alert("ERROR reversing vertical designations: " + error_code);
			}
		});
	}



	console.log("loaded frame_menu.js");
});



