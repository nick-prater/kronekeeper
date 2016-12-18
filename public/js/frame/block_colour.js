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
        'jquery',
	'jqueryui'
], function (
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
		$("#dialog_change_colour").dialog({
			autoOpen: false,
			modal: true,
			buttons: [cancel_button],
		});

		$("#change_colour_selection button").click(handle_button_click);
		$("#custom_colour_change_link").click(show_colour_picker);
		$("#custom_block_colour_picker").change(handle_custom_colour_change);
	}


	function show_dialog(args) {

		/* Current colour can be specified as hex, or provided as a jquery css
		 * string in the form "rgb(123,123,123)", which we'll translate to hex
		 */
		if(!args.current_colour && args.current_rgb_text) {
			args.current_colour = rgb_text_to_hex(args.current_rgb_text);
		}

		jq_element = args.jq_element;
		block_id = args.block_id;
		$("#default_block_colour").css("background-color", args.default_colour);
		$("#custom_block_colour").css("background-color", args.current_colour);
		$("#custom_block_colour_picker").val(args.current_colour);
		$("#change_colour_selection").show();
		$("#change_colour_update_message").hide();
		$("#change_colour_error_message").hide();
		$("#dialog_change_colour").dialog("open");
	}

	function show_colour_picker(e) {
		$("#custom_block_colour_picker").trigger("click");
	}


	function handle_custom_colour_change(e) {
		console.log("custom colour changed");
		$("#custom_block_colour").attr("style", "background:" + $("#custom_block_colour_picker").val());
	}


	function handle_button_click(e) {

		var background_rgb = $(this).find("span").css("background-color");
		var html_colour = rgb_text_to_hex(background_rgb);

		/* Special Case to set default */
		if($(this).hasClass("default")) {
			console.log("setting block to default colour");
			html_colour = null;
		}

		$("#change_colour_selection").hide();
		$("#change_colour_update_message").show();

		$.ajax({
			url: "/api/block/" + block_id,
			data: JSON.stringify({
				html_colour: html_colour
			}),
			method: 'PATCH',
			error: function(jq_xhr, status_text, error_text) {
				console.log("error updating block_color", status_text, error_text);
				$("#change_colour_update_message").hide();
				$("#change_colour_error_message").show();
			},
			success: function(data, status_text, jq_xhr) {
				console.log("updated block colour");
				jq_element.css("background-color", background_rgb);
				$("#dialog_change_colour").dialog("close");
			}
		});
	}


	function rgb_text_to_hex(rgb) {
		var rgb = rgb.match(/^rgba?[\s+]?\([\s+]?(\d+)[\s+]?,[\s+]?(\d+)[\s+]?,[\s+]?(\d+)[\s+]?/i);
		var html_colour = (
			"#" + 
			("0" + parseInt(rgb[1],10).toString(16)).slice(-2) +
			("0" + parseInt(rgb[2],10).toString(16)).slice(-2) +
			("0" + parseInt(rgb[3],10).toString(16)).slice(-2)
		);
		return html_colour;
	}


	console.log("loaded frame/block_colour.js");

	/* Expose public methods/properties */
	return {
		initialise: initialise,
		show_dialog: show_dialog,
	};
});



