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
	'frame/remove_block',
	'frame/title',
	'frame/frame_menu',
	'backbone',
        'jquery',
	'jqueryui'
], function (
	remove_block,
	title
) {
        'use strict';

	/* Keep track of the block we are associated with */
	var jq_block = null;
	

	/* Initialise the menus and associated events */
	$("#block_menu").menu({
		select: handle_block_menu_selection
	});
	$(".block .menu_button a").on("click", show_block_menu);


	function show_block_menu(e) {

		e.stopPropagation();

		/* Set global block_id - which block opened the menu? */
		jq_block = $(e.target).closest("td");

		set_allowed_menu_options( );
		$("#block_menu").menu("collapseAll", null, true);
		$("#block_menu").menu().show().position({
			my: "left top",
			at: "left bottom",
			of: this,
			collision: "fit flip"
		});

		/* Clicking outside the menu closes it */
		$(document).on("click", function() {
			$("#block_menu").menu().hide();
			$("#block_menu").menu("collapseAll", null, true);
		});
	};


	function set_allowed_menu_options() {

		enable_menu_action_if_true(
			"open",
			!jq_block.hasClass("is_free") && !jq_block.hasClass("unavailable")
		);
		enable_menu_action_if_true(
			"place_submenu",
			jq_block.hasClass("is_free") && !jq_block.hasClass("unavailable")
		);
		enable_menu_action_if_true(
			"remove",
			!jq_block.hasClass("is_free") && !jq_block.hasClass("unavailable")
		);
	}


	function enable_menu_action_if_true(action, t) {

		var selector = "li[data-action='" + action + "']";
		var elements = $("#block_menu").find(selector);

		if(t) {
			elements.removeClass("ui-state-disabled");
		}
		else {
			elements.addClass("ui-state-disabled");
		}
	}


	function handle_block_menu_selection(e, jq_element) {

		switch(e.currentTarget.dataset.action) {

			case "open" :
				jq_block.find("a.link")[0].click();
				break;
				
			case "place" :
				place_block(
					jq_block.data("block_id"),
					e.currentTarget.dataset.block_type
				);
				break;

			case "remove" :
				$("#block_menu").menu().hide();
				remove_block.activate({
					block_id: jq_block.data("block_id"),
					success: function () {
						jq_block.removeClass("in_use");
						jq_block.addClass("is_free");
						jq_block.find("span.name").first().text("unused");
						console.log("finished removing block");
					}
				});
				break;
		}

	}


	function place_block(block_id, block_type){

		console.log("placing", block_type, "at block_id", block_id);
		var url = '/api/frame/place_block';
		var data = {
			block_id: block_id,
			block_type: block_type
		};

		$.ajax({
			url: url,
			type: "POST",
			contentType: 'application/json; charset=utf-8',
			data: JSON.stringify(data),
			dataType: "json",
			success: function(json) {
				console.log("placed block ok");
				jq_block.removeClass("is_free");
				jq_block.addClass("in_use");
				jq_block.find("span.name").first().text("");
			},
			error: function(xhr, status) {
				var error_code = xhr.status + " " + xhr.statusText;
				alert("ERROR placing block: " + error_code);
			}
		});
	}



	var title_view = new title.view({
		model: new title.model(window.frame_info)
	});


	console.log("loaded frame.js");
});



