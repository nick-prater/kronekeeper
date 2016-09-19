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

	var highlight_green = {
		color: '#00ff00'
	};

	var highlight_duration = 1000;

	function highlight_element_change_applied(jq_context, selector) {
		var element = jq_context.children(selector);
		element.removeClass('change_pending');
		element.effect("highlight", highlight_green, highlight_duration);
	}

	function highlight_link(jq_context, selector) {
		var original_background_colour = jq_context.find(selector).css("background-color");
		jq_context.find(selector)
		          .css("background-color", highlight_green.color)
		          .animate({backgroundColor: original_background_colour}, highlight_duration);
	}

	console.log("loaded highlight.js");

	return {
		element_change_applied: highlight_element_change_applied,
		link_change_applied: highlight_link,
		green: highlight_green,
		duration: highlight_duration
	};
});



