package kronekeeper::BlockType;

=head1 LICENCE

This file is part of Kronekeeper, a web based application for
recording and managing wiring frame records.

Copyright (C) 2020 NP Broadcast Limited

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
use kronekeeper::Activity_Log;
use Exporter qw(import);
our $VERSION = '0.01';
our @EXPORT_OK = qw();


my $al = kronekeeper::Activity_Log->new();


prefix '/block_type' => sub {

	get '/' => require_login sub {

		template('block_types', {
			block_types => account_block_types(),
		});
	};
};


sub account_block_types {
	my $account_id = shift || session('account')->{id};
	my $q = database->prepare("
		SELECT * FROM block_type_info
		WHERE account_id = ?
		ORDER BY name ASC
	");
	$q->execute(
		$account_id,
	);


	debug("got block types");
	return $q->fetchall_arrayref({})
}

1;
