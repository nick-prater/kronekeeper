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
	'backbone',
        'jquery',
	'jqueryui'
], function (
) {
        'use strict';

	function data_from_form() {
		/* Extracts the user attributes from the form on-screen */
		var rv = {
			email: $("#login").val(),
			name: $("#name").val(),
			is_active: $("#enabled_checkbox").prop('checked'),
			roles: selected_roles(),
			id: window.user_id
		};
		return rv;
	}

	function selected_roles() {
		/* Returns an array of the roles selected on-screen */
		var selected_roles = [];
		$(".roles input:checkbox:checked").each(function(index, element) {
			selected_roles.push($(element).val());
		});
		return selected_roles;
	}


	var User_Model = Backbone.Model.extend({
		urlRoot: '/api/user',
		save_data: function(data) {

			this.set(data);

			if(!this.changedAttributes()) {
				console.log("nothing changed");
				this.trigger("unchanged");
			}
			else {
				var previous_attributes = this.previousAttributes();
				this.save(this.changedAttributes(), {
					patch: true,
					error: function(model, xhr, options) {
						console.log("ERROR saving user data");
						model.set(previous_attributes);
					}
				});
			}
		}
	});

	var User_View = Backbone.View.extend({

		el: '#user_form',

		events: {
			'click #update_button' : 'do_update'
		},

		initialize: function() {
			console.log("current_state:", this.model.attributes);
			console.log("view initialised");

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
		},

		do_update: function(e) {
			this.disable_buttons();
			this.show_message("#saving_message");
			var result = this.model.save_data(
				data_from_form()
			);
		},

		disable_buttons: function(e) {
			$("#reset_password_button").attr("disabled", "disabled");
			$("#update_button").attr("disabled", "disabled");
		},
		enable_buttons: function(e) {
			$("#reset_password_button").removeAttr("disabled");
			$("#update_button").removeAttr("disabled");
		},

		show_message: function(selector) {
			$(".message div").hide();
			$(selector).show();
		},

		upload_error: function(model, xhr, options) {
			if(xhr.status == 409) {
				this.show_message("#login_conflict_message");
			}
			else if(xhr.status == 403) {
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

	var user_view = new User_View({
		model: new User_Model(data_from_form())
	});


	console.log("loaded user.js");
});

