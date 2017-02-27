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
our $VERSION = '0.02';



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
			error("kk_filter uses invalid user_id");
			kronekeeper::User::user_id_valid_for_account($data->{kk_filter}->{user_id}) or do {
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

		my $rv = {
			id => $id,
			completed_by_person_id => $completed_by,
		};

		# If this is a frame log item, include the next item id in returned data
		my $row;
		if($row = get_activity_log_record($id)) {
			$rv->{next_item_id} = next_frame_task_id($row->{frame_id});
		}

		return to_json $rv;
	};
};



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
			to_person_id
		) VALUES (?,?,?,?,?,?,?,?)"
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
	if($args{kk_filter}->{user_id}) {
		debug("applying filter for user_id: " . $args{kk_filter}->{user_id});
		$filter_sql .= " AND activity_log.by_person_id = ?";
		push @filter_args, $args{kk_filter}->{user_id};
	}

	my $q = database->prepare("
		SELECT
			activity_log.id,
			log_timestamp AT TIME ZONE ? AS log_timestamp,
			by_person_id,
			person.name AS by_person_name,
			frame_id,
			function,
			note,
			completed_by_person_id,
			(? = activity_log.id) AS is_next_task
		FROM activity_log
		JOIN person ON (person.id = activity_log.by_person_id)
		WHERE frame_id = ?
		$filter_sql
		$limit_sql
	");
	my @query_args = (
		$args{timezone},
		$args{next_task_id},
		$args{frame_id},
		@filter_args,
		@limit_args,
	);
	
	$q->execute(@query_args);

	# Return value depends on which arguments were provided	
	if(defined $args{max_items}) {
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


1;
