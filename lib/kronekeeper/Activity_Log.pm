package kronekeeper::Activity_Log;

=head1 LICENCE

This file is part of Kronekeeper, a web based application for 
recording and managing wiring frame records.

Copyright (C) 2016-2017 NP Broadcast Limited

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

=cut



use strict;
use warnings;
use Exporter qw(import);
use Dancer2 appname => 'kronekeeper';
use Dancer2::Plugin::Database;
use Dancer2::Plugin::Auth::Extensible;
use Moo;
use kronekeeper::Frame;
use kronekeeper::User;
use Excel::Writer::XLSX;
use Time::Piece;
our $VERSION = '0.03';



prefix '/template' => sub {

	# Templates are just frames with a flag set
	# Redirect them to the appropriate frame routes
	get '/:frame_id/activity_log' => require_login sub {
		forward '/frame/'.param('frame_id').'/activity_log';
	};
};


prefix '/frame/:frame_id/activity_log' => sub {

	get '' => require_login sub {

		user_has_role('view_activity_log') or do {
			send_error('forbidden' => 403);
		};
		kronekeeper::Frame::frame_id_valid_for_account(param("frame_id")) or do {
			send_error('forbidden' => 403);
		};

		template(
			'activity_log',
			{
				frame_info => kronekeeper::Frame::frame_info(param("frame_id")),
				account_users => kronekeeper::User::account_users(),
			}
		);
	};


	get '/xlsx' => require_login sub {

		user_has_role('view_activity_log') or do {
			send_error('forbidden' => 403);
		};

		my $id = param('frame_id');
		kronekeeper::Frame::frame_id_valid_for_account($id) or do {
			send_error('forbidden' => 403);
		};

		my $filter = param('filter') || '{}';

		debug "filter: $filter";

		my $kk_filter = from_json($filter);

		use Data::Dumper;
		debug Dumper $kk_filter;

		if($kk_filter && $kk_filter->{user_id}) {
			error("kk_filter uses invalid user_id");
			kronekeeper::User::user_id_valid_for_account($kk_filter->{user_id}) or do {
				send_error("filter uses invalid user_id" => 403);
			};
		}

		my $results = get_activity_log(
			max_items => undef,
			frame_id => $id,
			kk_filter => $kk_filter,
		);

		content_type 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
		header 'Content-Disposition' => 'inline; filename="Kronekeeper-activity_log.xlsx';
		return activity_log_as_xlsx({
			rows => $results,
			frame_info => kronekeeper::Frame::frame_info($id),
			kk_filter => $kk_filter,
		});
	};


	post '/query' => require_login sub {

		# This receives and sends JSON data suitable for use with Datatables
		# See: https://datatables.net/manual/server-side

		user_has_role('view_activity_log') or do {
			send_error('forbidden' => 403);
		};

		my $id = param('frame_id');
		kronekeeper::Frame::frame_id_valid_for_account($id) or do {
			send_error('forbidden' => 403);
		};

		my $data = from_json(request->body);

		# We return this directly to the client, so
		# make sure it doesn't contain anything nasty.
		$data->{draw} =~ m/^\d+$/ or do {
			error("draw parameter is invalid");
			send_error("invalid draw parameter" => 400);
		};
		$data->{draw} += 0; # Recast as numeric

		if($data->{kk_filter} && $data->{kk_filter}->{user_id}) {
			kronekeeper::User::user_id_valid_for_account($data->{kk_filter}->{user_id}) or do {
				error("kk_filter uses invalid user_id");
				send_error("filter uses invalid user_id" => 403);
			};
		}

		my $results = get_activity_log(
			max_items => $data->{length},
			skip_records => $data->{start},
			frame_id => $id,
			next_task_id => next_frame_task_id($id),
			kk_filter => $data->{kk_filter},
		);

		my $filtered_count = get_activity_log(
			frame_id => $id,
			kk_filter => $data->{kk_filter},
		);

		my $rv = {
			draw => $data->{draw},
			data => $results,
			recordsTotal => activity_log_count($id),
			recordsFiltered => $filtered_count,
		};

		content_type 'application/json';
		return to_json $rv;
	};


	post '/bulk_complete' => require_login sub {

		user_has_role('edit_activity_log') or do {
			send_error('forbidden' => 403);
		};

		my $id = param('frame_id');
		kronekeeper::Frame::frame_id_valid_for_account($id) or do {
			send_error('forbidden' => 403);
		};

		my $data = from_json(request->body);

		if($data->{kk_filter} && $data->{kk_filter}->{user_id}) {
			kronekeeper::User::user_id_valid_for_account($data->{kk_filter}->{user_id}) or do {
				error("kk_filter uses invalid user_id");
				send_error("filter uses invalid user_id" => 403);
			};
		}

		# Although we could construct a single query to do this, it's advantageous
		# to code the filter queries in just one place so that there is no risk of
		# a bug causing inconsistencies in the way they are applied. We therefore
		# retrieve a list of all matching rows, then apply update as a separate query

		# Regardless of user-specified filter, we are only going to change rows
		# that are currently marked incomplete. There is therefore no point in returning
		# already completed rows.
		$data->{kk_filter}->{show_complete} = 0;

		my $results = get_activity_log(
			max_items => undef,
			frame_id => $id,
			kk_filter => $data->{kk_filter},
		);
		my $user = logged_in_user;

		# Build list of rows to update
		# Again, we could combine this into a single query, but we use
		# existing code paths to minimise the change of inconsistency.
		# It's not an expensive operation, but we'll revisit if it's too slow.
		foreach my $result(@{$results}) {
			debug("marking activity_log id $result->{id} as completed");
			update_completed_flag(
				$result->{id},
				$user->{id},
			);
		}

		my $rv = {};
		$rv->{next_item_id} = next_frame_task_id(param('frame_id'));

		database->commit;
		debug("completed activity log bulk complete");

		content_type 'application/json';
		return to_json $rv;
	};

};


