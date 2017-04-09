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
	'backbone',
        'jquery',
	'jqueryui'
], function (
) {
        'use strict';

	var jq_row;

	/* Initialise the menus and associated events */
	var $el = $("#task_menu");
	$el.menu({
		select: handle_menu_selection
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
				console.log("marking this and previous tasks as complete");
				break;
		}
	}


	function mark_this_task_complete() {
		var checkbox = jq_row.find("input.completed").first();
		checkbox.prop("checked", true);
		checkbox.trigger("change");
	}


	console.log("loaded task_menu.js");

	return {
		show: show_menu
	};
});



