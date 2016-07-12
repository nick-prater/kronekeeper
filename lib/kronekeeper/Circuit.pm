package kronekeeper::Circuit;

=head1 LICENCE

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

=cut


use strict;
use warnings;
use feature 'switch';
use Dancer2 appname => 'kronekeeper';
use Dancer2::Plugin::Database;
use Dancer2::Plugin::Auth::Extensible;
use kronekeeper::Activity_Log;

my $al = kronekeeper::Activity_Log->new();





prefix '/circuit' => sub {


};



prefix '/api/circuit' => sub {

	patch '/:circuit_id' => require_login sub {

		user_has_role('edit') or do {
			send_error('forbidden' => 403);
		};

		my $id = param('circuit_id');
		circuit_id_valid_for_account($id) or do {
			send_error('forbidden' => 403);
		};
		debug "updating circuit: $id";

		debug request->body;
		my $data = from_json(request->body);
		my $changes = {};
		my $circuit_info = circuit_info($id);

		# We're supplied with a list of changed fields
		# which we process individually so that we can
		# update the activity log with each change.
		# In practice, only one field tends to be updated
		# at a time, as updates are triggered by change
		# events on each field in the user interface.
		foreach my $field(keys %{$data}) {
			my $value = $data->{$field};
			given($field) {
				when('name') {
					update_name($circuit_info, $value);
					$changes->{name} = $value;
				};
				when('cable_reference') {
					update_cable_reference($circuit_info, $value);
					$changes->{cable_reference} = $value;
				};

				default {
					error "failed to update unrecognised circuit field '$field'";
				};					
			};
		};

		database->commit;

		content_type 'application/json';
		return to_json $changes;
	};

};


sub circuit_id_valid_for_account {

	my $circuit_id = shift;
	my $account_id = shift || session('account')->{id};

	$circuit_id =~ m/^\d+$/ or do {
		error "block_id is not an integer";
		return undef;
	};
	$account_id =~ m/^\d+$/ or do {
		error "account_id is not an integer";
		return undef;
	};

	my $q = database->prepare("
		SELECT 1
		FROM circuit
		JOIN block ON (block.id = circuit.block_id)
		JOIN vertical ON (vertical.id = block.vertical_id)
		JOIN frame ON (frame.id = vertical.frame_id) 
		WHERE circuit.id = ?
		AND frame.account_id = ?
	");

	$q->execute(
		$circuit_id,
		$account_id,
	);

	return $q->fetchrow_hashref;
}


sub circuit_info {
	my $circuit_id = shift;
	my $q = database->prepare("
		SELECT * FROM circuit_info
		WHERE id = ?
	");
	$q->execute($circuit_id);
	return $q->fetchrow_hashref;
}


sub update_name {

	my $info = shift;
	my $name = shift;

	# Rename circuit
	my $q = database->prepare("
		UPDATE circuit SET name = ?
		WHERE id = ?
	");

	$q->execute(
		$name,
		$info->{id},
	) or do {
		database->rollback;
		send_error('error updating circuit' => 500);
	};

	#Update Activity Log
	my $note = sprintf(
		'circuit %s renamed "%s" (was "%s")',
		$info->{full_designation},
		$name,
		$info->{name} || '',
	);

	$al->record({
		function     => 'kronekeeper::Circuit::update_name',
		frame_id     => $info->{frame_id},
		block_id_a   => $info->{block_id},
		circuit_id_a => $info->{id},
		note         => $note,
	});
}


sub update_cable_reference {

	my $info = shift;
	my $value = shift;

	# Rename circuit
	my $q = database->prepare("
		UPDATE circuit SET cable_reference = ?
		WHERE id = ?
	");

	$q->execute(
		$value,
		$info->{id},
	) or do {
		database->rollback;
		send_error('error updating circuit' => 500);
	};

	#Update Activity Log
	my $note = sprintf(
		'circuit %s cable reference changed to "%s" (was "%s")',
		$info->{full_designation},
		$value,
		$info->{cable_reference} || '',
	);

	$al->record({
		function     => 'kronekeeper::Circuit::update_cable_reference',
		frame_id     => $info->{frame_id},
		block_id_a   => $info->{block_id},
		circuit_id_a => $info->{id},
		note         => $note,
	});
}



1;
