package kronekeeper::Activity_Log;

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
use Moo;


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
			block_id_b,
			circuit_id_a,
			circuit_id_b
		) VALUES (?,?,?,?,?,?,?,?,?)"
	);

	$q->execute(
		$args->{person_id},
		$args->{function},
		$args->{account_id},
		$args->{frame_id},
		$args->{note},
		$args->{block_id_a},
		$args->{block_id_b},
		$args->{circuit_id_a},
		$args->{circuit_id_b},
	);
	database->commit;
		
	debug sprintf(
		"activity_log: %s  by_person_id:%s  %s",
		$args->{function}  || '',
		$args->{person_id} || '--',
		$args->{note},
	);

}





1;
