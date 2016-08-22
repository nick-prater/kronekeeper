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
use Exporter qw(import);
our $VERSION = '0.01';
our @EXPORT_OK = qw(
	circuit_info
	circuit_pins
	circuit_id_valid_for_account
	circuit_info_from_designation
);

my $al = kronekeeper::Activity_Log->new();



prefix '/api/circuit' => sub {

	get '/:circuit_id' => require_login sub {

		circuit_id_valid_for_account(param("circuit_id")) or do {
			send_error('forbidden' => 403);
		};

		# Unfortunately the view that returns a collection of circuits
		# uses slightly different field names to the view that returns
		# a single circuit. Both are used by the user-interface Backbone
		# Circuit model, so we map the field names here to match those
		# used in /api/block/:block_id
		my $circuit = circuit_info(param("circuit_id"));
		return to_json {
			circuit_id      => $circuit->{id},
			block_id        => $circuit->{block_id},
			name            => $circuit->{name},
			cable_reference => $circuit->{cable_reference},
			connection      => $circuit->{connection},
			designation     => $circuit->{circuit_designation},
		};
	};

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
			given($field) {
				when(/^(name)$/) {
					update_name_cascade($circuit_info, $data->{$field});
					$changes->{$field} = $data->{$field};
					$changes->{connected_circuits} = connected_circuits($id);
				};
				when(/^(cable_reference|connection)$/) {
					update_field($circuit_info, $field, $data->{$field});
					$changes->{$field} = $data->{$field};
				};
				default {
					error "failed to update unrecognised circuit field '$field'";
				};					
			};
		};

		database->commit;

		content_type 'application/json';
		return to_json {
			changes => $changes,
		};
	};


	get '/:circuit_id/jumpers' => require_login sub {

		my $circuit_id = param('circuit_id');
		circuit_id_valid_for_account($circuit_id) or do {
			send_error('forbidden' => 403);
		};

		debug "getting jumpers for circcuit_id $circuit_id";

		return to_json {
			jumpers => get_circuit_jumpers($circuit_id),
		};
	};

};


sub circuit_id_valid_for_account {

	my $circuit_id = shift;
	my $account_id = shift || session('account')->{id};

	$circuit_id && $circuit_id =~ m/^\d+$/ or do {
		error "block_id is not an integer";
		return undef;
	};
	$account_id && $account_id =~ m/^\d+$/ or do {
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


sub parse_circuit_designation {

	my $designation = shift or return undef;
	debug("parsing designation $designation");

	# Strip any whitespace
	$designation =~ s/\s//g;

	# Make uppercase
	$designation = uc $designation;

	my ($vertical, $block, $circuit) = $designation =~ m/^(\p{Letter}+)(\d+)\.(\d+)$/ or do {
		error("Failed to parse circuit designation for $designation");
		return undef;
	};
	
	debug("extracted vertical:$vertical, block:$block, circuit:$circuit");
	
	return {
		vertical_designation => $vertical,
		block_designation => $block,
		circuit_designation => $circuit,
	};
}


sub circuit_info_from_designation {

	my $designation = shift;
	my $frame_id = shift;

	my $d = parse_circuit_designation($designation) or return undef;

	# Try an exact match
	my $q = database->prepare("
		SELECT * FROM circuit_info
		WHERE frame_id = ?
		AND vertical_designation = ?
		AND block_designation = ?
		AND circuit_designation = ?
	");
	$q->execute(
		$frame_id,
		$d->{vertical_designation},
		$d->{block_designation},
		$d->{circuit_designation},
	);
	my $result = $q->fetchrow_hashref;
	if($result) {
		debug("found exact match for circuit designation");
		return $result;
	}

	# Otherwise try a search stripping leading zeros from the block designation
	# So a user entered designation of A3.2 will find a circuit with full
	# designation A03.2
	debug("didn't find exact match for circuit designation - trying to match without leading zeros");
	$q = database->prepare("
		SELECT * FROM circuit_info
		WHERE frame_id = ?
		AND vertical_designation = ?
		AND TRIM(LEADING '0' FROM block_designation) = TRIM(LEADING '0' FROM ?)
		AND circuit_designation = ?
	");
	$q->execute(
		$frame_id,
		$d->{vertical_designation},
		$d->{block_designation},
		$d->{circuit_designation},
	);
	$result = $q->fetchrow_hashref;
	return $result;
}


sub circuit_pins {

	my $circuit_id = shift;

	my $q = database->prepare("
		SELECT *
		FROM pin
		WHERE pin.circuit_id = ?
		ORDER BY position
	");
	$q->execute($circuit_id);
	return $q->fetchall_arrayref({});
}


sub get_circuit_jumpers {

	my $circuit_id = shift;
	my $q = database->prepare("
		SELECT * FROM json_circuit_jumpers(?) AS json_data
	");
	$q->execute($circuit_id);

	# We set utf8=>0 here, because the database driver has already
	# done the character decoding. Failing to set this option triggers
	# an error when when accented characters or emoji.
	# Fix for our Github issue #12
	my $result = from_json($q->fetchrow_hashref->{json_data}, {utf8 => 0});

	return $result;
}


sub update_field {

	my $info = shift;
	my $field = shift;
	my $value = shift;

	# This variable is used to construct sql command, so limit to acceptable values
	$field =~ m/^(cable_reference|name|connection)$/ or do {
		database->rollback;
		send_error("invalid field name");
	};
	
	my $q = database->prepare("
		UPDATE circuit SET $field = ?
		WHERE id = ?
	");

	$q->execute(
		$value,
		$info->{id},
	) or do {
		database->rollback;
		send_error('error updating circuit' => 500);
	};

	# Make field name user friendly
	my $field_display_name = $field;
	$field_display_name =~ s/_/ /g;
	
	# Update Activity Log
	my $note = sprintf(
		'circuit %s %s changed to "%s" (was "%s")',
		$info->{full_designation},
		$field_display_name,
		$value,
		$info->{$field} || '',
	);

	$al->record({
		function     => 'kronekeeper::Circuit::update_field',
		frame_id     => $info->{frame_id},
		block_id_a   => $info->{block_id},
		circuit_id_a => $info->{id},
		note         => $note,
	});
}


sub update_name_cascade {

	my $info = shift;
	my $name = shift;

	my $q = database->prepare("SELECT update_circuit_name_cascade(?, ?)");

	$q->execute(
		$info->{id},
		$name,
	) or do {
		database->rollback;
		send_error('error updating circuit name' => 500);
	};

	# Update Activity Log
	my $note = sprintf(
		'circuit %s name changed to "%s" (was "%s")',
		$info->{full_designation},
		$name,
		$info->{name} || '',
	);

	$al->record({
		function     => 'kronekeeper::Circuit::update_name_cascade',
		frame_id     => $info->{frame_id},
		block_id_a   => $info->{block_id},
		circuit_id_a => $info->{id},
		note         => $note,
	});
}


sub connected_circuits {

	# Returns an arrayref of all circuits connected via (possibly
	# multiple) jumpers to the given cicuit_id
	my $circuit_id = shift;
	my $q = database->prepare("SELECT * FROM connected_circuit_ids(?)");
	$q->execute($circuit_id);
	
	my @rv;
	while(my $row = $q->fetchrow_arrayref) {
		push(@rv, $$row[0]);
	}

	return \@rv;
}

1;
