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
	'jqueryui'
], function (
) {
        'use strict';

	var view = null;

	/* Initialise dialogs */
	var cancel_button = {
		text: "Cancel",
		icon: "ui-icon-close",
		click: function(e) {
			$(this).dialog("close");
		}
	};
	var enable_user_button = {
		text: "Enable User",
		icon: "ui-icon-check",
		click: function(e) {
			$("#enabled_checkbox").prop('checked', true);
			$(this).dialog("close");
			reset_password();
		}
	};
	var ok_button = {
		text: "OK",
		icon: "ui-icon-check",
		click: function(e) {
			$(this).dialog("close");
		}
	};

	$("#dialog_confirm_enable_user").dialog({
		autoOpen: false,
		modal: true,
		buttons: [cancel_button, enable_user_button]
	});
	$("#dialog_show_new_password").dialog({
		autoOpen: false,
		modal: true,
		buttons: [ok_button]
	});


	function initialise(backbone_view) {

		view = backbone_view;
	}


	function handle_reset_password_button() {

		console.log("reset_password button clicked");

		if(!$("#enabled_checkbox").prop('checked')) {
			$("#dialog_confirm_enable_user").dialog("open");
		}
		else {
			reset_password();
		}
	}


	function reset_password() {

		console.log("generating new password");
		var new_password = generate_password();

		$("#generated_password").text(new_password);	
		$(".dialog.password_result .message div").hide();
		$("#saving_password_message").show();
		$("#dialog_show_new_password").dialog("open");

		save_password(new_password);
	}


	function save_password(new_password) {

		console.log("saving new password");

		var data = {
			new_password: new_password,
			email: view.model.get("email")
		};

		/* Validation and sanity check before update */
		if(!data.new_password || !data.email) {
			console.log("Can't set password - invalid data:", data);
			$(".dialog.password_result .message div").hide();
			$("#saving_password_error_message").show();
			return;
		}

		/* Do update */
		$.ajax({
			url: "/api/user/password",
			data: data,
			method: 'POST',
			error: function(jq_xhr, status_text, error_text) {
				console.log("error updating password", jq_xhr.status);
				$(".dialog.password_result .message div").hide();
				$("#saving_password_error_message").show();
			},
			success: function(data, status_text, jq_xhr) {
				console.log("updated password");
				$(".dialog.password_result .message div").hide();
				$("#saving_password_ok_message").show();
				view.model.set("is_active", true);
			}
		});
	}


	function generate_password() {

		var characters = "BCDFGHJKLMNOPQRSTVWXYZbcdfghjklmnpqrstvwxyz123456789";
		var count = 10;
		var rv = '';
		while(count) {
			var random_index = Math.floor(Math.random() * characters.length);
			rv += characters.charAt(random_index);
			count --;
		}
		return rv;
	}


	/* Exports */
	return {
		initialise: initialise,
		click: handle_reset_password_button,
		reset: reset_password
	};
});
