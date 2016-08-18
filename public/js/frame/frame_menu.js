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

	var properties = {
		selected_menu_option: null
	};

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
		click: reverse_designations
	};

	$("#dialog_confirm_reverse_vertical_designations").dialog({
		autoOpen: false,
		modal: true,
		buttons: [cancel_button, reverse_button]
	});

	$("#dialog_confirm_reverse_block_designations").dialog({
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

	$("#dialog_cannot_reverse_block_designations").dialog({
		autoOpen: false,
		modal: true,
		buttons: [cancel_button],
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
	}


	function handle_menu_selection(e, jq_element) {

		console.log(e.currentTarget.dataset.action, "action clicked");
		properties.selected_menu_option = e.currentTarget.dataset.action;

		switch(e.currentTarget.dataset.action) {

			case "show_activity_log" : 
				window.location.href = "/activity_log/" + window.frame_id;
				break;

			case "reverse_vertical_designations" :
				$("#block_menu").menu().hide();
				$("#dialog_confirm_reverse_vertical_designations").dialog("open");
				break;

			case "reverse_block_designations" :
				$("#block_menu").menu().hide();

				/* Can only automatically reverse block designations if there
				 * are no differences in the size of each vertical. Differences
				 * are apparent if there are blocks in the frame marked unavailable.
				 */
				if($("td.block.unavailable").length == 0) {
					$("#dialog_confirm_reverse_block_designations").dialog("open");
				}
				else {
					$("#dialog_cannot_reverse_block_designations").dialog("open");
				}
				break;
		}

	}


	function reverse_designations() {

		var url = "/api/frame/reverse_designations";
		var data = {
			frame_id: window.frame_id
		};

		/* Set request data according to selected menu option */
		switch(properties.selected_menu_option) {
			case "reverse_vertical_designations" :
				data.vertical = true;
				break;
			case "reverse_block_designations" :
				data.block = true;
				break;
		}

		$("#dialog_confirm_reverse_vertical_designations").dialog("close");
		$("#dialog_confirm_reverse_block_designations").dialog("close");
		$("#dialog_reversing_designations").dialog("open");

		$.ajax({
			url: url,
			type: "POST",
			dataType: "json",
			data: JSON.stringify(data),
			contentType: 'application/json; charset=utf-8',
			success: function(json) {
				console.log("reversed designations OK");
				window.location.reload();
			},
			error: function(xhr, status) {
				var error_code = xhr.status + " " + xhr.statusText;
				$("#dialog_reversing_designations").dialog("close");
				alert("ERROR reversing designations: " + error_code);
			}
		});
	}



	console.log("loaded frame_menu.js");
});



