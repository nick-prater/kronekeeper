/* 
This file is part of Kronekeeper, a web based application for 
recording and managing wiring frame records.

Copyright (C) 2020 NP Broadcast Limited

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
	'dropdown',
	'backbone',
        'jquery',
	'jqueryui'
], function (
	dropdown
) {
        'use strict';

	var wire_collection;

	var Wire_Model = Backbone.Model.extend({
		idAttribute: 'id',
		defaults: function() {
			return {
				id: null,
				colour_id: null
			};
		}
	});

	var Wire_Collection = Backbone.Collection.extend({
		model: Wire_Model,
	});

	var Wire_View = Backbone.View.extend({
		tagName: 'li',
		className: 'wire',
		template: _.template( $('#wire_template').html() ),
		events: {
			"click a.button.remove_wire" : "remove_wire"
		},
		render: function() {
			let model = this.model;
			this.$el.html(this.template());

			/* Select jumper template */
			dropdown.initialise(this.$el.find("div.custom-select"), {
				initial_value: model.get("colour_id"),
				on_change: function(value) {
					model.set("colour_id", value);
				}
			});

			return this;
		},
		remove_wire: function(e) {
			e.preventDefault();
			this.remove();
		}
	});
	
	var List_View = Backbone.View.extend({

		el: "#wire_list",

		render: function() {
			/* Render each wire item in turn */
			this.collection.each(function(model) {
				this.add_wire(model);
			}, this);
		},

		initialize: function() {
			this.collection.on("add", (model, collection, options) => {
				this.add_wire(model);
			});
		},

		add_wire: function(wire_model) {
			let wire = new Wire_View({model: wire_model});
			let wire_element = wire.render().$el;

			/* Last element in the list is an 'add wire' button,
			 * so we need to insert the new wire before that, rather
			 * than just appending it to the end of the list.
			 */
			wire_element.insertBefore(this.$el.find("li:last-child"));
		}
	});


	function initialise() {	
		wire_collection = new Wire_Collection(window.wires);
		let list = new List_View({collection: wire_collection});
		list.render();
		console.log(wire_collection.length + " wires initialised");
		return wire_collection;
	};

	function add_wire() {
		console.log("adding wire");
		var r = wire_collection.add([{}]);
	};

	function colours () {
		/* Returns an ordered array of the wire colour ids */
		let models = wire_collection.toJSON();
		return models.map((model) => {
			return model.colour_id;
		});
	}


	console.log("loaded jumper_template/wire.js");

	/* Exports */
	return {
		add_wire: add_wire,
		colours: colours,
		initialise: initialise
	};

});



