package kronekeeper::Jumper;

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



prefix '/api/jumper' => sub {

	del '/:jumper_id' => sub {

		user_has_role('edit') or do {
			send_error('forbidden' => 403);
		};

		my $id = param('jumper_id');
		jumper_id_valid_for_account($id) or do {
			send_error('forbidden' => 403);
		};

		delete_jumper($id);

		database->commit;

		return to_json {
			deleted => 1,
			jumper_id => $id,
		};
	};

};


sub jumper_id_valid_for_account {

	my $jumper_id = shift;
	my $account_id = shift || session('account')->{id};

	$jumper_id =~ m/^\d+$/ or do {
		error "id is not an integer";
		return undef;
	};
	$account_id =~ m/^\d+$/ or do {
		error "account_id is not an integer";
		return undef;
	};

	my $q = database->prepare("
		SELECT 1
		FROM jumper_wire
		JOIN connection ON (connection.jumper_wire_id = jumper_wire.id)
		JOIN pin ON (pin.id = connection.pin_id)
		JOIN circuit ON (circuit.id = pin.circuit_id)
		JOIN block ON (block.id = circuit.block_id)
		JOIN vertical ON (vertical.id = block.vertical_id)
		JOIN frame ON (frame.id = vertical.frame_id) 
		WHERE jumper_wire.jumper_id = ?
		AND frame.account_id = ?
		LIMIT 1
	");

	$q->execute(
		$jumper_id,
		$account_id,
	);

	return $q->fetchrow_hashref;
}


sub jumper_wire_connections {

	my $jumper_id = shift;
	my $q = database->prepare("
		SELECT *
		FROM jumper_wire_connections
		WHERE jumper_id = ?
	");
	$q->execute($jumper_id);

	return $q->fetchall_arrayref({});
}


sub describe_jumper_connections {

	my $connections = shift;

	$connections or return "[no connections]";

	if($connections->[0]->{is_simple_jumper}) {
		my @designations = @{$connections->[0]->{full_circuit_designations}};
		return join('->', @designations);
	}
	else {
		my @wire_descriptions;
		foreach my $wire(@{$connections}) {
			push(
				@wire_descriptions,
				join('->', @{$wire->{full_pin_designations}})
			);
		}
		return join(', ', @wire_descriptions);
	}
}


sub delete_jumper {

	my $id = shift;
	debug "deleting jumper_id $id";

	my $connections = jumper_wire_connections($id);

	# Remove jumper and it's connections
	my $q = database->prepare(
		"SELECT delete_jumper(?)"
	);
	$q->execute(
		$id,
	) or do {
		database->rollback;
		send_error('error deleting jumper' => 500);
	};

	# Update Activity Log
	my $note = sprintf(
		'jumper removed %s',
		describe_jumper_connections($connections)
	);

	# Technically jumpers could span an unlimited number of blocks
	# and circuits, so we only record activity at the frame level
	$al->record({
		function     => 'kronekeeper::Jumper::delete_jumper',
		frame_id     => $connections->[0]->{frame_id},
		note         => $note,
	});
}




1;
