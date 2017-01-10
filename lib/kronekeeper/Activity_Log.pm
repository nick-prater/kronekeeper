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
use Dancer2 appname => 'kronekeeper';
use Dancer2::Plugin::Database;
use Dancer2::Plugin::Auth::Extensible;
use Moo;
use kronekeeper::Frame;
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

		my $results = get_activity_log(
			max_items => $data->{length},
			skip_records => $data->{start},
			frame_id => $id,
		);

		my $rv = {
			draw => $data->{draw},
			data => $results,
			recordsTotal => activity_log_count($id),
			recordsFiltered => activity_log_count($id),
		};

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

	my %args = @_;
	$args{max_items} ||= 500;
	$args{skip_records} ||= 0;
	$args{frame_id} or die "missing frame_id argument";
	$args{timezone} ||= 'UTC';


	my $q = database->prepare("
		SELECT 
			log_timestamp AT TIME ZONE ? AS log_timestamp,
			by_person_id,
			person.name AS by_person_name,
			frame_id,
			function,
			note
		FROM activity_log
		JOIN person ON (person.id = activity_log.by_person_id)
		WHERE frame_id = ?
		ORDER BY log_timestamp DESC, activity_log.id DESC
		LIMIT ?
		OFFSET ?
	");
	$q->execute(
		$args{timezone},
		$args{frame_id},
		$args{max_items},
		$args{skip_records},
	);
		
	my $result = $q->fetchall_arrayref({});
	return $result;
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


1;
