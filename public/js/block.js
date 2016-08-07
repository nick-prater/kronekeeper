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
	'block/circuit',
	'block/caption',
	'backbone',
        'jquery',
	'jqueryui'
], function (
	circuit,
	caption
) {
        'use strict';


	var Block_View = Backbone.View.extend({

		el: '#block_table_body',

		initialize: function() {
			this.listenTo(
				this.collection,
				'provision_jumper_fields',
				this.set_jumper_columns
			);
		},

		render: function() {
			this.collection.each(function(model) {
				var row = new circuit.view({model: model});
				this.$el.append(row.render().$el);
			}, this);

			/* The jumpers on each circuit are only rendered
			 * once all circuit row views have been instantiated, 
			 * so that if there's a circuit needing more than the
			 * initial 2 jumper cells, all circuit rows are able
			 * to respond. Otherwise we have a race condition.
			 */
			this.collection.trigger("table_structure_rendered");
			return this;
		},

		set_jumper_columns: function(column_count) {
			$('#jumper_heading').attr('colspan', column_count);
		}
	});


	var caption_view = new caption.view({
		model: new caption.model(window.block_info)
	});
	var circuit_list = new circuit.collection(null, {block_id: window.block_info.id});
	var block_view = new Block_View({collection: circuit_list});

	circuit_list.fetch({
		success: function(collection, response, options) {
			console.log("fetched circuit list OK");
			block_view.render();
		},
		error: function(collection, response, options) {
			alert("ERROR: failed to fetch circuit list");
		}
	});

	console.log("loaded block.js");
});



