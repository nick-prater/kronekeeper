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


define([
	'backbone',
        'jquery',
	'jqueryui'
], function (
) {
        'use strict';

	var properties = {};

	/* Initialise dialog */
	var cancel_button = {
		text: "Cancel",
		icon: "ui-icon-close",
		click: function(e) {
			$(this).dialog("close");
		}
	};
	var remove_button = {
		text: "Remove",
		icon: "ui-icon-trash",
		click: remove_vertical
	};

	$("#dialog_confirm_remove_vertical").dialog({
		autoOpen: false,
		modal: true,
		buttons: [cancel_button, remove_button],
	});


	function remove_vertical() {

		console.log("removing vertical_id %d, all its blocks and jumpers", properties.vertical_id);
		var url = '/api/frame/remove_vertical';
		var data = {
			vertical_id: properties.vertical_id
		};

		$.ajax({
			url: url,
			type: "POST",
			contentType: 'application/json; charset=utf-8',
			data: JSON.stringify(data),
			dataType: "json",
			success: function(json) {
				console.log("removed vertical ok");
				$("#dialog_confirm_remove_vertical").dialog("close");
				properties.success_callback();
			},
			error: function(xhr, status) {
				var error_code = xhr.status + " " + xhr.statusText;
				alert("ERROR removing vertical: " + error_code);
			}
		});
	}


	function remove_from_display(vertical_id) {
		/* Removes all elements from the page for the specified
		 * vertical_id and decrements position for subsequent
		 * vertical elements.
		 */

		/* Get position number for vertical being removed */
		let removed_position = $(`th[data-vertical_id="${vertical_id}"]`).first().attr('data-position');
		if(!jQuery.isNumeric(removed_position)) {
			console.log("ERROR: Cannot determine position of vertical being removed");
			return;
		}
		console.log("removing vertical with position", removed_position);

		/* Remove specified vertical elements */
		$(`th[data-vertical_id="${vertical_id}"]`).remove();
		$(`td[data-vertical_id="${vertical_id}"]`).remove();

		/* Decrement position for subsequent vertical elements */
		$('th[data-position]').each((index, element) => {
			let element_position = $(element).attr('data-position');
			if(element_position > removed_position) {
				element_position --;
				$(element).attr('data-position', element_position);
			}
		});
	}


	function begin(args) {

		console.log("remove vertical triggered");
		properties.vertical_id = args.vertical_id;
		properties.success_callback = args.success;

		$("#dialog_confirm_remove_vertical").dialog("open");
	}

	console.log("loaded remove_vertical.js");

	return {
		begin: begin,
		remove_from_display: remove_from_display
	};
});
