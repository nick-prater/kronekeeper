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
	'activity_log/comments',
	'underscore',
	'datatables.net'
], function (
	moment,
	comments
) {
        'use strict';

	/* Table is hidden until it is processed by Data */
	$("#activity_log_table").on("init.dt", function () {
		console.log("table redrawn");
		$("#activity_log_table").show();
	});

	/* Reload table when filter selection changes */
	$(".filter_selection input").change(handle_filter_change);
	$(".filter_selection select").change(handle_filter_change);
	$(".status_selection input").change(handle_filter_change);
	set_download_url();

	/* Pre-compile templates */
	var comments_button_template = _.template(
		$('#comments_button_template').html()
	);
	var menu_button_template = _.template(
		$('#menu_button_template').html()
	);

	$("#activity_log_table").DataTable({
		serverSide: true,
		searching: false, /* Not yet implemented in our perl api */
		ordering: false,  /* Not yet implemented in our perl api */
		bAutoWidth: false,
		ajax: {
			url: "activity_log/query",
			type: "POST",
			data: function(d) {
				d.kk_filter = get_filter_parameters();
				console.log(d);
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
				data: 'by_person_name',
				render: function(data, type, row, meta) {
					return _.escape(data);
				}
			},
			{
				data: 'note',
				className: "dt-left",
				render: function(data, type, row, meta) {
					var html = _.escape(data);
					if(row.active_jumper_id) {
						return '<a href="/jumper/' + row.active_jumper_id + '">' + html + '</a>';
					}
					else if(row.active_block_id && row.active_circuit_id) {
						return '<a href="/block/' + row.active_block_id + '#circuit_id=' + row.active_circuit_id + '">' + html + '</a>';
					}
					else if(row.active_block_id) {
						return '<a href="/block/' + row.active_block_id + '">' + html + '</a>';
					}
					else {
						return html;
					}
				}
			},
			{
				data: 'completed_by_person_id',
				render: function(data, type, row, meta) {
					var checked = data ? 'checked="checked" ' : '';
					var title = data ? ' title="' + _.escape(row.completed_by_person_name) + '"' : ' title="incomplete"';
					return '<input type="checkbox" ' + checked + 'value="' + row.id + '" class="completed"' + title + ' />';
				},
				className: "dt-center",
				width: "5em"
			},
			{
				data: 'comment',
				render: function(data, type, row, meta) {
					return comments_button_template(row) + menu_button_template(row);
				},
				className: "dt-center"
			}
		],
		createdRow: function(row, data, index) {
			if(data.completed_by_person_id) {
				$(row).addClass("completed");
			}
			if(data.is_next_task) {
				$(row).addClass("next_task");
			}
			$(row).attr("data-id", data.id);
			$(row).on("click", "a.notes_button", comments.display);
		}
	});

	/* When table is redrawn, attach events to new rows */
	$("#activity_log_table").on("draw.dt", function () {
		console.log("draw.dt");
		$("input.completed").change(handle_checkbox_change);
	});


	function handle_filter_change(e) {

		console.log("filter changed");
		set_download_url();
		$("#activity_log_table").DataTable().draw();
	}


	function set_download_url() {

		/* Update XLSX download link with new parameters */
		var filter_params = JSON.stringify(get_filter_parameters());
		console.log("filter_params");
		$("#download_xlsx_link").attr("href", "activity_log/xlsx?filter=" + filter_params);
	}

	function get_filter_parameters() {

		var rv = {
			show_complete: $("#checkbox_show_complete").prop("checked"),
			show_incomplete: $("#checkbox_show_incomplete").prop("checked"),
			show_jumpers: $("#checkbox_show_jumpering").prop("checked"),
			show_blocks: $("#checkbox_show_blocks").prop("checked"),
			show_other: $("#checkbox_show_other").prop("checked")
		};
	
		/* No user_id parameter means show entries for all users */	
		if($("#select_user").val()) {
			rv.user_id = $("#select_user").val();
		}

		return rv;
	}


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
				if(json.next_item_id) {
					tbody.find("tr").has('input[value="' + json.next_item_id + '"]').addClass("next_task");
				}
			}
		});
	}

});
