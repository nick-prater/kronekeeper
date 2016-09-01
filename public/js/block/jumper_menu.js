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


define([
	'backbone',
        'jquery',
	'jqueryui'
], function (
) {
        'use strict';

	/* Initialise the menus and associated events */
	var $el = $("#jumper_menu");
	var this_view = null;
	$el.menu({
		select: handle_menu_selection
	});


	function show_menu(view) {

		if(!view) {
			console.log("show_menu called without passing a view");
		}

		this_view = view;
		$el.menu("collapseAll", null, true);
		set_allowed_menu_options();

		$el.show().position({
			my: "left top",
			at: "left bottom",
			of: view.$el.find('.jumper_menu_button'),
			collision: "fit flip"
		});

		/* Clicking outside the menu closes it */
		$(document).on("click", hide_menu);
		$(document).on("keypress", hide_menu);
	}


	function hide_menu() {
		$el.hide();
		$(document).off("click");
		$(document).off("keypress");
	}


	function set_allowed_menu_options() {

		enable_menu_action_if_true(
			"clear",
			this_view.model.id
		);
		enable_menu_action_if_true(
			"jumper_to_here",
			valid_jumper_destination()
		);
		enable_menu_action_if_true(
			"show_destination",
			this_view.model.id
		);
	}

	function valid_jumper_destination() {

		/* Returns true if this is valid as a "jumper to here" destination.
		 * Note this only allows us to jumper within the same frame.
		 */
		return (
			sessionStorage.jumpering_from_circuit_id &&
			(sessionStorage.jumpering_from_circuit_id != this_view.model.circuit.id) &&
			sessionStorage.jumpering_from_frame_id &&
			(sessionStorage.jumpering_from_frame_id == this_view.model.circuit.get("frame_id"))
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

			case "clear" :
				this_view.jumper_remove();
				break;
			case "jumper_from_here" :
				jumper_from_here();
				break;
			case "jumper_to_here" :
				jumper_to_here();
				break;
			case "show_destination" :
				this_view.trigger("show_destination");
				break;
		}
	}


	function jumper_from_here() {
		console.log("setting jumper source to:", this_view.model.circuit.id);
		sessionStorage.jumpering_from_circuit_id = this_view.model.circuit.id;
		sessionStorage.jumpering_from_frame_id = this_view.model.circuit.get("frame_id");
	}


	function jumper_to_here() {
		this_view.trigger("add_jumper", {
			circuit_id: this_view.model.circuit.id,
			jumper_id: this_view.model.id,
			destination_circuit_id: sessionStorage.jumpering_from_circuit_id
		});
		sessionStorage.removeItem("jumpering_from_circuit_id");
		sessionStorage.removeItem("jumpering_from_frame_id");
	}


	console.log("loaded jumper_menu.js");

	return {
		show: show_menu
	};
});



