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
	'block/loading_overlay',
	'backbone',
        'jquery',
	'jqueryui'
], function (
	highlight,
	loading_overlay
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
			'input .name' : 'highlight_change',
			'change .name' : 'save_caption',
			'keypress .name' : 'reset_on_escape_key',
			'change #block_select' : 'block_selection_changed',
			'change #vertical_select' : 'vertical_selection_changed',
			'click a.block_navigation' : 'navigate_block'
		},

		initialize: function() {
			this.listenTo(
				this.model,
				'sync',
				this.model_synced
			);
			this.populate_block_select({
				selected_id: window.block_info.id
			});

			var view = this;
			$(document).bind("keydown", function(e) {
				view.handle_keydown(e)
			});
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
		},

		populate_block_select: function(args) {
			console.log("populating block selection");

			/* Get current vertical selection */
			var selected_vertical_id = $("#vertical_select").val();
			var vertical;
			$.each(blocks, function(index, value) {
				if(value.id == selected_vertical_id) {
					vertical = value;
					return false;  //break loop
				}
			});

			/* Clear existing block selection */
			var block_select = $('#block_select');
			block_select.children().remove();

			/* Populate with new selection - in Kronekeeper, each
			 * vertical can have a different number of blocks.
			 * The blocks we have are sorted by position index, which
			 * always runs from bottom-to-top.
			 */
			$.each(vertical.blocks, function(index, block) {
				var option = $("<option />").val(block.id).text(block.designation);
				option.attr("data-position", block.position);
				if( 
				    (args.selected_id && (block.id == args.selected_id)) ||
				    (args.selected_position && (block.position == args.selected_position))
				) {
					option.attr("selected", "selected");
				};
				block_select.prepend(option);
			});
		},

		handle_keydown: function(e) {
			if(e.shiftKey) {
				if(e.keyCode == 40) {
					// SHIFT-ARROW_DOWN
					this.select_next_option("#block_select");
					return false;
				}
				else if(e.keyCode == 38) {
					// SHIFT-ARROW_UP
					this.select_prev_option("#block_select");
					return false;
				}
				else if(e.keyCode == 37) {
					// SHIFT-ARROW_LEFT
					this.select_prev_option("#vertical_select");
					return false;
				}
				else if(e.keyCode == 39) {
					// SHIFT-ARROW_RIGHT
					this.select_next_option("#vertical_select");
					return false;
				}
			}
		},

		navigate_block: function(e) {
			var target = $(e.currentTarget);
			if(target.hasClass("down")) {
				this.select_next_option("#block_select");
			}
			else if(target.hasClass("up")) {
				this.select_prev_option("#block_select");
			}
			else if(target.hasClass("left")) {
				this.select_prev_option("#vertical_select");
			}
			else if(target.hasClass("right")) {
				this.select_next_option("#vertical_select");
			}
			return false;
		},

		vertical_selection_changed: function() {
			console.log("vertical selection changed");

			/* Find position of currently selected block */
			var selected_block_item = $("#block_select > option:selected");
			var block_position = selected_block_item.attr("data-position") || 1;
			console.log("block_position", block_position);

			/* Kronekeeper verticals can differ in the available blocks, so
			 * we have to re-populate the block selection whenever the vertical
			 * changes
			 */
			this.populate_block_select({
				selected_position: block_position
			});

			$("#block_select").trigger("change");
		},

		block_selection_changed: function() {
			console.log("block selection changed");
			var selected_block_id = $('#block_select').val();
			console.log("loading block", selected_block_id);
			loading_overlay.show();
			location.assign("/block/" + selected_block_id);
		},

		select_next_option: function(option_selector) {
			var selected_item = $(option_selector + " > option:selected");
			var next_item = selected_item.next();

			if(selected_item && next_item.html()) {
				selected_item.prop("selected", false);
				next_item.prop("selected", true);
			}
			$(option_selector).trigger("change");
		},

		select_prev_option: function(option_selector) {
			var selected_item = $(option_selector + " > option:selected");
			var prev_item = selected_item.prev();

			if(selected_item && prev_item.html()) {
				selected_item.prop("selected", false);
				prev_item.prop("selected", true);
			}
			$(option_selector).trigger("change");
		}

	});


	console.log("loaded block/caption.js");

	/* Expose public methods/properties */
	return {
		model: Block_Caption_Model,
		view: Block_Caption_View
	};
});



