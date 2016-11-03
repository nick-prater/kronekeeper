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

	var lists = $('.custom-select');

	/* Handle click on the dropdown list */
	lists.on('click', function(e) {

		e.stopPropagation();

		lists.not(this).find('ul:visible').hide();
		$(this).find('ul').slideToggle(0);
		

		/* Clicked target may be a child element, rather than the list item iteslf */
		var li = $(e.target).parentsUntil('ul').find('li').first();

		console.log("size: " + li.length);

		if (li) {

			console.log(li);

			li = $(e.target);
			/* Set html of top position to match the selected item */
			$(this).find('span').html(li.html());

			console.log("selected " + li.data('jumper_template_id'));
		}
	});

	/* Collapse dropdown if user clicks anywhere else on the page */
	/* TODO: react the same way on escape */
	$(document).click(function(e) {
		lists.find('ul:visible').hide();
	});


	console.log("loaded import/kris/dropdown.js");
});
