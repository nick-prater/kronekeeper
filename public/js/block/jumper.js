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
	'block/highlight',
	'backbone',
        'jquery',
	'jqueryui'
], function (
	jumper_select,
	highlight
) {
        'use strict';


	var Jumper_Model = Backbone.Model.extend({

		defaults: function() {
			return {
				designation: null,
				id: null,
				is_simple_jumper: false,
				wires: []
			};
		},

		initialize: function(attributes, options) {
			this.circuit = options.circuit;
		},

		parse: function(response, options) {

			var data = response.data;

			/* Sanity check - a jumper should always have at least one wire */
			if(!(data.wires.length >= 1)) {
				alert("ERROR: jumper has no associated wires, therefore no connections!");
			}

			/* Assumption is that all wires lead to the same destination circuit
			 * We've no UI to create a jumper other than this, but still, we trap this
			 * in case we do something crazy in future and forget to update this part of the UI
			 */
			var mismatched_wire = data.wires.find(function(wire) {
				return (wire.b_circuit_id != data.wires[0].b_circuit_id);
			});
			if(mismatched_wire) {
				alert(
					"UNEXPECTED CONDITION: jumper has wires terminating on " +
					"different circuits. Not all connections are shown"
				);
			}

			/* This is the data finally used to construct the new Model */
			return {
				id: data.jumper_id,
				is_simple_jumper: data.is_simple_jumper,
				wires: data.wires,
				designation: data.wires[0].b_circuit_full_designation,
				destination_block_id: data.wires[0].b_block_id,
				destination_circuit_id: data.wires[0].b_circuit_id
			};
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
			'keydown' : 'handle_keydown',
			'dblclick' : 'handle_double_click',
			'hashchange' : 'handle_hash_change'
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

			var view = this;

			/* Bind to window events to handle highlighting. If
			 * this view is ever destroyed, we need to take care to
			 * unbind them
			 */
			$(window).on("hashchange", function(e) {
				view.handle_hash_change(e);
			});
			$(window).on("click", function(e) {
				view.remove_highlighting(e);
			});
			$(window).on("keydown", function(e) {
				view.remove_highlighting(e);
			});
		},
	
		render: function() {
			console.log("jumper", this.model.id, "render on circuit", this.model.circuit.id);
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

		handle_keydown: function(e) {

			switch(e.keyCode) {

				case 27:
					// Escape - reset to original value
					e.target.value = this.model.get("designation");
					e.target.parentNode.classList.remove('change_pending');
					break;

				case 38:
					// Up Arrow
					this.move_focus(e, "up");
					break;

				case 40:
					// Down Arrow
					this.move_focus(e, "down");
					break;
			}
		},

		move_focus: function(e, direction) {

			var td = $(e.target).closest("td");
			var tr = td.closest("tr");
			var index = tr.find("td").index(td);

			tr = direction == "up" ? tr.prev()
			                       : tr.next();

			var columns = tr.find("td");
			$(columns[index]).find("input").focus();
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
					jumper_id: this.model.id,
					destination_designation: e.target.value,
					cancel_action: function() {
						console.log("cancel action");
						e.target.value = jumper_view.model.get("designation");
						jumper_view.el.classList.remove('change_pending');
						jumper_view.$el.effect("highlight", {}, highlight.duration);
					},
					success_action: function(data) {
						console.log("success action: ", data);

						if(data.deleted_jumper_id) {
							/* Propagate deletion to other jumpers displayed on this block */
							jumper_view.model.circuit.collection.trigger("jumper_deleted", data.deleted_jumper_id);
						}

						/* Update our own model and re-render */
						jumper_view.model.set(
							jumper_view.model.parse({
								data: data.jumper_info
							})
						);

						jumper_view.el.classList.remove('change_pending');
						jumper_view.render();
						jumper_view.$el.effect("highlight", highlight.green, highlight.duration);

						/* Trigger update and re-render for other affected circuits */
						propagate_circuit_changes(data.jumper_info.wires);
					}
				});

				function propagate_circuit_changes(wires) {

						/* Build list of changed circuits, so we only trigger one event for each */
						var changed_circuits = [];
						wires.forEach(function(wire) {

							/* Don't trigger an event on ourselves */
							if(wire.b_circuit_id != wire.a_circuit_id) {
								changed_circuits[wire.b_circuit_id] = true;
							}
						});

						/* Trigger an event for each affected circuit, so they can reload their jumper models */
						changed_circuits.forEach(function(changed, circuit_id) {
							console.log("propagating jumper change for circuit_id ", circuit_id);
							jumper_view.model.circuit.collection.trigger("circuit_jumper_change",circuit_id);
						});
				}
			}
		},

		jumper_remove: function() {

			this.model.destroy({
				success: function(model, response, options) {
					console.log("jumper removed OK");
					model.circuit.collection.trigger("jumper_deleted", model.id);
				},
				error: function(model, response, options) {
					console.log("ERROR removing jumper");
					alert("ERROR removing jumper");
				}
			});
		},

		jumper_deleted: function(deleted_jumper_id) {

			/* Event handler that responds to another jumper being deleted.
			 * If we are the other end of the deleted jumper, we'll have the
			 * same id, but the text input field won't have been cleared.
			 */
			if(deleted_jumper_id == this.model.id) {
				console.log("jumper_deleted on circuit_id:", this.model.circuit.id, "jumper_id:", this.model.id);
				this.model.set(this.model.defaults());
				this.render();
				this.model_synced();
			}
		},

		model_synced: function(model, response, options) {
			/* Clear field highlighting and flash green to indicate successful save
			 * Server returns the changed fields to confirm which have been updated
			 */
			console.log("jumper model synced");
			this.$el.removeClass('change_pending');
			this.$el.effect("highlight", highlight.green, highlight.duration);
		},

		handle_double_click: function(e) {
			/* Load and highlight the other end of the double-clicked jumper. */
			if(this.model.id) {
				window.location.href = (
					"/block/" + this.model.get("destination_block_id") +
				        "#jumper_id=" + this.model.id
				);
			}
		},

		handle_hash_change: function(e) {
			if(window.location.hash == ("#jumper_id=" + this.model.id)) {
				this.$el.addClass("highlight");
			}
		},

		remove_highlighting: function(e) {
			this.$el.removeClass("highlight");
			if(window.location.hash == ("#jumper_id=" + this.model.id)) {
				window.location.hash = "";
			}
		}
	});


	console.log("loaded block/jumper.js");

	/* Expose public methods */
	return {
		model: Jumper_Model,
		view: Jumper_View
	};
});



