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

	var model;

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

	$("#circuit_note_dialog").dialog({
		autoOpen: false,
		modal: true,
		buttons: [cancel_button, save_button],
		close: function(event) {
			model = null;
		}
	});

	$("#circuit_note_dialog textarea").on("input", update_save_button_state);


	function display(args) {
		model = args.model;
		$("#circuit_note_dialog textarea").val(model.get("note"));
		$("#circuit_note_dialog div.message").html("");
		update_save_button_state();
		$("#circuit_note_dialog").dialog("open");
	};


	function update_save_button_state() {

		/* Enable/Disable Save button depending whether note text has changed */
		if($("#circuit_note_dialog textarea").val() != model.get("note")) {
			$("#circuit_note_dialog").parent().find('button:contains("Save")').button("enable");
		}
		else {
			$("#circuit_note_dialog").parent().find('button:contains("Save")').button("disable");
		}
	};


	function save_note() {

		$("#circuit_note_dialog div.message").html(
			$('#saving_note_message').html()
		);
		$("#circuit_note_dialog").parent().find('button:contains("Save")').button("disable");

		var data = {
			note: $("#circuit_note_dialog textarea").val()
		};
		model.save(data, {
			patch: true,
			success: function(model, response, options) {

				$("#circuit_note_dialog").dialog("close");
/*
				$("#circuit_note_dialog div.message").html(
					$('#saved_note_message').html()
				);
				setTimeout(function() {
					$("#circuit_note_dialog").dialog("close");
				}, 500);
*/
			},
			error: function(model, xhr, options) {
				$("#circuit_note_dialog div.message").html(
					$('#failed_saving_note_message').html()
				);
				$("#circuit_note_dialog").parent().find('button:contains("Save")').button("enable");
			}
		});
	}


	/* Not used */
	function display_load_error(error_code) {

		/* Displays a loading failed message in the dialog */
		var template = _.template( $('#loading_error_template').html() );
		$("#circuit_note_dialog").html(
			template({
				error_code: error_code
			})
		);
	}




	console.log("notes module loaded");


	/* Export public methods */
	return {
		display: display
	};
});

