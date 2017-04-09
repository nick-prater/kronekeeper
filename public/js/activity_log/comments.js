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

	var element;

	/* Initialise dialog */
	var cancel_button = {
		text: "Cancel",
		icon: "ui-icon-close",
		click: function(e) {
			$(this).dialog("close");
		}
	};
	var save_button = {
		text: "Save",
		icon: "ui-icon-check",
		click: function(e) {
			save_note();
		}
	};

	$("#comments_dialog").dialog({
		autoOpen: false,
		modal: true,
		buttons: [cancel_button, save_button],
		close: function(event) {
			element = null;
		}
	});

	$("#comments_dialog textarea").on("input", update_save_button_state);


	function get_activity_log_id() {

		var tr = $(element).closest("tr");
		var activity_log_id = tr.data("id");

		if(!activity_log_id) {
			console.log("ERROR: failed to determine activity_log_id for this row");
		}

		return activity_log_id;
	}


	function get_comment() {
		return $(element).children("span.comment_text").text();
	}



	function display(e) {

		/* Called by click event on comments button */
		element = e.currentTarget;
		$("#comments_dialog div.message").html("");
		$("#comments_dialog textarea").val(get_comment());
		update_save_button_state();
		$("#comments_dialog").dialog("open");
	};


	function update_save_button_state() {

		/* Enable/Disable Save button depending whether note text has changed */
		if($("#comments_dialog textarea").val() != get_comment()) {
			$("#comments_dialog").parent().find('button:contains("Save")').button("enable");
		}
		else {
			$("#comments_dialog").parent().find('button:contains("Save")').button("disable");
		}
	};


	function save_note() {

		$("#comments_dialog div.message").html(
			$('#saving_comment_message').html()
		);
		$("#comments_dialog").parent().find('button:contains("Save")').button("disable");

		var data = {
			comment: $("#comments_dialog textarea").val()
		};

		$.ajax({
			url: "/api/activity_log/" + get_activity_log_id(),
			method: 'PATCH',
			data: JSON.stringify(data),
			error: function(jq_xhr, status_text, error_text) {
				console.log("error updating activity log", status_text, error_text);
				$("#comments_dialog div.message").html(
					$('#failed_saving_comment_message').html()
				);
				$("#comments_dialog").parent().find('button:contains("Save")').button("enable");
			},
			success: function(json, status_text, jq_xhr) {
				console.log("activity log updated");

				/* Write updated comment back to html */
				var template = _.template(
					$('#comments_button_template').html()
				);
				$(element).replaceWith(
					template(data)
				);

				$("#comments_dialog").dialog("close");
			}
		});
	}


	console.log("comments module loaded");


	/* Export public methods */
	return {
		display: display
	};
});

