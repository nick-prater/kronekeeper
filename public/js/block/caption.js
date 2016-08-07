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
	'block/highlight',
	'backbone',
        'jquery',
	'jqueryui'
], function (
	highlight
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
				highlight.element_change_applied(this.$el, "input.name");
			};
		}
	});


	console.log("loaded block/caption.js");

	/* Expose public methods/properties */
	return {
		model: Block_Caption_Model,
		view: Block_Caption_View
	};
});



