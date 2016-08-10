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
		click: remove_block
	};

	$("#dialog_confirm_remove").dialog({
		autoOpen: false,
		modal: true,
		buttons: [cancel_button, remove_button],
	});


	function remove_block() {

		console.log("removing block_id", properties.block_id, "and all its jumpers");
		var url = '/api/frame/remove_block';
		var data = {
			block_id: properties.block_id
		};

		$.ajax({
			url: url,
			type: "POST",
			contentType: 'application/json; charset=utf-8',
			data: JSON.stringify(data),
			dataType: "json",
			success: function(json) {
				console.log("removed block ok");
				$("#dialog_confirm_remove").dialog("close");
				properties.success_callback();
			},
			error: function(xhr, status) {
				var error_code = xhr.status + " " + xhr.statusText;
				alert("ERROR removing block: " + error_code);
			}
		});
	}


	function activate(args) {

		console.log("remove block triggered");
		properties.block_id = args.block_id;
		properties.success_callback = args.success;

		$("#dialog_confirm_remove").dialog("open");
	}


	return {
		activate: activate
	};
});
