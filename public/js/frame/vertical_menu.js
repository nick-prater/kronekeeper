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
	'frame/remove_vertical',
	'backbone',
        'jquery',
	'jqueryui'
], function (
	remove_vertical
) {
        'use strict';

	var properties = {
		selected_menu_option: null,
		trigger_element: null,
		vertical_id: null
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
	var insert_button = {
		text: "Insert",
		icon: "ui-icon-check",
		click: insert_vertical
	};

	$("#dialog_rename_vertical").dialog({
		autoOpen: false,
		modal: true,
		buttons: [cancel_button, rename_button]
	});

	$("#dialog_insert_vertical").dialog({
		autoOpen: false,
		modal: true,
		buttons: [cancel_button, insert_button]
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
		properties.vertical_id = (
			$(this)
			.closest("th")
			.data("vertical_id")
		);

		$("ul.context_menu").not(this).menu().hide();
		$("#vertical_menu").menu("collapseAll", null, true);
		$("#vertical_menu").menu().show().position({
			my: "left top",
			at: "left bottom",
			of: this,
			collision: "fit flip"
		});

		/* Clicking outside the menu closes it */
		$(document).one("click", function() {
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
				$("#dialog_rename_vertical").dialog("open");
				break;

			case "remove_vertical" :
				remove_vertical.begin({
					vertical_id: properties.vertical_id,
					success: function () {
						remove_vertical.remove_from_display(properties.vertical_id)
					}
				});
				break;

			case "insert_vertical_left" :
			case "insert_vertical_right" :
				$("#dialog_insert_vertical").dialog("open");
				break;
		}
	}


	function rename_vertical() {

		var url = "/api/frame/rename_vertical";
		var data = {
			vertical_id: properties.vertical_id,
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


	function insert_vertical() {

		let url = "/api/frame/insert_vertical";
		let position = (
			$(properties.trigger_element)
			.closest("th")
			.data("position")
		);

		if(properties.selected_menu_option == 'insert_vertical_right') {
			position ++;
		};

		var data = {
			frame_id: window.frame_info.id,
			position: position
		};

		$("#dialog_insert_vertical").dialog("close");
		$("#dialog_updating_frame_message").dialog("open");

		$.ajax({
			url: url,
			type: "POST",
			dataType: "json",
			data: JSON.stringify(data),
			contentType: 'application/json; charset=utf-8',
			success: function(json) {
				console.log("inserted vertical OK");
				window.location.reload();
			},
			error: function(xhr, status) {
				var error_code = xhr.status + " " + xhr.statusText;
				$("#dialog_updating_frame_message").dialog("close");
				alert("ERROR inserting vertical: " + error_code);
			}
		});
	}


	console.log("loaded vertical_menu.js");
});



