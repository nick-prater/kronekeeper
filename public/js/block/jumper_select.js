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

	/* TODO: On dialog close, should we cancel any pending xhr requests? */

	/* Default action to take when dialog is cancelled or jumper is successfully installed */
	var cancel_action;
	var success_action;
	var close_success_flag;

	/* Initialise dialog */
	var cancel_button = {
		text: "Cancel",
		icon: "ui-icon-close",
		click: function(e) {
			$(this).dialog("close");
		}
	};

	$("#jumper_connection_dialog").dialog({
		autoOpen: false,
		modal: true,
		buttons: [cancel_button],
		close: function(event) {
			if(close_success_flag) {
				console.log("close dialog - success");
				close_success_flag = false;
			}
			else {
				console.log("close dialog - cancel");
				cancel_action();
			}
		}
	});



	function display(args) {

		console.log("display()");
		cancel_action = args.cancel_action;
		success_action = args.success_action;

		/* Reset buttons to initial state */
		$("#jumper_connection_dialog").dialog("option",	"buttons", [cancel_button]);

		/* Reset dialog to show 'loading' message before loading new content */
		$("#jumper_connection_dialog").html($("#loading_message_template").html());
		$("#jumper_connection_dialog").dialog("open");

		/* Are we replacing an existing jumper? */
		var replacing_jumper_id = args.jumper_id;

		var request_data = {
			a_circuit_id: args.circuit_id,
			b_designation: args.destination_designation,
			replacing_jumper_id: replacing_jumper_id
		};

		console.log("displaying jumper connection choices for:", request_data);

		$("#jumper_connection_dialog").load(
			'/jumper/connection_choice',
			request_data,
			function(response, status, xhr) {
				if(status=="success") {
					console.log("loaded connection choices OK");
					handle_connection_choice_load_success();
				}
				else {
					var error_code = xhr.status + " " + xhr.statusText;
					display_load_error(error_code);
				}
			}
		);
	};



	function display_load_error(error_code) {

		/* Displays a loading failed message in the dialog */
		var template = _.template( $('#loading_error_template').html() );
		$("#jumper_connection_dialog").html(
			template({
				error_code: error_code
			})
		);
	}



	function handle_connection_choice_load_success() {

		console.log("handle_connection_choice_load_success");

		/* Set buttons - as a side-effect this re-centres the dialog */
		$("#jumper_connection_dialog").dialog("option",	"buttons", [cancel_button]);

		/* Set up events on dynamically loaded content */
		$("#simple_jumper_button").on("click", handle_simple_jumper_click);
		$("#custom_jumper_button").on("click", handle_custom_jumper_click);
		$(".choose_jumper_connections select").on("change", jumper_connection_change);
		$("select.wire_colour_picker").on("change", handle_wire_colour_change);
	}


	function handle_wire_colour_change(event) {
		disable_next_button_when_invalid();
	}


	function handle_simple_jumper_click(event) {

		/* Load jumper selection */
		console.log("simple jumper selected");

		/* Reset buttons and show 'loading' message */
		$("#jumper_connection_dialog").html($("#loading_message_template").html());
		$("#jumper_connection_dialog").dialog("option",	"buttons", [cancel_button]);

		var request_data = {
			wire_count: window.jumper_state.a_pins.length,
			a_designation: window.jumper_state.a_circuit.full_designation,
			b_designation: window.jumper_state.b_circuit.full_designation,
		};

		console.log("displaying jumper wire choices for:", request_data);

		$("#jumper_connection_dialog").load(
			'/jumper/wire_choice',
			request_data,
			function(response, status, xhr) {
				if(status=="success") {
					console.log("loaded wire choices OK");
					handle_wire_choice_load_success();
				}
				else {
					var error_code = xhr.status + " " + xhr.statusText;
					display_load_error(error_code);
				}
			}
		);
	}


	function handle_wire_choice_load_success() {

		/* Set buttons - as a side-effect this re-centres the dialog */
		$("#jumper_connection_dialog").dialog("option",	"buttons", [cancel_button]);

		/* Set up events on dynamically loaded content */
		$(".choose_jumper_template .option_group div.option_item").on("click", handle_jumper_template_click);
	}


	function handle_custom_jumper_click(event) {

		console.log("custom jumper selected");

		$("#choose_jumper_type_div").hide();
		$("#choose_jumper_connections_div").show();

		/* Add a next button, but leave it disabled until at least one connection is made */
		/* This has a side-effect of re-centering the dialog on the page */
		var next_button = {
			text: "Next",
			icon: "ui-icon-check",
			click: function(e) {
				add_custom_jumper(e);
			}
		};
		$("#jumper_connection_dialog").dialog("option",	"buttons", [cancel_button, next_button]);
		$("#jumper_connection_dialog").parent().find('button:contains("Next")').button("disable");
	}


	function disable_next_button_when_invalid () {

		/* We need at least one selected b_pin
		 * All selected b_pins must have a colour selected
		 */

		var state = "disable";
		$(".choose_jumper_connections select.b_pin_picker").each(function() {
			var b_pin_id = $(this).val();
			var colour_id = $(this).parent().parent().find("select.wire_colour_picker").first().val();

			if(b_pin_id && colour_id) {
				state = "enable";
			}
			else if(b_pin_id && !colour_id) {
				state = "disable";
				return false;
			}
		});

		$("#jumper_connection_dialog").parent().find('button:contains("Next")').button(state);
	}


	function jumper_connection_change(e) {
		disable_next_button_when_invalid();
	}


	function add_custom_jumper(event) {

		var connections = [];
		$(".choose_jumper_connections select.b_pin_picker").each(function() {
			var a_pin_id = $(this).parent().parent().attr("data-a_pin_id");
			var b_pin_id = $(this).val();
			var colour_id = $(this).parent().parent().find("select.wire_colour_picker").first().val();

			if(b_pin_id && colour_id) {
				var connection = {
					a_pin_id: a_pin_id,
					b_pin_id: b_pin_id,
					wire_colour_id: colour_id
				};
				console.log(connection);
				connections.push(connection);
			}
		});

		var data = {
			a_circuit_id: window.jumper_state.a_circuit.id, 
			b_circuit_id: window.jumper_state.b_circuit.id,
			replacing_jumper_id: window.jumper_state.replacing_jumper_id,
			connections: connections
		};
		console.log(data);

		/* Send request to server */
		$.ajax({
			url: "/api/jumper/add_custom_jumper",
			contentType: 'application/json; charset=utf-8',
			data: JSON.stringify(data),
			type: "POST",
			dataType: "json",
			success: function(json) {
				console.log("updated jumper OK");
				close_success_flag = true;
				$("#jumper_connection_dialog").dialog("close");
				success_action(json);
			},
			error: function(xhr, status) {
				var error_code = xhr.status + " " + xhr.statusText;
				display_load_error(error_code);
			}
		});
	}


	function handle_jumper_template_click(event) {
		console.log("jumper_template_click");
		$("#jumper_connection_dialog").html($("#creating_jumper_message_template").html());
		$("#jumper_connection_dialog").dialog("option",	"buttons", [cancel_button]);

		var data = {
			a_circuit_id: window.jumper_state.a_circuit.id, 
			b_circuit_id: window.jumper_state.b_circuit.id,
			jumper_template_id: event.currentTarget.getAttribute("data-jumper_template_id"),
			replacing_jumper_id: window.jumper_state.replacing_jumper_id
		};

		/* Send request to server */
		console.log(data);
		$.ajax({
			url: "/api/jumper/add_simple_jumper",
			type: "POST",
			contentType: 'application/json; charset=utf-8',
			data: JSON.stringify(data),
			dataType: "json",
			success: function(json) {
				console.log("updated jumper OK");
				close_success_flag = true;
				$("#jumper_connection_dialog").dialog("close");
				success_action(json);
			},
			error: function(xhr, status) {
				var error_code = xhr.status + " " + xhr.statusText;
				display_load_error(error_code);
			}
		});
	}


	console.log("jumper_select module loaded");

	/* Export public methods */
	return {
		display: display
	};
});

