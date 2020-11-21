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


require([
	'backbone',
        'jquery',
	'jqueryui'
], function (
) {
        'use strict';

	var properties = {
		selected_menu_option: null,
		trigger_element: null
	};

	/* Initialise the menus and associated events */
	$("#vertical_menu").menu({
		select: handle_menu_selection
	});
	$(".frame a.vertical_menu_button").on("click", show_menu);


	/* Initialise dialogs */
	var cancel_button = {
		text: "Cancel",
		icon: "ui-icon-close",
		click: function(e) {
			$(this).dialog("close");
		}
	};
	var rename_button = {
		text: "Rename",
		icon: "ui-icon-check",
		click: rename_vertical
	};

	$("#dialog_rename_vertical").dialog({
		autoOpen: false,
		modal: true,
		buttons: [cancel_button, rename_button]
	});

	$("#dialog_updating_frame_message").dialog({
		dialogClass: "no-close",
		autoOpen: false,
		modal: true,
		buttons: [],
		closeOnEscape: false
	});

	function show_menu(e) {

		e.stopPropagation();
		properties.trigger_element = this;

		$("#vertical_menu").menu("collapseAll", null, true);
		$("#vertical_menu").menu().show().position({
			my: "left top",
			at: "left bottom",
			of: this,
			collision: "fit flip"
		});

		/* Clicking outside the menu closes it */
		$(document).on("click", function() {
			$("#vertical_menu").menu().hide();
		});
	}


	function handle_menu_selection(e, jq_element) {

		console.log(e.currentTarget.dataset.action, "action clicked");
		properties.selected_menu_option = e.currentTarget.dataset.action;

		switch(e.currentTarget.dataset.action) {
			case "rename_vertical" :
				let current_name = (
					$(properties.trigger_element)
					.closest("div.container")
					.find("div.name")
					.text()
					.trim()
				);
				$("#vertical_name").val(current_name);
				$("#rename_vertical_duplicate_error").hide();
				$("#block_menu").menu().hide();
				$("#dialog_rename_vertical").dialog("open");
				break;
		}
	}


	function rename_vertical() {

		var url = "/api/frame/rename_vertical";
		let vertical_id = (
			$(properties.trigger_element)
			.closest("th")
			.data("vertical_id")
		);
		var data = {
			vertical_id: vertical_id,
			designation: $("#vertical_name").val()
		};

		$("#dialog_rename_vertical").dialog("close");
		$("#dialog_updating_frame_message").dialog("open");

		$.ajax({
			url: url,
			type: "POST",
			dataType: "json",
			data: JSON.stringify(data),
			contentType: 'application/json; charset=utf-8',
			success: function(json) {
				console.log("renamed designations OK");
				window.location.reload();
			},
			error: function(xhr, status) {
				if(xhr.status == 409) {
					$("#dialog_updating_frame_message").dialog("close");
					$("#rename_vertical_duplicate_error").show();
					$("#dialog_rename_vertical").dialog("open");
				}
				else {
					var error_code = xhr.status + " " + xhr.statusText;
					$("#dialog_updating_frame_message").dialog("close");
					alert("ERROR renaming designations: " + error_code);
				}
			}
		});
	}

	console.log("loaded vertical_menu.js");
});



