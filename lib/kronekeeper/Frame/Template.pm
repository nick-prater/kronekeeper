package kronekeeper::Frame::Template;

=head1 LICENCE

This file is part of Kronekeeper, a web based application for 
recording and managing wiring frame records.

Copyright (C) 2017 NP Broadcast Limited

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
use kronekeeper::Frame qw(
	frame_id_valid_for_account
);
use kronekeeper::Block qw(
	block_id_valid_for_account
);
use Exporter qw(import);
our $VERSION = '0.01';
our @EXPORT_OK = qw(
);

my $al = kronekeeper::Activity_Log->new();


prefix '/api/frame' => sub {

	post '/place_template' => sub {

		user_has_role('edit') or do {
			error("user does not have edit role");
			send_error('forbidden' => 403);
		};

		debug request->body;
		my $data = from_json(request->body);

		frame_id_valid_for_account($data->{template_id}) or do {
			error("template is not valid for this account");
			send_error('forbidden' => 403);
		};
		block_id_valid_for_account($data->{block_id}) or do {
			error("place_at_block_id is not valid for this account");
			send_error('forbidden' => 403);
		};

		debug("placing frame");
	};
};




1;

