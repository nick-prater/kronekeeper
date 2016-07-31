package kronekeeper::Frame;

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
use Exporter qw(import);
our $VERSION = '0.01';
our @EXPORT_OK = qw(
	frame_id_valid_for_account
	frame_info
);



prefix '/frame' => sub {

	get '/' => require_login sub {

		my $q = database->prepare("
			SELECT * FROM frame
			WHERE account_id = ?
			AND is_deleted IS FALSE
			ORDER BY name ASC
		");
		$q->execute(
			session('account')->{id}
		);

		my $f = $q->fetchall_arrayref({});

		template('frames', { frames => $f });
	};	


	get '/:frame_id' => require_login sub {

		my $frame_id = param('frame_id');

		$frame_id && $frame_id =~ m/^\d+$/ or do {
			send_error('invalid frame_id parameter', 400);
		};
		frame_id_valid_for_account($frame_id) or do {
			send_error('forbidden' => 403);
		};

		my $frame_info = frame_info($frame_id);
		$frame_info && !$frame_info->{is_deleted} or do {
			send_error('not found' => 404);
		};

		template('frame', {
			frame_info   => $frame_info,
			frame_blocks => frame_blocks($frame_id),
		});
	};


	any qr{/\d+(/\d+.*)} => require_login sub {
		
		# To keep a nice hierachy, allow access to 'block' routes
		# responds to routes of the form: /frame/[frame_id]/[block_id]/xxx...
		# forwards them to /block/[block_id]/xxx...
		my ($route) = splat;
		my $target =  "/block" . $route;
		debug "redirecting to $target";
		forward $target;
	};

};



sub frame_id_valid_for_account {

	my $frame_id = shift;
	my $account_id = shift || session('account')->{id};

	$frame_id && $frame_id =~ m/^\d+$/ or do {
		error "frame_id is not an integer";
		return undef;
	};
	$account_id && $account_id =~ m/^\d+$/ or do {
		error "account_id is not an integer";
		return undef;
	};


	my $q = database->prepare("
		SELECT 1
		FROM frame
		WHERE id = ?
		AND account_id = ?
	");

	$q->execute(
		$frame_id,
		$account_id,
	);

	return $q->fetchrow_hashref;
}



sub frame_info {
	my $frame_id = shift;
	my $q = database->prepare("SELECT * FROM frame_info WHERE id = ?");
	$q->execute($frame_id);
	return $q->fetchrow_hashref;
}

sub verticals {
	my $frame_id = shift;
	my $q = database->prepare("
		SELECT * from vertical
		WHERE frame_id = ?
		ORDER BY position ASC
	");
	$q->execute($frame_id);
	return $q->fetchall_hashref('position');
}

sub frame_blocks {
	my $frame_id = shift;
	my $verticals = verticals($frame_id);
	my $q = database->prepare("
		SELECT  
			id,
			vertical_id,
			position,
			designation,
			name,
			block_is_free(id) AS is_free
		FROM block
		WHERE vertical_id = ?
		ORDER BY position ASC
	");
	
	foreach my $vertical_position(keys %{$verticals}) {
		my $vertical = $verticals->{$vertical_position};
		$q->execute($vertical->{id});
		$vertical->{blocks} = $q->fetchall_hashref('position');
	}	

	return $verticals;
}




1;
