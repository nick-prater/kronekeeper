package kronekeeper::Block;

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




prefix '/block' => sub {

	get '/:block_id' => require_login sub {

		my $id = param('block_id');

		$id && $id =~ m/^\d+$/ or do {
			send_error('invalid block_id parameter', 400);
		};
		block_id_valid_for_account($id) or do {
			send_error('forbidden' => 403);
		};

		#my $frame_info = frame_info($frame_id);
		#$frame_info && !$frame_info->{is_deleted} or do {
		#	send_error('not found' => 404);
		#};

		my $block_detail = block_detail($id);

		template('block', {
			block_detail => $block_detail,
		});
	};

};



sub block_id_valid_for_account {

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




sub block_detail {
	my $block_id = shift;
	my $q = database->prepare("
		SELECT *
		FROM block_detail
		WHERE id=?
	");
	$q->execute($block_id);
	return $q->fetchall_arrayref({});
}





1;
