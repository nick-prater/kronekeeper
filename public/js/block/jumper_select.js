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

	/* TODO: On dialog close, should we cancel any pending xhr requests? */

	/* Action to take when dialog is cancelled */
	var cancel_action = null;


	$("#jumper_connection_dialog").dialog({
		autoOpen: false,
		modal: true,
		buttons: {
			Cancel: function(event) {
				$(this).dialog("close");
			}
		},
		close: function(event) {
			cancel_action()
		}
	});


	function display(args) {

		cancel_action = args.cancel_action;

		/* Reset dialog to show 'loading' message before loading new content */
		$("#jumper_connection_dialog").html($("#loading_message_template").html());
		$("#jumper_connection_dialog").dialog("open");

		var request_data = {
			a_circuit_id: args.circuit_id,
			b_designation: args.destination_designation,
			jumper_id: args.jumper_id  // null unless we're replacing an existing jumper
		};

		console.log("displaying jumper connection choices for:", request_data);

		$("#jumper_connection_dialog").load(
			'/jumper/connection_choice',
			request_data,
			function(response, status, xhr) {
				if(status=="success") {
					console.log("loaded connection choices OK");
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


	console.log("jumper_select module loaded");

	/* Export public methods */
	return {
		display: display
	};
});

