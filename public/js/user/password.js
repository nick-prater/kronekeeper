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


require([
        'jquery'
], function (
) {
        'use strict';


	$("#submit_button").click(handle_submit);	


	function handle_submit(e) {

		e.preventDefault();
		e.stopPropagation();

		/* Clear all messages */
		$(".change_password .message div").hide();

		if($("#new_password_1").val() != $("#new_password_2").val()) {
			console.log("new passwords do not match");
			$("#password_mismatch_message").show();
			return;
		}

		var data = {
			old_password: $("#old_password").val(),
			new_password: $("#new_password_1").val()
		};

		$("#submit_button").attr("disabled", "disabled");

		$.ajax({
			url: "/api/user/password",
			data: data,
			method: 'POST',
			error: function(jq_xhr, status_text, error_text) {
				console.log("error updating password", jq_xhr.status);
				if(jq_xhr.status == 403) {
					$("#password_incorrect_message").show();
				}
				else {
					$("#password_change_error_message").show();
				}
				$("#submit_button").removeAttr("disabled");
			},
			success: function(data, status_text, jq_xhr) {
				console.log("updated password");
				$("#password_change_ok_message").show();
				setTimeout(function() {
					$("#submit_button").removeAttr("disabled");
				}, 500);
			}
		});
	}



	console.log("loaded user/password.js");
});

