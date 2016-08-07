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
	'block/jumper',
	'backbone',
        'jquery',
	'jqueryui'
], function (
	jumper
) {
        'use strict';


	var Circuit_Model = Backbone.Model.extend({

		idAttribute: 'circuit_id',
		urlRoot: '/api/circuit',

		defaults: {
			block_id: null,
			circuit_id: null,
			designation: null,
			name: null,
			cable_reference: null,
			connection: null,
			jumpers: []
		},

		initialize: function(attributes) {

			/* Handle the possibility that we have no jumpers */
			if(!attributes.jumpers) {
				attributes.jumpers = [];
			}

			/* Build a discrete model for each jumper, so we 
			 * can delete/patch/create these individually
			 */
			this.jumper_models = [];
			attributes.jumpers.forEach(function(jumper_data, index) {
				this.jumper_models.push(new jumper.model({
					data: jumper_data,
				},
				{
					parse: true,
					circuit: this
				}));
			}, this);

			this.listenTo(
				this.collection,
				"circuit_jumper_change",
				this.jumper_changed
			);
			this.listenTo(
				this,
				"loaded_jumper_data",
				this.display_jumper_data
			);
		},

		jumper_changed: function(changed_circuit_id) {

			if(changed_circuit_id == this.get("circuit_id")) {
				this.reload_jumpers();
			}
		},

		reload_jumpers: function() {

			var circuit_model = this;
			var circuit_id = this.get("circuit_id");
			var url = '/api/circuit/' + circuit_id + '/jumpers';
			var data = {
				circuit_id: this.get("circuit_id")
			};

			$.ajax({
				url: url,
				type: "GET",
				dataType: "json",
				success: function(json) {
					console.log("jumper data loaded OK");
					circuit_model.trigger("loaded_jumper_data", json);
				},
				error: function(xhr, status) {
					var error_code = xhr.status + " " + xhr.statusText;
					console.log("failed to reload jumper data:", error_code);
				}
			});
		},

		display_jumper_data: function(data) {

			var jumpers = this.jumper_models;
			console.log("cells_needed:", jumpers.length);
			console.log("jumpers:", jumpers);

			data.jumpers.forEach(function(jumper_data) {

				/* Is this jumper already displayed?
				 * nothing to do if so - at present we don't update jumpers,
				 * we delete and add new for any changes
				 */
				var jumper_model = this.jumper_model_by_id(jumper_data.jumper_id);
				if(jumper_model) {
					console.log("already have jumper_id", jumper_data.jumper_id);
					jumper_model.set(
						jumper_model.parse({data: jumper_data})
					);
				}
				else {
					console.log("adding new jumper_id", jumper_data.jumper_id);

					/* Is there an existing model we can populate? */
					var jumper_model = this.get_empty_jumper_model();

					if(jumper_model) {
						console.log("cells_needed pre-populate-existing:", jumpers.length);
						console.log("populating existing jumper model");
						jumper_model.set(
							jumper_model.parse({data: jumper_data})
						);
						console.log("cells_needed after populate-existing:", jumpers.length);
					}
					else {
						console.log("No empty jumper models found - adding one");

						jumper_model = new jumper.model({
							data: jumper_data,
						},
						{
							parse: true,
							circuit: this
						});
						this.jumper_models.push(jumper_model);
					}
				}
			}, this);

			this.trigger("render_jumpers_request");
		},

		jumper_model_by_id: function(wanted_jumper_id) {

			/* Returns the jumper model having the given jumper_id */
			return this.jumper_models.find(function(jumper_model) {
				return wanted_jumper_id == jumper_model.get("id");
			});
		},

		get_empty_jumper_model: function() {

			/* Returns the first unpopulated jumper model, or undef if none */
			return this.jumper_models.find(function(jumper_model) {
				return !jumper_model.get("id");
			});
		}
		

	});



	var Circuits_Collection = Backbone.Collection.extend({

		model: Circuit_Model,
		url: function() {
			return '/api/block/' + this.block_id;
		},

		initialize: function(models, options) {
			this.block_id = options.block_id;
		},

		parse: function(data) {
			return data.circuits;
		},

		provision_jumper_fields: function(required_count) {
			/* This routine will ensure at least the specified
			 * number of jumper field cells are available. This
			 * collection keeps track of how many should be
			 * provided, but delegates their creation to views
			 * which listen to the provision_jumper_fields event.
			 */
			this.trigger("provision_jumper_fields", this.jumper_count);
		}
	});



	var Circuit_View = Backbone.View.extend({

		tagName: 'tr',
		className: 'circuit',

		events: {
			'click a.add_jumper' : 'add_jumper',
			'input .circuit_name input' : 'circuit_name_input',
			'change .circuit_name input' : 'circuit_name_change',
			'keypress .circuit_name input' : 'circuit_name_keypress',
			'input .cable_reference input' : 'cable_reference_input',
			'change .cable_reference input' : 'cable_reference_change',
			'keypress .cable_reference input' : 'cable_reference_keypress',
			'input .connection input' : 'connection_input',
			'change .connection input' : 'connection_change',
			'keypress .connection input' : 'connection_keypress'
		},

		initialize: function() {
			this.listenTo(
				this.model,
				'sync',
				this.model_synced
			);
			this.listenTo(
				this.model.collection,
				"table_structure_rendered",
				this.render_jumpers
			);
			this.listenTo(
				this.model.collection,
				"provision_jumper_fields",
				this.provision_jumper_fields
			);
			this.listenTo(
				this.model,
				"render_jumpers_request",
				this.render_jumpers
			);
		},

		template: _.template( $('#row_template').html() ),

		render: function() {
			/* Jumpers are populated once the basic table
			 * structure is in place so that we can handle
			 * any requirement for extra columns without
			 * race conditions.
			 */
			var json = this.model.toJSON();
			this.$el.html(this.template(json));
			return this;
		},

		render_jumpers: function() {

			console.log("render_jumpers()");

			/* This is called during initialisation to bulk-render all jumpers for the circuit */
			var jumpers = this.model.jumper_models;

			console.log("cells_needed:", jumpers.length);
			console.log("jumpers:", jumpers);

			/* Ensure we have enough blank cells for all jumpers */
			var cells_needed = jumpers.length;
			while(this.$el.children("td.jumper").not(".inactive").size() < cells_needed) {
				this.add_jumper();
			}

			/* Populate the cells */
			var circuit_model = this.model;
			this.$el.children("td.jumper").not(".inactive").each(function(index, cell) {
				if(!jumpers[index]) {
					jumpers[index] = new jumper.model(null, {circuit:circuit_model});
				}
				//TODO we're creating a new view here... why not re-render an existing view?
				var view = new jumper.view({
					model: jumpers[index]
				});
				$(cell).replaceWith(view.render().$el);
			});
		},

		add_jumper: function(e) {

			var inactive_cell_count = this.$el.children("td.jumper.inactive").size();

			if(inactive_cell_count < 1) {
				/* Need to provision another column */
				var jumper_cell_count = this.$el.children("td.jumper").size();
				this.model.collection.trigger(
					"provision_jumper_fields",
					jumper_cell_count + 1
				);
			}

			/* Activate an inactive cell */
			var jumper_model = new jumper.model(null, {circuit:this.model});
			this.model.jumper_models.push(jumper_model);
			var view = new jumper.view({
				model: jumper_model
			});
			this.$el.children("td.jumper.inactive").first().replaceWith(view.render().$el);
		},

		circuit_name_keypress: function(e) {
			this.reset_on_escape_key(e, 'name');
		},

		cable_reference_keypress: function(e) {
			this.reset_on_escape_key(e, 'cable_reference');
		},

		connection_keypress: function(e) {
			this.reset_on_escape_key(e, 'connection');
		},

		reset_on_escape_key: function(e, attribute_name) {
			if(e.keyCode == 27) {
				e.target.value = this.model.get(attribute_name);
				e.target.parentNode.classList.remove('change_pending');
			}
		},


		circuit_name_input: function(e) {
			this.highlight_change(e, 'name');
		},

		cable_reference_input: function(e) {
			this.highlight_change(e, 'cable_reference');
		},

		connection_input: function(e) {
			this.highlight_change(e, 'connection');
		},

		highlight_change: function(e, attribute_name) {
			if(e.target.value != this.model.get(attribute_name)) {
				e.target.parentNode.classList.add('change_pending');
			}
			else {
				e.target.parentNode.classList.remove('change_pending');
			}
		},


		circuit_name_change: function(e) {
			this.save_data({name: e.target.value});
		},

		cable_reference_change: function(e) {
			this.save_data({cable_reference: e.target.value});
		},

		connection_change: function(e) {
			this.save_data({connection: e.target.value});
		},

		save_data: function(data) {
			this.model.save(data, {
				patch: true,
				success: function(model, response, options) {
					console.log("circuit data saved");
				},
				error: function(model, xhr, options) {
					console.log("ERROR saving circuit data");
				}
			});
		},


		model_synced: function(model, response, options) {
			/* Clear field highlighting and flash green to indicate successful save
			 * Server returns the changed fields to confirm which have been updated
			 */
			if('name' in response) {
				highlight_element_change_applied(this.$el, "td.circuit_name");
			}
			if('cable_reference' in response) {
				highlight_element_change_applied(this.$el, "td.cable_reference");
			}
			if('connection' in response) {
				highlight_element_change_applied(this.$el, "td.connection");
			}
		},

		provision_jumper_fields: function(required_count) {

			var jumper_cell_count = this.$el.children("td.jumper").size();
			var td_buttons = this.$el.children("td.circuit_buttons").first();
			var template = $('#inactive_jumper_cell_template').html();

			while(jumper_cell_count < required_count) {
				/* Insert new cell in row before the buttons */
				td_buttons.before(template);
				jumper_cell_count ++;
			}
		}

	});

	console.log("loaded circuit.js");

	/* Expose public methods */
	return {
		model: Circuit_Model,
		view: Circuit_View,
		collection: Circuits_Collection
	};

});