prefix '/api/activity_log' => sub {

	# Templates are just frames with a flag set
	# Redirect them to the appropriate frame routes
	patch '/:id' => require_login sub {

		user_has_role('edit_activity_log') or do {
			send_error('forbidden' => 403);
		};

		my $id = param("id");
		my $user = logged_in_user;
		activity_log_id_valid_for_account($id) or do {
			error("activity log id is invalid for this account");
			send_error("activity log id is invalid for this account" => 403);
		};

		my $data = from_json(request->body);
		my $completed_by = $data->{completed} ? $user->{id} : undef;
		my $rv = {
			id => $id,
		};

		# Update completed flag if status is provided
		if(exists $data->{completed}) {
			$rv->{completed_by_person_id} = $completed_by;
			update_completed_flag(
				$id,
				$completed_by,
			);
		}

		# Update comment if provided
		if(exists $data->{comment}) {
			update_comment(
				$id,
				$data->{comment},
			);
		}

		# If this is a frame log item, include the next item id in returned data
		my $row;
		if($row = get_activity_log_record($id)) {
			$rv->{next_item_id} = next_frame_task_id($row->{frame_id});
		}

		database->commit;

		content_type 'application/json';
		return to_json $rv;
	};
};


sub update_completed_flag {

	my $id = shift;
	my $completed_by = shift;

	debug("updating completed_by_person_id for activity_log id $id");

	my $q = database->prepare("
		UPDATE activity_log
		SET completed_by_person_id = ?
		WHERE activity_log.id = ?
	");
	$q->execute(
		$completed_by,
		$id,
	) or do {
		database->rollback;
		error("ERROR updating activity log");
		send_error("database error updating activity log" => 500);
	};
}


sub update_comment {

	my $id = shift;
	my $comment = shift;

	debug("updating comment for activity_log id $id");

	my $q = database->prepare("
		UPDATE activity_log
		SET comment = ?
		WHERE activity_log.id = ?
	");
	$q->execute(
		$comment,
		$id,
	) or do {
		database->rollback;
		error("ERROR updating activity log");
		send_error("database error updating activity log" => 500);
	};
}


sub record {

	my $self = shift;
	my $args = shift;
	my $user = logged_in_user;

	defined $args->{note} or die "notes argument missing";
	exists $args->{account_id} or $args->{account_id} = $user->{account_id};
	exists $args->{person_id}  or $args->{person_id}  = $user->{id};

	my $q = database->prepare(
		"INSERT INTO activity_log (
			by_person_id,
			function,
			account_id,
			frame_id,
			note,
			block_id_a,
			circuit_id_a,
			to_person_id,
			jumper_id
		) VALUES (?,?,?,?,?,?,?,?,?)"
	);

	$q->execute(
		$args->{person_id},
		$args->{function},
		$args->{account_id},
		$args->{frame_id},
		$args->{note},
		$args->{block_id_a},
		$args->{circuit_id_a},
		$args->{to_person_id},
		$args->{jumper_id},
	);
		
	debug sprintf(
		"activity_log: %s  by_person_id:%s  %s",
		$args->{function}  || '',
		$args->{person_id} || '--',
		$args->{note},
	);
}


sub get_activity_log {

	# If called without max_items and skip_records arguments, this returns a count
	# of the available records with filters applied. If max_items and skip_records
	# are supplied, returns an arrayref of filtered records

	my %args = @_;
	$args{skip_records} ||= 0;
	$args{frame_id} or die "missing frame_id argument";
	$args{timezone} ||= 'UTC';
	$args{kk_filter} ||= {};

	# Apply result limit if provided
	my $limit_sql = '';
	my @limit_args = ();
	if(defined $args{max_items}) {
		$limit_sql = "
			ORDER BY log_timestamp DESC, activity_log.id DESC
			LIMIT ?
			OFFSET ?
		";
		@limit_args = (
			$args{max_items},
			$args{skip_records},
		);
	}

	# Apply filters if specified
	my $filter_sql = '';
	my @filter_args = ();

	# Max activity_log_id filter
	if($args{kk_filter}->{max_activity_log_id}) {
		debug("applying filter for max activity_log.id: " . $args{kk_filter}->{max_activity_log_id});
		$filter_sql .= " AND activity_log.id <= ?";
		push @filter_args, $args{kk_filter}->{max_activity_log_id};
	}

	# By User Filter
	if($args{kk_filter}->{user_id}) {
		debug("applying filter for user_id: " . $args{kk_filter}->{user_id});
		$filter_sql .= " AND activity_log.by_person_id = ?";
		push @filter_args, $args{kk_filter}->{user_id};
	}

	# Complete/Incomplete filter
	if($args{kk_filter}->{show_complete} && !$args{kk_filter}->{show_incomplete}) {
		$filter_sql .= " AND completed_by_person_id IS NOT NULL";
	}
	elsif($args{kk_filter}->{show_incomplete} && !$args{kk_filter}->{show_complete}) {
		$filter_sql .= " AND completed_by_person_id IS NULL";
	}
	elsif(!$args{kk_filter}->{show_incomplete} && !$args{kk_filter}->{show_complete}) {
		$filter_sql .= " AND FALSE";
		debug("Neither complete nor incomplete log entries have been requested. This will return no results");
	}

	# Function type filter
	my @function_filters = ("FALSE"); # Default is to show nothing
	if($args{kk_filter}->{show_jumpers}) {
		push(@function_filters, "function IN (
			'kronekeeper::Jumper::add_simple_jumper',
			'kronekeeper::Jumper::add_custom_jumper',
			'kronekeeper::Jumper::delete_jumper'
		)");
	}

	if($args{kk_filter}->{show_blocks}) {
		push(@function_filters, "function IN (
			'kronekeeper::Frame::place_block',
			'kronekeeper::Frame::remove_block'
		)");
	}

	if ($args{kk_filter}->{show_other}) {
		push(@function_filters, "function NOT IN (
			'kronekeeper::Jumper::add_simple_jumper',
			'kronekeeper::Jumper::add_custom_jumper',
			'kronekeeper::Jumper::delete_jumper',
			'kronekeeper::Frame::place_block',
			'kronekeeper::Frame::remove_block'
		)");
	}

	$filter_sql .= " AND (" . join(" OR ", @function_filters) . ")";


	my $sql = "
		SELECT
			activity_log.id,
			log_timestamp AT TIME ZONE ? AS log_timestamp,
			by_person_id,
			created_by_person.name AS by_person_name,
			frame_id,
			function,
			activity_log.note AS note,
			completed_by_person_id,
			completed_by_person.name AS completed_by_person_name,
			(? = activity_log.id) AS is_next_task,
			block.id AS active_block_id,
			circuit.id AS active_circuit_id,
			jumper.id AS active_jumper_id,
			comment
		FROM activity_log
		JOIN person AS created_by_person ON (
			created_by_person.id = activity_log.by_person_id
		)
		LEFT JOIN person AS completed_by_person ON (
			completed_by_person.id = activity_log.completed_by_person_id
		)
		LEFT JOIN block ON (
			block.id = activity_log.block_id_a
		)
		LEFT JOIN circuit ON (
			circuit.id = activity_log.circuit_id_a
		)
		LEFT JOIN jumper ON (
			jumper.id = activity_log.jumper_id
		)
		WHERE frame_id = ?
		$filter_sql
		$limit_sql
	";
	my @query_args = (
		$args{timezone},
		$args{next_task_id},
		$args{frame_id},
		@filter_args,
		@limit_args,
	);

	debug ("query: $sql");
	my $q = database->prepare($sql);
	$q->execute(@query_args);

	# Return value depends on which arguments were provided	
	if(exists $args{max_items}) {
		my $result = $q->fetchall_arrayref({});
		return $result;
	}
	else {
		return $q->rows;
	}
}


sub get_activity_log_record {

	my $id = shift;
	my $q = database->prepare("
		SELECT * FROM activity_log
		WHERE id = ?
	");
	$q->execute($id);
	return $q->fetchrow_hashref;
}


sub activity_log_count {

	my $frame_id = shift;
	my $q = database->prepare("
		SELECT COUNT(*) AS c
		FROM activity_log
		WHERE frame_id = ?
	");
	$q->execute($frame_id);

	my $r = $q->fetchrow_hashref or do {
		database->rollback;
		error("failed to query count from activity_log");
		send_error("Failed to query count from activity_log" => 500);
	};

	return $r->{c};
}


sub activity_log_id_valid_for_account {

	my $id = shift;
	my $account_id = shift || session('account')->{id};

	$id && $id =~ m/^\d+$/ or do {
		error "activity_log_id is not an integer: [$id]";
		return undef;
	};

	my $q = database->prepare("
		SELECT 1
		FROM activity_log
		WHERE activity_log.account_id = ?
		AND activity_log.id = ?
	");
	$q->execute(
		$account_id,
		$id
	);

	return $q->fetchall_arrayref({});
}


sub next_frame_task_id {

	my $frame_id = shift;
	my $q = database->prepare("
		SELECT id
		FROM activity_log
		WHERE frame_id = ?
		AND completed_by_person_id IS NULL
		ORDER BY log_timestamp ASC
		LIMIT 1
	");
	$q->execute($frame_id);

	my $r = $q->fetchrow_hashref or do {
		error("failed to find next activity log item");
		return undef;
	};

	return $r->{id};
}


sub activity_log_as_xlsx {

	my $args = shift;

	# Write spreadsheet to an in-memory filehandle, rather than usimg
	# temporary files. Maybe we'll need to revisit this if they get
	# very big...
	open my $fh, '>', \my $xlsx or die "failed to open filehandle for xlsx spreadsheet: $!\n";

	my $workbook  = Excel::Writer::XLSX->new( $fh );
	my $worksheet = $workbook->add_worksheet();
	my $row = 0;
	my $col = 0;

	# Define some formats
	my $column_heading = $workbook->add_format(
		bold => 1,
	);
	my $align_left = $workbook->add_format(
		align => 'left',
	);
	my $timestamp_format = $workbook->add_format(
		align => 'left',
		num_format => 'DD/MM/YYYY HH:MM:SS',
	);
	my $info_heading = $workbook->add_format(
		bold => 1,
		align => 'right',
	);

	# Set column widths and formats
	$worksheet->set_column(0, 0, 25, $align_left);       # ID
	$worksheet->set_column(1, 1, 20, $timestamp_format); # Timestamp
	$worksheet->set_column(2, 2, 15);                    # Created By
	$worksheet->set_column(3, 3, 40);                    # Activity
	$worksheet->set_column(4, 4, 10);                    # Complete
	$worksheet->set_column(5, 5, 15);                    # Completed By
	$worksheet->set_column(6, 6, 15, $align_left);       # Comment
	$worksheet->set_column(7, 7, 30);                    # Function

	# Insert Kronekeeper logo
	my $logo_image = config->{kronekeeper_logo};
	if($logo_image && -e $logo_image) {
		$worksheet->set_row($row, 60);
		$worksheet->insert_image(
			$row, $col,
			$logo_image,
			20, 20,
			2, 2,
		);
	}
	else {
		error("Kronekeeper logo image missing or not defined");
	}
	
	# Insert heading
	$row ++;
	$row ++;
	$col = 0;
	$worksheet->write($row, $col ++, "Report:", $info_heading);
	$worksheet->write($row, $col ++, "Activity Log");

	$row ++;
	$col = 0;
	$worksheet->write($row, $col ++, "Frame:", $info_heading);
	$worksheet->write($row, $col ++, $args->{frame_info}->{name});

	$row ++;
	$col = 0;
	$worksheet->write($row, $col ++, "Report Created (UTC):", $info_heading);
	$worksheet->write_date_time($row, $col ++, gmtime->datetime(), $timestamp_format);

	$row ++;
	$col = 0;
	my $filter_by_person = kronekeeper::User::user_info($args->{kk_filter}->{user_id});
	$worksheet->write($row, $col ++, "Show Activity By:", $info_heading);
	$worksheet->write($row, $col ++, $filter_by_person ? $filter_by_person->{name} : 'anybody');

	$row ++;
	$col = 0;
	$worksheet->write($row, $col ++, "Show Complete:", $info_heading);
	$worksheet->write($row, $col ++, $args->{kk_filter}->{show_complete} ? 'yes' : 'no');

	$row ++;
	$col = 0;
	$worksheet->write($row, $col ++, "Show Incomplete:", $info_heading);
	$worksheet->write($row, $col ++, $args->{kk_filter}->{show_incomplete} ? 'yes' : 'no');

	$row ++;
	$col = 0;
	$worksheet->write($row, $col ++, "Show Jumpering:", $info_heading);
	$worksheet->write($row, $col ++, $args->{kk_filter}->{show_jumpers} ? 'yes' : 'no');

	$row ++;
	$col = 0;
	$worksheet->write($row, $col ++, "Show Blocks:", $info_heading);
	$worksheet->write($row, $col ++, $args->{kk_filter}->{show_blocks} ? 'yes' : 'no');

	$row ++;
	$col = 0;
	$worksheet->write($row, $col ++, "Show Other Activity:", $info_heading);
	$worksheet->write($row, $col ++, $args->{kk_filter}->{show_other} ? 'yes' : 'no');


	# Add column headings
	$row ++;	
	$row ++;	
	$col = 0;
	$worksheet->set_row($row, undef, $column_heading);
	$worksheet->write($row, $col ++, 'ID');
	$worksheet->write($row, $col ++, 'Timestamp (UTC)');
	$worksheet->write($row, $col ++, 'Created By');
	$worksheet->write($row, $col ++, 'Activity');
	$worksheet->write($row, $col ++, 'Complete');
	$worksheet->write($row, $col ++, 'Completed By');
	$worksheet->write($row, $col ++, 'Comment');
	$worksheet->write($row, $col ++, 'Function');


	foreach my $r(@{$args->{rows}}) {
		$row ++;
		$col = 0;

		# Convert format of timestamp field
		# Excel::Writer::XLSX requires date and time parts to be separated by 'T'
		# whereas postgres returns them separated by space
		$r->{log_timestamp} =~ s/ /T/;

		$worksheet->write($row, $col ++, $r->{id});
		$worksheet->write_date_time($row, $col ++, $r->{log_timestamp});
		$worksheet->write($row, $col ++, $r->{by_person_name});
		$worksheet->write($row, $col ++, $r->{note});
		$worksheet->write($row, $col ++, $r->{completed_by_person_id} ? 'yes' : 'no');
		$worksheet->write($row, $col ++, $r->{completed_by_person_name});
		$worksheet->write($row, $col ++, $r->{comment});
		$worksheet->write($row, $col ++, $r->{function});
	}

	$workbook->close();
	close $fh;

	debug "written xlsx with $row rows";
	return $xlsx;
}



1;
