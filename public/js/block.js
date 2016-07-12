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



	var Circuit_Model = Backbone.Model.extend({

		idAttribute: 'circuit_id',
		urlRoot: '/api/circuit',

		defaults: {
			block_id: null,
			circuit_id: null,
			designation: null,
			name: null,
			cable_reference: null,
			jumpers: []
		}

	});


	var Circuits_Collection = Backbone.Collection.extend({

		model: Circuit_Model,
		url: function() {
			return '/api/block/' + this.block_id;
		},

		initialize: function(args) {
			this.block_id = args.block_id;
		},

		parse: function(data) {
			return data.circuits;
		}
	});


	var Circuit_View = Backbone.View.extend({

		tagName: 'tr',
		className: 'circuit',

		events: {
			'click a.add_jumper' : 'add_jumper',
			'input .circuit_name input' : 'circuit_name_input',
			'change .circuit_name input' : 'circuit_name_change',
			'input .cable_reference input' : 'cable_reference_input',
			'change .cable_reference input' : 'cable_reference_change'
		},

		initialize: function() {
			this.listenTo(this.model, 'sync', this.model_synced);
		},

		template: _.template( $('#row_template').html() ),

		render: function() {
			var json = this.model.toJSON();
			json.jumper_text = json.jumpers.join('; ');
			this.$el.html(this.template(json));
			return this;
		},

		add_jumper: function(e) {
			console.log("Add jumper");
			console.log(e);
		},


		circuit_name_input: function(e) {
			this.highlight_change(e, 'name');
		},

		cable_reference_input: function(e) {
			this.highlight_change(e, 'cable_reference');
		},

		highlight_change: function(e, attribute_name) {
			if(e.target.value != this.model.attributes[attribute_name]) {
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
			/* Clear field highlighting and flash green to indicate successful save */
			if('name' in response) {
				this.$el.find("td.circuit_name").removeClass('change_pending');
				this.$el.find("td.circuit_name").effect("highlight", {color: "#deffde"}, 500);
			};
			if('cable_reference' in response) {
				this.$el.find("td.cable_reference").removeClass('change_pending');
				this.$el.find("td.cable_reference").effect("highlight", {color: "#deffde"}, 500);
			};

		}

	});


	var Block_View = Backbone.View.extend({

		el: '#block_table_body',

		initialize: function() {
			this.listenTo(this.collection, 'reset', this.render);
		},

		render: function() {
			console.log("rendering Block_View");
			this.collection.each(function(model) {
				//console.log(model);
				var row = new Circuit_View({model: model});
				$('#block_table_body').append(row.render().$el);

			}, this);

			return this;
		}
	});



	var circuit_list = new Circuits_Collection({block_id: window.block_id});
	var view = new Block_View({collection: circuit_list});

	circuit_list.fetch({
		reset: true,
		success: function(collection, response, options) {
			console.log("fetched circuit list OK");
		},
		error: function(collection, response, options) {
			console.log("ERROR: failed to fetch circuit list");
		}
	});

	console.log("loaded block.js");

});



