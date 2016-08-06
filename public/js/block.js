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
	'backbone',
        'jquery',
	'jqueryui'
], function (
	circuit
) {
        'use strict';


	var Block_Caption_Model = Backbone.Model.extend({

		urlRoot: '/api/block',
		defaults: {
			name: null
		}
	});


	var Block_Caption_View = Backbone.View.extend({

		el: '#block_table_caption',

		events: {
			'input' : 'highlight_change',
			'change' : 'save_caption',
			'keypress' : 'reset_on_escape_key'
		},

		initialize: function() {
			this.listenTo(
				this.model,
				'sync',
				this.model_synced
			);
		},

		highlight_change: function(e) {
			if(e.target.value != this.model.get("name")) {
				e.target.classList.add('change_pending');
			}
			else {
				e.target.classList.remove('change_pending');
			}
		},

		reset_on_escape_key: function(e) {
			if(e.keyCode == 27) {
				e.target.value = this.model.get("name");
				e.target.classList.remove('change_pending');
			}
		},

		save_caption: function(e) {
			var data = {
				name: e.target.value
			};

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
				highlight_element_change_applied(this.$el, "input.name");
			};
		}
	});


	var Block_View = Backbone.View.extend({

		el: '#block_table_body',

		initialize: function() {
			this.listenTo(
				this.collection,
				'reset',
				this.render
			);
			this.listenTo(
				this.collection,
				'provision_jumper_fields',
				this.set_jumper_columns
			);
		},

		render: function() {
			this.collection.each(function(model) {
				var row = new circuit.view({model: model});
				$(this.el).append(row.render().$el);
			}, this);
			this.collection.trigger("table_structure_rendered");
			return this;
		},

		set_jumper_columns: function(column_count) {
			$('#jumper_heading').attr('colspan', column_count);
		}
	});



	var caption_view = new Block_Caption_View({
		model: new Block_Caption_Model(window.block_info)
	});
	var circuit_list = new circuit.collection(null, {block_id: window.block_info.id});
	var block_view = new Block_View({collection: circuit_list});

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



