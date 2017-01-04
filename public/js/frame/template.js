/* 
This file is part of Kronekeeper, a web based application for 
recording and managing wiring frame records.

Copyright (C) 2017 NP Broadcast Limited

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
	'util',
        'jquery',
	'jqueryui'
], function (
	util
) {
        'use strict';

	var jq_element;
	var block_id;

	function initialise() {

		/* Initialise dialog */
		var cancel_button = {
			text: "Cancel",
			icon: "ui-icon-close",
			click: function(e) {
				$(this).dialog("close");
			}
		};
		$("#dialog_pick_template").dialog({
			autoOpen: false,
			modal: true,
			buttons: [cancel_button],
			open: function() {
				/* Close dialog on Escape key, even if we don't have focus. */
				$(document).on("keydown", function(e) {
					console.log("Escape key pressed - closing dialog");
					$("#dialog_pick_template").dialog("close");
				});
			},
			close: function() {
				$(document).off("keydown");
			}
		});

		$("#dialog_pick_template a.template").click(handle_template_click);
	}


	function show_dialog(args) {

		jq_element = args.jq_element;
		block_id = args.block_id;
		$("#dialog_pick_template div.section").hide();
		$("#dialog_pick_template div.section.template_selection").show();
		$("#dialog_pick_template").dialog("open");
	}


	function handle_template_click(e) {
		
		var template_id = e.currentTarget.dataset.template_id;

		if(template_id) {
			$("#dialog_pick_template div.section.template_selection").hide();
			place_template(template_id, block_id);
		}
	}
	

	function place_template(template_id, block_id) {

		
		$("#dialog_pick_template div.section.messages div.message").hide();
		$("#pick_template_saving_message").show();
		$("#dialog_pick_template div.section.messages").show();

		$.ajax({
			url: "/api/frame/place_template",
			data: JSON.stringify({
				template_id: template_id,
				block_id: block_id
			}),
			method: 'POST',
			error: function(jq_xhr, status_text, error_text) {
				console.log("error placing template", status_text, error_text);
				$("#dialog_pick_template div.section.messages div.message").hide();
				$("#pick_template_error_message").show();
			},
			success: function(json, status_text, jq_xhr) {
				console.log("placed template");
				$("#dialog_pick_template").dialog("close");
				update_blocks(JSON.parse(json));
			}
		});
	}


	function update_blocks(blocks) {

		$.each(blocks, function(index, data) {
			var block = $("#block-" + data.id);
			block.removeClass("is_free");
			block.addClass("in_use");
			block.find("span.name").first().text(util.truncate(data.name, window.block_name_max_chars));
			block.find("div.block_type").first().text(data.block_type_name);
			block.attr("style", "background:" + data.html_colour);
		});
	}



	console.log("loaded frame/template.js");

	/* Expose public methods/properties */
	return {
		initialise: initialise,
		show_dialog: show_dialog
	};
});



