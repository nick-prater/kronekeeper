/* 
This file is part of Kronekeeper, a web based application for 
recording and managing wiring frame records.

Copyright (C) 2020 NP Broadcast Limited

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
	'backbone',
        'jquery',
	'jqueryui'
], function (
) {
        'use strict';

	function remove_block_position(params) {

		console.log("removing position of block_id %i", params.block_id);
		var url = '/api/frame/remove_block_position';
		var data = {
			block_id: params.block_id
		};

		$.ajax({
			url: url,
			type: "POST",
			contentType: 'application/json; charset=utf-8',
			data: JSON.stringify(data),
			dataType: "json",
			success: function(json) {
				console.log("removed block position ok");
				params.success();
			},
			error: function(xhr, status) {
				var error_code = xhr.status + " " + xhr.statusText;
				alert("ERROR removing block position: " + error_code);
			}
		});
	}


	function create_block_position(params) {

		console.log("enabling position of block_id %i", params.block_id);
		var url = '/api/frame/enable_block_position';
		var data = {
			block_id: params.block_id
		};

		$.ajax({
			url: url,
			type: "POST",
			contentType: 'application/json; charset=utf-8',
			data: JSON.stringify(data),
			dataType: "json",
			success: function(json) {
				console.log("enabled block position ok");
				params.success();
			},
			error: function(xhr, status) {
				var error_code = xhr.status + " " + xhr.statusText;
				alert("ERROR enabling block position: " + error_code);
			}
		});
	}


	console.log("loaded block_position.js");

	/* Exports */
	return {
		remove: remove_block_position,
		create: create_block_position
	};
});
