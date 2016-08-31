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

	var element;
	var $element;

	function initialise(args) {
		element = args.element;
		$element = $(args.element);
		$(document).on("keydown", handle_keydown);
	}

	function enable_selection() {
		$element.find("div.option_group div.option_item.selected").removeClass("selected");
		$element.find("div.option_group div.option_item").filter(":visible").first().addClass("selected");
	}

	function close() {
		$(document).off("keydown");
	}


	function handle_keydown(e) {

		/* Only process keypress if dialog is open */
		if(!$element.dialog("isOpen")) {
			return true;
		}

		switch(e.keyCode) {
			case 27:
				// Escape
				$element.dialog("close");
				break;
			case 38:
				// Up Arrow
				select_previous_option();
				break;
			case 40:
				// Down Arrow
				select_next_option();
				break;
			case 13:
				// Enter
				trigger_selected_option();
				break;
		}

		return false;
	}


	function trigger_selected_option() {
		var selected_element = $element.find("div.option_group div.option_item.selected").filter(":visible").first();
		selected_element.trigger("click");
	}

	function select_next_option() {
		var selected_element = $element.find("div.option_group div.option_item.selected").filter(":visible").first();
		var next_element = selected_element.next("div.option_item");
		if(next_element.length) {
			selected_element.removeClass("selected");
			next_element.addClass("selected");
		}
	}

	function select_previous_option() {
		var selected_element = $element.find("div.option_group div.option_item.selected").filter(":visible").first();
		var next_element = selected_element.prev("div.option_item");
		if(next_element.length) {
			selected_element.removeClass("selected");
			next_element.addClass("selected");
		}
	}


	return {
		initialise: initialise,
		enable_selection: enable_selection,
		close: close
	};
});
