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
	'block/highlight',
	'backbone',
        'jquery',
	'jqueryui'
], function (
	jumper,
	highlight
) {
        'use strict';


	var Circuit_Model = Backbone.Model.extend({

		idAttribute: 'circuit_id',
		urlRoot: '/api/circuit',

		defaults: function() {
			return {
				block_id: null,
				circuit_id: null,
				designation: null,
				name: null,
				cable_reference: null,
				connection: null,
				jumpers: []
			};
		},

		initialize: function(attributes) {

			this.jumper_models = [];

			/* Handle the possibility that we have no jumpers */
			if(!attributes.jumpers) {
				console.log("WARNING: no jumpers passed to initialize circuit");
				attributes.jumpers = [];
			}

			/* Build a discrete model for each jumper, so we 
			 * can delete/patch/create these individually
			 */
			attributes.jumpers.forEach(function(jumper_data, index) {
				var jumper_model = new jumper.model({
					data: jumper_data,
				},
				{
					parse: true,
					circuit: this
				});
				this.jumper_models.push(jumper_model);
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

			console.log(
				"circuit model initialised for circuit", this.id,
				"with", this.jumper_models.length, "jumper models"
			);
		},

		jumper_changed: function(changed_circuit_id) {

			/* Triggered whenever jumpering is changed elsewhere on
			 * our block. If our circuit is affected, something has
			 * changed in our jumper connections, so we need to reload
			 */
			if(changed_circuit_id == this.id) {
				this.reload_jumpers();
			}
		},

		reload_jumpers: function() {

			console.log("reloading jumpers for circuit", this.id);

			var circuit_model = this;
			var url = '/api/circuit/' + this.id + '/jumpers';
			var data = {
				circuit_id: this.id
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
			'click a.add_jumper'              : 'add_jumper',
			'input .circuit_name input'       : function(e) {this.highlight_change(e, 'name')},
			'input .cable_reference input'    : function(e) {this.highlight_change(e, 'cable_reference')},
			'input .connection input'         : function(e) {this.highlight_change(e, 'connection')},
			'keypress .circuit_name input'    : function(e) {this.handle_keypress(e, 'name')},
			'keypress .cable_reference input' : function(e) {this.handle_keypress(e, 'cable_reference')},
			'keypress .connection input'      : function(e) {this.handle_keypress(e, 'connection')},
			'change .circuit_name input'      : function(e) {this.save_data({name: e.target.value})},
			'change .cable_reference input'   : function(e) {this.save_data({cable_reference: e.target.value})},
			'change .connection input'        : function(e) {this.save_data({connection: e.target.value})}
		},

		initialize: function() {

			/* Keep track of component sub-views */
			this.jumper_views = [];

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
			/* Jumpers are populated later, once the basic
			 * table structure is in place so that we can
			 * handle any requirement for extra columns
			 * without race conditions.
			 */
			var json = this.model.toJSON();
			this.$el.html(this.template(json));
			return this;
		},

		render_jumpers: function() {

			console.log("render_jumpers()");

			/* Typically a circuit has two jumper fields, but it can have more
			 * Ensure we have enough blank cells for every jumper model
			 */
			var jumper_models = this.model.jumper_models;
			var jumper_views = this.jumper_views;
			var cells_needed = jumper_models.length;
			while(this.$el.children("td.jumper").not(".inactive").size() < cells_needed) {
				this.add_jumper();
			}

			/* Populate the cells */
			var circuit_model = this.model;
			this.$el.children("td.jumper").not(".inactive").each(function(index, cell) {

				console.log("populating jumper cell index");

				/* By default we have two jumper cells for each circuit, but the circuit
				 * may have fewer, even none. If so, we initialise empty jumper models
				 * and render associated views to fill the cells.
				 */
				if(!jumper_models[index]) {
					jumper_models[index] = new jumper.model(null, {circuit:circuit_model});
				}
				if(!jumper_views[index]) {
					jumper_views[index] = new jumper.view( {model: jumper_models[index]} );
					jumper_views[index].setElement(cell);
				}

				jumper_views[index].render();
			});
		},

		add_jumper: function(e) {

			/* Add an active jumper cell.
			 * First see if there is an inactive cell to which we can assign
			 * a model and view. (An inactive cell is an existing table cell
			 * which is greyed-out and has neither model or view associated).
			 * If there are no inactive cells in this table row, we expand
			 * the table to add an active jumper cell to this row and an
			 * inactive table cell to every other circuit row.
			 */

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
			this.$el.children("td.jumper.inactive").first().removeClass("inactive");
			this.render_jumpers();
		},

		handle_keypress: function(e, attribute_name) {
			if(e.keyCode == 27) {
				e.target.value = this.model.get(attribute_name);
				e.target.parentNode.classList.remove('change_pending');
			}
		},

		highlight_change: function(e, attribute_name) {
			if(e.target.value != this.model.get(attribute_name)) {
				e.target.parentNode.classList.add('change_pending');
			}
			else {
				e.target.parentNode.classList.remove('change_pending');
			}
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
				highlight.element_change_applied(this.$el, "td.circuit_name");
			}
			if('cable_reference' in response) {
				highlight.element_change_applied(this.$el, "td.cable_reference");
			}
			if('connection' in response) {
				highlight.element_change_applied(this.$el, "td.connection");
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



