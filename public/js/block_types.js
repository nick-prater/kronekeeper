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
        'jquery',
	'jqueryui'
], function (
) {
        'use strict';

	var jq_row;
	var block_type_id;

	function initialise() {

		/* Initialise dialog */
		var cancel_button = {
			text: "Cancel",
			icon: "ui-icon-close",
			click: function(e) {
				$(this).dialog("close");
			}
		};
		var delete_button = {
			text: "Delete",
			icon: "ui-icon-trash",
			click: function(e) {
				delete_block_type(block_type_id);
			}
		};

		$("#dialog_confirm_delete").dialog({
			autoOpen: false,
			modal: true,
			buttons: [cancel_button, delete_button],
			open: function() {
				/* Close dialog on Escape key, even if we don't have focus. */
				$(document).on("keydown", function(e) {
					console.log("Escape key pressed - closing dialog");
					$("#dialog_confirm_delete").dialog("close");
				});
			},
			close: function() {
				jq_row = null;
				block_type_id = null;
				$(document).off("keydown");
			}
		});

		/* Attach event handler to every row's delete button */
		$("table a.delete").click(display_dialog);
	}


	function display_dialog(e) {

		jq_row = $(e.target).closest("tr");
		block_type_id = jq_row.data('block_type_id');
		let block_type_name = jq_row.find('td.name').text();

		$("#name_of_block_type_to_delete").text(block_type_name);
		$("#dialog_confirm_delete div.section.messages div.message").hide();
		$("#dialog_confirm_delete div.section.main").show();
		$("#dialog_confirm_delete").dialog("open");
	}


	function delete_block_type() {

		/* Looks at global block_type_id and jq_row variables */		
		$("#dialog_confirm_delete div.section.main").hide();
		$("#dialog_confirm_delete div.section.messages div.message").hide();
		$("#deleting_message").show();

		$.ajax({
			url: "/api/block_type/" + block_type_id,
			method: 'DELETE',
			error: function(jq_xhr, status_text, error_text) {
				console.log("error deleting block_type", status_text, error_text);
				$("#dialog_confirm_delete div.section.messages div.message").hide();
				$("#delete_error_message").show();
			},
			success: function(json, status_text, jq_xhr) {
				console.log("deleted block_type");
				jq_row.remove();
				$("#dialog_confirm_delete").dialog("close");
			}
		});
	}

	initialise();
	console.log("loaded block_types.js"); 
});


