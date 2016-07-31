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
	'block/jumper_select',
	'backbone',
        'jquery',
	'jqueryui'
], function (
	jumper_select
) {
        'use strict';

	/* Highlight effect options */
	var highlight_green = {
		color: '#00ff00'
	};
	var highlight_duration = 1000;



	var Jumper_Model = Backbone.Model.extend({

		defaults: {
			designation: null,
			id: null
		},

		initialize: function(attributes, options) {
			this.circuit = options.circuit;
		},

		urlRoot: '/api/jumper'
	});


	var Jumper_View = Backbone.View.extend({

		tagName: 'td',
		className: 'jumper',
		template: _.template( $('#active_jumper_cell_template').html() ),

		events: {
			'input' : 'highlight_change',
			'change' : 'jumper_change',
			'keypress' : 'reset_on_escape_key'
		},

		initialize: function(attributes) {
			this.listenTo(
				this.model.circuit.collection,
				"jumper_deleted",
				this.jumper_deleted
			);
			this.listenTo(
				this.model,
				'sync',
				this.model_synced
			);
		},
	
		render: function() {
			var json = this.model.toJSON();
			this.$el.html(this.template(json));
			return this;
		},

		highlight_change: function(e) {
			if(e.target.value != this.model.get("designation")) {
				e.target.parentNode.classList.add('change_pending');
			}
			else {
				e.target.parentNode.classList.remove('change_pending');
			}
		},

		reset_on_escape_key: function(e) {
			if(e.keyCode == 27) {
				e.target.value = this.model.get("designation");
				e.target.parentNode.classList.remove('change_pending');
			}
		},

		jumper_change: function(e) {
			if(e.target.value == this.model.get("designation")) {
				/* No change - nothing to do */
				console.log("jumper unchanged");
			}
			else if (e.target.value == '') {
				this.jumper_remove();
			}
			else {
				console.log("jumper changed");
				var jumper_view = this;
				jumper_select.display({
					circuit_id: this.model.circuit.id,
					jumper_id: this.model.get("id"),
					destination_designation: e.target.value,
					cancel_action: function() {
						console.log("cancel action");
						e.target.value = jumper_view.model.get("designation");
						e.target.parentNode.classList.remove('change_pending');
						jumper_view.$el.effect("highlight", {}, highlight_duration);
					},
					success_action: function(data) {
						console.log("success action");
						jumper_view.model.set({
							id: data.jumper_id,
							designation: data.b_circuit_info.full_designation
						});
						e.target.value = data.b_circuit_info.full_designation;
						e.target.parentNode.classList.remove('change_pending');
						jumper_view.$el.effect("highlight", highlight_green, highlight_duration);
					}
				});
			}
		},

		jumper_remove: function() {
			var jq_element = this.$el;
			this.model.destroy({
				success: function(model, response, options) {
					console.log("jumper removed OK");
					jq_element.removeClass('change_pending');
					jq_element.effect("highlight", highlight_green, highlight_duration);
				},
				error: function(model, response, options) {
					console.log("ERROR removing jumper");
					alert("ERROR removing jumper");
				}
			});
			this.model.circuit.collection.trigger("jumper_deleted", this.model.get("id"));
			this.model.set(this.model.defaults);
		},

		jumper_deleted: function(deleted_jumper_id) {

			/* Responds to another jumper being deleted
			 * If we are the other end of the deleted jumper, we'll have the
			 * same id, but the text input field won't have been cleared.
			 */
			if(deleted_jumper_id == this.model.get("id") && this.$("input").val() != "") {
				this.$("input").val('');
				this.$el.effect("highlight", {}, highlight_duration);
				this.model.set(this.model.defaults);
			}
		},

		model_synced: function(model, response, options) {
			/* Clear field highlighting and flash green to indicate successful save
			 * Server returns the changed fields to confirm which have been updated
			 */
			console.log("jumper model synced");
			this.$el.removeClass('change_pending');
			this.$el.effect("highlight", highlight_green, highlight_duration);
		}

	});


	console.log("loaded block/jumper.js");

	/* Expose public methods */
	return {
		model: Jumper_Model,
		view: Jumper_View
	};
});



