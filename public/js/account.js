/* 
This file is part of Kronekeeper, a web based application for 
recording and managing wiring frame records.

Copyright (C) 2019 NP Broadcast Limited

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
	'backbone',
        'jquery',
	'jqueryui'
], function (
) {
        'use strict';

	function data_from_form() {
		/* Extracts the account attributes from the form on-screen */
		var rv = {
			name: $("#name").val(),
			max_frame_count: $("#max_frame_count").val(),
			max_frame_width: $("#max_frame_width").val(),
			max_frame_height: $("#max_frame_height").val(),
			id: window.account_id
		};
		return rv;
	}

	var Account_Model = Backbone.Model.extend({
		urlRoot: '/api/account',
		save_data: function(data) {

			this.set(data);
			var changes = this.changedAttributes();
			
			/* Only run update if something has changed */
			if($.isEmptyObject(changes)) {
				console.log("nothing changed");
				this.trigger("unchanged");
			}
			else {
				var previous_attributes = this.previousAttributes();
				this.save(changes, {
					patch: true,
					success: function(model, data, options) {
						if(data.id) {
							console.log("updated account_id:", data.id);
							window.account_id = data.id;
						}
					},
					error: function(model, xhr, options) {
						console.log("ERROR saving account data");
						model.set(previous_attributes);
					}
				});
			}
		}
	});

	var Account_View = Backbone.View.extend({

		el: '#account_form',

		events: {
			'click #update_button' : 'do_update',
		},

		initialize: function() {
			console.log("current_state:", this.model.attributes);

			this.listenTo(
				this.model,
				"unchanged",
				this.data_unchanged
			);
			this.listenTo(
				this.model,
				"error",
				this.upload_error
			);
			this.listenTo(
				this.model,
				"sync",
				this.upload_success
			);

			console.log("view initialised");
		},

		do_update: function(e) {
			var form_is_valid = $("#account_form").get(0).reportValidity();
			if(form_is_valid) {
				this.disable_buttons();
				this.show_message("#saving_message");
				var result = this.model.save_data(
					data_from_form()
				);
			}
			else {
				this.show_message("#validation_error_message");
			}
		},

		disable_buttons: function(e) {
			$("#update_button").attr("disabled", "disabled");
		},
		enable_buttons: function(e) {
			$("#update_button").removeAttr("disabled");
		},

		show_message: function(selector) {
			$(".message div").hide();
			$(selector).show();
		},

		upload_error: function(model, xhr, options) {
			if(xhr.status == 403) {
				this.show_message("#permission_denied_message");
			}
			else {
				this.show_message("#saving_error_message");
			}
			this.enable_buttons();
		},
		upload_success: function() {
			this.show_message("#saving_ok_message");
			this.enable_buttons();
			console.log("success");
		},
		data_unchanged: function() {
			this.show_message("#no_change_message");
			this.enable_buttons();
		}
	});

	var account_view = new Account_View({
		model: new Account_Model(data_from_form())
	});


	console.log("loaded account.js");
});

