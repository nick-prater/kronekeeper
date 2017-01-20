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
        'jquery'
], function (
) {
        'use strict';


	function completely_visible(element) {

		/* Is element completely visible? */
		var jq_window = $(window);
		var viewport = {
			top:    jq_window.scrollTop(),
			bottom: jq_window.scrollTop() + jq_window.height() ,
			left:   jq_window.scrollLeft(),
			right:  jq_window.scrollLeft() + jq_window.width()
		};

		var bounds = element.offset();
		bounds.right = bounds.left + element.outerWidth();
		bounds.bottom = bounds.top + element.outerHeight();
		bounds.left = bounds.left;
		bounds.top = bounds.top;

		console.log("checking position of element");
		console.log("viewport:", viewport);
		console.log("element bounds:", bounds);

		/* Is any part of selected element off-screen */
		return !(
			bounds.left < viewport.left     ||
			bounds.right > viewport.right   ||
			bounds.top < viewport.top       ||
			bounds.bottom > viewport.bottom
		);
	}


	function to_centre(element) {
		console.log("scrolling to centre element");
		$('html,body').scrollTop(element.offset().top - ($(window).height() - element.outerHeight(true)) / 2);
		$('html,body').scrollLeft(element.offset().left - ($(window).width() - element.outerWidth(true)) / 2);
	}


	return {
		completely_visible: completely_visible,
		to_centre: to_centre
	};

});


