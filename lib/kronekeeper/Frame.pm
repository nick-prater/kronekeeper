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
use kronekeeper::Block qw(
	block_id_valid_for_account
	block_is_free
);
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


prefix '/api/frame' => sub {

	post '/place_block' => sub {

		user_has_role('edit') or do {
			send_error('forbidden' => 403);
		};

		debug "place_block()";
		debug request->body;
		my $data = from_json(request->body);

		block_id_valid_for_account($data->{block_id}) or do {
			send_error("block_id invalid or not permitted" => 403);
		};

		block_is_free($data->{block_id}) or do {
			send_error("block is not free" => 400);
		};

		$data->{block_type} && $data->{block_type} =~ m/^(237A|ABS)$/ or do {
			send_error("block_type invalid" => 400);
		};

		debug("adding $data->{block_type} block as block_id $data->{block_id}");
		my $placed_block_id = place_block(
			$data->{block_id},
			$data->{block_type},
		) or do {
			database->rollback;
			die;
		};

		return to_json {
			block_id => $placed_block_id,
		};
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

sub place_block {

	my $block_id = shift;
	my $block_type = shift;

	my %block_commands = (
		'237A' => 'place_237A_block',
		'ABS'  => 'place_ABS_block',
	);

	my $block_command = $block_commands{$block_type} or do {
		error("place_block called with unknows block type: $block_type");
		die;
	};

	my $q = database->prepare(sprintf(
		'SELECT %s(?) AS placed_block_id',
		$block_command
	));
	$q->execute($block_id) or do {
		error("ERROR running database command to place block");
		database->rollback;
		die;
	};

	my $result = $q->fetchrow_hashref or do {
		error("received no result back from database after placing block");
		database->rollback;
		die;
	};

	return $result->{placed_block_id};
}



1;
