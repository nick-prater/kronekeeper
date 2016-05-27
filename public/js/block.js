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
        'jquery'
], function (

) {
        'use strict';



	var Circuit_Model = Backbone.Model.extend({

		idAttribute: 'circuit_id',

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

		initialize: function() {
			// Event listeners to follow here
		},

		template: _.template( $('#row_template').html() ),

		render: function() {
			var json = this.model.toJSON();
			json.jumper_text = json.jumpers.join('; ');
			this.$el.html(this.template(json));
			return this;
		}
	});


	var Block_View = Backbone.View.extend({

		el: '#block_table_body',

		initialize: function() {
			this.listenTo(this.collection, 'sync', this.render);
			this.collection.fetch();
		},

		render: function() {

			this.collection.each(function(model) {
				var row = new Circuit_View({model: model});
				$('#block_table_body').append(row.render().$el);

			}, this);

			return this;
		}
	});



	var circuit_list = new Circuits_Collection({block_id: window.block_id});
	var view = new Block_View({collection: circuit_list});

	console.log("loaded block.js");

});



