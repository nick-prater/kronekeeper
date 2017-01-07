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
        'jquery',
	'jqueryui'
], function (
) {
        'use strict';

	var jq_row;
	var frame_id;

	function initialise() {

		/* Initialise dialog */
		var cancel_button = {
			text: "Cancel",
			icon: "ui-icon-close",
			click: function(e) {
				$(this).dialog("close");
			}
		};
		var copy_button = {
			text: "Copy",
			icon: "ui-icon-copy",
			click: function(e) {
				copy_frame(frame_id);
			}
		};

		$("#dialog_confirm_copy").dialog({
			autoOpen: false,
			modal: true,
			buttons: [cancel_button, copy_button],
			open: function() {
				/* Close dialog on Escape key, even if we don't have focus. */
				$(document).on("keydown", function(e) {
					if(e.keyCode == 27) {
						console.log("Escape key pressed - closing dialog");
						$("#dialog_confirm_copy").dialog("close");
					}
					if(e.keyCode == 13) {
						/* Default Action */
						copy_frame(frame_id);
					}
				});
			},
			close: function() {
				jq_row = null;
				frame_id = null;
				$(document).off("keydown");
			}
		});

		$("table a.copy").click(display_dialog);
	}


	function display_dialog(e) {

		jq_row = $(e.target).closest("tr");
		frame_id = jq_row.data('frame_id');

		/* Set a default for the new name */
		var frame_name = jq_row.find("td a.name").first().text();
		$("#new_name").val(frame_name + ' (copy)');

		$("#dialog_confirm_copy div.section.messages div.message").hide();
		$("#dialog_confirm_copy div.section.main").show();
		$("#dialog_confirm_copy").dialog("open");
	}


	function copy_frame() {

		/* Looks at global frame_id and jq_row variables */		
		$("#dialog_confirm_copy div.section.main").hide();
		$("#dialog_confirm_copy div.section.messages div.message").hide();
		$("#copying_message").show();

		var data = {
			frame_id: frame_id,
			frame_name: $("#new_name").val()
		};
		$.ajax({
			url: "/api/frame/copy",
			method: 'POST',
			data: JSON.stringify(data),
			error: function(jq_xhr, status_text, error_text) {
				console.log("error copying frame", status_text, error_text);
				$("#dialog_confirm_copy div.section.messages div.message").hide();
				$("#copy_error_message").show();
			},
			success: function(json, status_text, jq_xhr) {
				console.log("copied frame");
				$("#dialog_confirm_copy div.section.messages div.message").hide();
				$("#copy_success_message").show();
				location.reload();
			}
		});
	}


	console.log("loaded frames/copy.js");

	/* Expose public methods/properties */
	return {
		initialise: initialise
	};
});



