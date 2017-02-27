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


require([
	'jquery',
], function (
) {
        'use strict';

	/* Initialisation */
	$("#add_frame_form .validation_error").removeClass("validation_error");
	$("#add_frame_form div.message").hide();
	$("#create_frame_button").prop("disabled", false);


	$("#add_frame_form").submit(function(e) {

		e.preventDefault();
		$("#create_frame_button").prop("disabled", true);

		console.log("create frame submit button clicked");

		/* Clear any existing error highlighting */
		$("#add_frame_form .validation_error").removeClass("validation_error");
		$("#add_frame_form div.message").hide();

		var data = extract_form_data();

		if(!validate_data(data)) {
			console.log("validation failed");
			$("#create_frame_button").prop("disabled", false);
			return;
		}

		add_frame(data);
	});
	


	function extract_form_data() {
		var data = {
			frame_name: $("#frame_name").val(),
			frame_width: parseInt($("#frame_width").val(), 10),
			frame_height: parseInt($("#frame_height").val(), 10),
			designation_order_h: $("#designation_order_h").val(),
			designation_order_v: $("#designation_order_v").val(),
			is_template: $("#is_template").prop("checked")
		};

		console.log(data);
		return data;
	}



	function validate_data(data) {

		/* Not all browsers support HTML5 form validation, notably the
		 * version of Safari used by Global Radio, so we perform our own
		 * validation here of the user-entered data. If the browser does 
		 * support form validation, this code should be redundant. This is
		 * part of the fix for github issue #2.
		 */
		var errors = [];
		var max_width = $("#frame_width").attr("max");
		var max_height = $("#frame_height").attr("max");

		/* Name */
		if(!data.frame_name) {
			errors.push({
				id: "frame_name",
				message: "enter a frame name"
			});
		}

		/* Width */
		if(!$.isNumeric(data.frame_width)) {
			errors.push({
				id: "frame_width",
				message: "enter a frame width"
			});
		}
		else if(data.frame_width < 1) {
			errors.push({
				id: "frame_width",
				message: "frame width cannot be less than 1"
			});
		}
		else if(data.frame_width > max_width) {
			errors.push({
				id: "frame_width",
				message: "frame width cannot be greater than " + max_width
			});
		}

		/* Height */
		if(!$.isNumeric(data.frame_height)) {
			errors.push({
				id: "frame_height",
				message: "enter a frame height"
			});
		}
		else if(data.frame_height < 1) {
			errors.push({
				id: "frame_height",
				message: "frame height cannot be less than 1"
			});
		}
		else if(parseInt(data.frame_height) > max_height) {
			errors.push({
				id: "frame_height",
				message: "frame height cannot be greater than " + data.frame_height + "/" + max_height
			});
		}


		/* Highlight first error */
		if(errors.length > 0) {
			$("#" + errors[0].id).addClass("validation_error");
			$("#validation_message").text("ERROR: " + errors[0].message);
			$("#validation_message").show();
		}

		/* Returns true if there are no errors, false otherwise */
		return (errors.length == 0);
	}



	function add_frame(data) {

		$("#creating_frame_message").show();

		$.ajax({
			url: "/api/frame/add",
			method: 'POST',
			data: JSON.stringify(data),
			error: function(jq_xhr, status_text, error_text) {
				console.log("error adding frame:", error_text);
				$("#add_frame_form div.message").hide();

				/* Special case error if user is exceeding their frame limit */
				if(jq_xhr.responseJSON && jq_xhr.responseJSON.error_code == "TOO_MANY_FRAMES") {
					console.log("Cannot add new frame - too many frames");
					$("#too_many_frames_message").show();
				}
				else {
					$("#create_error_message").show();
				}

				$("#create_frame_button").prop("disabled", false);
			},
			success: function(json, status_text, jq_xhr) {

				/* Display success message, then display new frame */
				console.log("added frame_id", json.frame_id);
				$("#add_frame_form div.message").hide();
				$("#created_frame_message").show();

				/* Display new standard or temporary frame */
				if(json.is_template) {
					console.log("displaying newly created template");
					window.location = "/template/" + json.frame_id;
				}
				else {
					console.log("displaying newly created frame");
					window.location = "/frame/" + json.frame_id;
				}
			}
		});
	}


});
