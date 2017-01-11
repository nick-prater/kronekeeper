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


require([
	'moment',
	'datatables.net'
], function (
	moment
) {
        'use strict';

	/* Table is hidden until it is processed by Data */
	$("#activity_log_table").on("init.dt", function () {
		console.log("table redrawn");
		$("#activity_log_table").show();
	});

	$("#activity_log_table").DataTable({
		serverSide: true,
		searching: false, /* Not yet implemented in our perl api */
		ordering: false,  /* Not yet implemented in our perl api */
		bAutoWidth: false,
		ajax: {
			url: "activity_log/query",
			type: "POST",
			data: function(d) {
				return JSON.stringify(d);
			}
		},
		columns: [
			{
				data: 'log_timestamp',
				render: function(data, type, row) {
					return moment.utc(data).fromNow();
				},
				className: "dt-left"
			},
			{
			 	data: 'by_person_name' 
			},
			{
				data: 'note',
				className: "dt-left"
			},
			{
				data: 'completed_by_person_id',
				render: function(data, type, row, meta) {
					var checked = data ? 'checked="checked" ' : '';
					return '<input type="checkbox" ' + checked + 'value="' + row.id + '" class="completed" />';
				},
				className: "dt-center",
				width: "5em"
			}
		],
		createdRow: function(row, data, index) {
			if(data.completed_by_person_id) {
				$(row).addClass("completed");
			}
			if(data.is_next_task) {
				$(row).addClass("next_task");
			}
		}
	});

	/* When table is redrawn, attach events to new rows */
	$("#activity_log_table").on("draw.dt", function () {
		console.log("draw.dt");
		$("input.completed").change(handle_checkbox_change);
	});


	function handle_checkbox_change(e) {

		var element = e.currentTarget;
		var activity_log_id = element.value;
		var checked = element.checked;

		console.log("checkbox changed for activity_log id:", activity_log_id, checked);

		$.ajax({
			url: "/api/activity_log/" + activity_log_id,
			method: 'PATCH',
			data: JSON.stringify({
				completed: checked
			}),
			error: function(jq_xhr, status_text, error_text) {
				console.log("error updating activity log", status_text, error_text);
				console.log("reversing state of checkbox");
				alert("Failed to update activity log", status_text, error_text);
				element.checked = !checked;
			},
			success: function(json, status_text, jq_xhr) {
				console.log("activity log updated");
				var data = JSON.parse(json);
				var tr = $(element).closest("tr");
				if(checked) {
					tr.removeClass("next_task");
					tr.addClass("completed");
				}
				else {
					tr.removeClass("completed");
				}

				/* Remove next_task highlight from all items */
				var tbody = $(element).closest("tbody");
				tbody.find("tr").removeClass("next_task");

				/* Then, highlight next_task if we have it and it's visible */
				if(data.next_item_id) {
					tbody.find("tr").has('input[value="' + data.next_item_id + '"]').addClass("next_task");
				}
			}
		});
	}



});
