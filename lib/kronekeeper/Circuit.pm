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
use Dancer2 appname => 'kronekeeper';
use Dancer2::Plugin::Database;
use Dancer2::Plugin::Auth::Extensible;




prefix '/circuit' => sub {


};



prefix '/api/circuit' => sub {

	put '/:circuit_id' => sub {

		#TODO
		# Does this circuit belong to the current account?
		# Is this user allowed to edit?

		my $id = param('circuit_id');

		debug "updating circuit: $id";

		return to_json {
			success => 1
		}
	};

};


sub circuit_id_valid_for_account {

	my $frame_id = shift;
	my $account_id = shift || session('account')->{id};

	$frame_id =~ m/^\d+$/ or do {
		error "block_id is not an integer";
		return undef;
	};
	$account_id =~ m/^\d+$/ or do {
		error "account_id is not an integer";
		return undef;
	};

	my $q = database->prepare("
		SELECT 1
		FROM block
		JOIN vertical ON (vertical.id = block.vertical_id)
		JOIN frame ON (frame.id = vertical.frame_id) 
		WHERE block.id = ?
		AND frame.account_id = ?
	");

	$q->execute(
		$frame_id,
		$account_id,
	);

	return $q->fetchrow_hashref;
}




1;
