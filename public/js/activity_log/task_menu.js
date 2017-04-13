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
	'activity_log/filter',
        'jquery',
	'jqueryui'
], function (
	filter
) {
        'use strict';

	var jq_row;

	/* Initialise the menus and associated events */
	var $el = $("#task_menu");
	$el.menu({
		select: handle_menu_selection
	});

	/* Intialise needed dialogs */
	var cancel_button = {
		text: "Cancel",
		icon: "ui-icon-close",
		click: function(e) {
			$(this).dialog("close");
		}
	};
	var complete_button = {
		text: "Complete",
		icon: "ui-icon-check",
		click: function(e) {
			mark_this_and_previous_tasks_complete();
		}
	};

	$("#bulk_complete_dialog").dialog({
		autoOpen: false,
		modal: true,
		buttons: [cancel_button, complete_button],
		open: function() {
			/* Close dialog on Escape key, even if we don't have focus. */
			$(document).on("keydown", function(e) {
				if(e.which == 27) {
					$("#bulk_complete_dialog").dialog("close");
				}
			});
		},
		close: function() {
			$(document).off("keydown");
		}
	});


	function show_menu(e) {

		console.log("showing task menu");
		jq_row = $(e.currentTarget).closest("tr");
		$el.menu("collapseAll", null, true);
		set_allowed_menu_options();

		$el.show().position({
			my: "right top",
			at: "left bottom",
			of: $(e.currentTarget),
			collision: "fit flip"
		});

		/* Clicking outside the menu closes it */
		$(document).on("click", hide_menu);
		$(document).on("keypress", hide_menu);

		return false;
	}


	function hide_menu(e) {
		$el.hide();
		$(document).off("click");
		$(document).off("keypress");
	}


	function set_allowed_menu_options() {

		enable_menu_action_if_true(
			"complete-this",
			!jq_row.find("input.completed").first().prop("checked")
		);
	}


	function enable_menu_action_if_true(action, t) {

		var selector = "li[data-action='" + action + "']";
		var elements = $el.find(selector);

		if(t) {
			elements.removeClass("ui-state-disabled");
		}
		else {
			elements.addClass("ui-state-disabled");
		}
	}


	function handle_menu_selection(e, jq_element) {

		e.stopPropagation();
		console.log(e.currentTarget.dataset.action, "action clicked");
		hide_menu();

		switch(e.currentTarget.dataset.action) {

			case "complete-this" :
				mark_this_task_complete();
				break;

			case "complete-this-and-previous" :
				display_bulk_complete_dialog();
				break;
		}
	}


	function mark_this_task_complete() {
		var checkbox = jq_row.find("input.completed").first();
		checkbox.prop("checked", true);
		checkbox.trigger("change");
	}


	function display_bulk_complete_dialog() {
		$("#bulk_complete_dialog div.section.messages div.message").hide();
		$("#bulk_complete_dialog div.section.main").show();
		$("#bulk_complete_dialog").dialog("open");
	}



	function mark_this_and_previous_tasks_complete() {

		$("#bulk_complete_dialog div.section.main").hide();
		$("#bulk_complete_dialog div.section.messages div.message").hide();
		$("#bulk_complete_update_message").show();

		var data = {
			kk_filter: filter.get_parameters(),
		};
		data.kk_filter.max_activity_log_id = jq_row.data("id")
		console.log(data);

		$.ajax({
			url: "activity_log/bulk_complete",
			method: 'POST',
			data: JSON.stringify(data),
			error: function(jq_xhr, status_text, error_text) {
				console.log("error doing bulk complete operation", status_text, error_text);
				$("#bulk_complete_dialog div.section.messages div.message").hide();
				$("#bulk_complete_error_message").show();
			},
			success: function(json, status_text, jq_xhr) {
				console.log("completed bulk complete operation", json);

				/* Update the selected row */
				jq_row.find("input.completed").prop("checked", true);
				jq_row.addClass("completed");

				/* Update other rows on view */
				jq_row.nextAll().find("input.completed").prop("checked", true);
				jq_row.nextAll().addClass("completed");

				/* Remove next_task highlight from all items */
				var tbody = jq_row.closest("tbody");
				tbody.find("tr").removeClass("next_task");

				/* Then, highlight next_task if we have it and it's visible */
				if(json.next_item_id) {
					tbody.find("tr").has('input[value="' + json.next_item_id + '"]').addClass("next_task");
				}

				$("#bulk_complete_dialog").dialog("close");
			}
		});

	}


	console.log("loaded task_menu.js");

	return {
		show: show_menu
	};
});



