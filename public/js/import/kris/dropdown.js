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
        'jquery',
], function (
) {
        'use strict';

	/* We want to display a rich drop-down of jumper templates, including
	 * div elements to illustrate the wire colours. A standard html <select>
	 * doesn't allow anything but text in <option> elements, so cannot be used
	 * for this. Instead we construct our own select-type dropdown based on
	 * an unordered list.
	 *
	 * Inspired by:
	 *   http://jsfiddle.net/6zcRk/ and
	 *   http://stackoverflow.com/questions/9548618/custom-drop-down-panel-with-jquery
	 *   http://www.jankoatwarpspeed.com/reinventing-a-drop-down-with-css-and-jquery/
	 */


	/* Initialises a custom drop-down select widget. Pass a jquery reference to the containing div */
	function initialise(container, initial_value) {

		var list = container.find('ul');
		var selection = container.find("div.selection");
		var selection_label = selection.find("span.option");

		selection.click(function(e) {

			e.stopPropagation();

			if(list.is(":hidden")) {

				list.show();

				/* Add event handlers */
				list.find('li').on("click", handle_select);
				$(document).on("click", handle_document_click);
				$(document).on("keydown", handle_keydown);
			}

			function hide_dropdown() {

				list.hide();

				/* Clean-up event handlers */
				list.find('li').off("click", handle_select);
				$(document).off("click", handle_document_click);
				$(document).off("keydown", handle_keydown);
			}

			function handle_keydown(e) {

				if(e.which == 27) {
					hide_dropdown();
				}		
			}

			function handle_select(e) {

				e.stopPropagation();
				selection_label.html(e.currentTarget.innerHTML);
				selection_label.data("value", e.currentTarget.dataset.value);

				console.log("selected " + selection_label.data("value"));
				hide_dropdown();
			}

			function handle_document_click(e) {
				
				e.stopPropagation();
				hide_dropdown();
			}

		});

		if(initial_value) {
			selection_label.html(
				list.find("li[data-value='" + initial_value + "']").first().html()
			);
		}
	}



	console.log("loaded import/kris/dropdown.js");

	/* Our Exports */
	return {
		initialise: initialise
	};
});
