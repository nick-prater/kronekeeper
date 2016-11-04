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
	'import/kris/dropdown',
	'backbone',
        'jquery',
	'jqueryui'
], function (
	dropdown
) {
        'use strict';

	var Wiretype_Model = Backbone.Model.extend({

		idAttribute: 'id',

		defaults: function() {
			return {
				id: null,
				wiretype_name: null,
				kris_colour_a: null,
				kris_colour_b: null,
				jumper_template_id: null,
			};
		}
	});


	var Wiretype_Collection = Backbone.Collection.extend({

		model: Wiretype_Model,
	});


	var Row_View = Backbone.View.extend({

		tagName: 'tr',
		className: 'wiretype',
		template: _.template( $('#row_template').html() ),

		initialize: function() {

		},

		render: function() {
			var json = this.model.toJSON();
			console.log(json);
			this.$el.html(this.template(json));

			/* Select jumper template */
			dropdown.initialise(
				this.$el.find("div.custom-select"),
				this.model.get("jumper_template_id")
			);

			return this;
		}
	});

	
	var Table_View = Backbone.View.extend({

		el: "#wiretype_table_body",

		render: function() {

			/* Show/hide empty table placeholder */
			if(this.collection.length) {
				this.$el.find("tr.empty_table").hide();
			}
			else {
				this.$el.find("tr.empty_table").show();
			}

			/* Render each table row in turn */
			this.collection.each(function(model) {
				var row = new Row_View({model: model});
				this.$el.append(row.render().$el);
			}, this);
		}
	});



	var wiretype_collection = new Wiretype_Collection(window.wiretypes);
	var table = new Table_View({collection: wiretype_collection});
	table.render();



	console.log("loaded import/kris/wiretype.js");
	console.log(wiretype_collection.length + " wiretypes initialised");
});



