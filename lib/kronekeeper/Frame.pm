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
use kronekeeper::Activity_Log;
use kronekeeper::Block qw(
	block_id_valid_for_account
	block_is_free
	block_info
	block_circuits
);
use kronekeeper::Jumper qw(
	delete_jumper
);
use Exporter qw(import);
our $VERSION = '0.01';
our @EXPORT_OK = qw(
	frame_id_valid_for_account
	frame_info
);

my $al = kronekeeper::Activity_Log->new();


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

	get '/add' => sub {

		user_has_role('edit') or do {
			send_error('forbidden' => 403);
		};

		template('add_frame', {});
	};

	post '/add' => sub {

		user_has_role('edit') or do {
			send_error('forbidden' => 403);
		};

		param('frame_name') or do {
			debug("invalid frame_name parameter");
			send_error("invalid frame name parameter" => 400);
		};

		param('frame_width') && param('frame_width') =~ m/^\d+$/ or do {
			debug("invalid frame_width parameter");
			send_error("invalid frame_width parameter" => 400);
		};

		param('frame_height') && param('frame_height') =~ m/^\d+$/ or do {
			debug("invalid frame_height parameter");
			send_error("invalid frame_height parameter" => 400);
		};

		my $frame_id = create_frame(
			param('frame_name'),
			param('frame_width'),
			param('frame_height'),
		) or do {
			error("Failed creating new frame");
			database->rollback;
			send_error("Failed creating new frame" => 500);
		};

		# Update Activity Log
		my $note = sprintf(
			'Created new frame "%s" with dimensions %d x %d',
			param('frame_name'),
			param('frame_width'),
			param('frame_height'),
		);

		$al->record({
			function     => 'kronekeeper::Frame::add_frame',
			frame_id     => $frame_id,
			note         => $note,
		});

		database->commit;

		forward(
			'/frame/',
			{},
			{method => 'GET'}
		);
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

		
		# Update Activity Log
		my $info = block_info($placed_block_id);
		my $note = sprintf(
			'placed %s block at %s',
			$data->{block_type},
			$info->{full_designation},
		);

		$al->record({
			function     => 'kronekeeper::Frame::place_block',
			frame_id     => $info->{frame_id},
			block_id_a   => $info->{block_id},
			note         => $note,
		});

		database->commit;

		return to_json {
			block_id => $placed_block_id,
		};
	};


	post '/remove_block' => sub {
		
		# Removes a block and all associated jumpers, circuits, pins etc...

		user_has_role('edit') or do {
			send_error('forbidden' => 403);
		};

		debug "remove_block()";
		debug request->body;
		my $data = from_json(request->body);

		block_id_valid_for_account($data->{block_id}) or do {
			send_error("block_id invalid or not permitted" => 403);
		};
		my $info = block_info($data->{block_id});

		debug("removing block_id $data->{block_id} and all associated elements");
		my $removed_block = remove_block(
			$data->{block_id},
		) or do {
			database->rollback;
			die;
		};

		# Update Activity Log
		my $note = sprintf(
			'Removed block from %s (was "%s")',
			$info->{full_designation},
			$info->{name} || '',
		);

		$al->record({
			function     => 'kronekeeper::Frame::remove_block',
			frame_id     => $info->{frame_id},
			block_id_a   => $info->{block_id},
			note         => $note,
		});

		database->commit;

		return to_json {
			success => $removed_block,
			activity_log_note => $note,
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


sub remove_block {

	my $block_id = shift;

	# We deal with the activity log at this application level,
	# rather than within the database. As we want to record the
	# removal of every jumper connected to the block, before the
	# block itself is removed, we do individual jumper removal
	# from perl, rather than as a single database call.
	#
	# Note that this doesn't remove the block position itself.
	# That remains available as a position for a new block to be
	# placed.

	# Get jumpers on this block
	my $block_circuits = block_circuits($block_id);

	# Delete the jumpers one-by-one
	foreach my $circuit(@{$block_circuits}) {
		my $jumpers = $circuit->{jumpers} or next; # maybe no jumpers
		foreach my $jumper(@{$jumpers}) {
			delete_jumper($jumper->{jumper_id});
		}
	}

	# Finally delete the block
	my $q = database->prepare("SELECT remove_block(?) AS removed_block");
	$q->execute($block_id) or do {
		error("ERROR running database command to remove block");
		database->rollback;
		die;
	};

	my $result = $q->fetchrow_hashref or do {
		error("received no result back from database after removing block");
		database->rollback;
		die;
	};

	return $result->{removed_block};
}


sub create_frame {

	my $frame_name = shift;
	my $frame_width = shift;
	my $frame_height = shift;
	my $account_id = shift || session('account')->{id};

	debug(sprintf(
		'creating frame "%s" with dimensions %dx%d',
		$frame_name,
		$frame_width,
		$frame_height,
	));

	my $q = database->prepare("
		SELECT create_regular_frame(?,?,?,?) AS new_frame_id
	");
	$q->execute(
		$account_id,
		$frame_name,
		$frame_width,
		$frame_height
	) or do {
		error("ERROR running create_regular_frame on database");
		database->rollback;
		send_error("ERROR creating frame" => 500);
	};

	my $result = $q->fetchrow_hashref or do {
		error("ERROR no result after running create_regular_frame on database");
		database->rollback;
		send_error("ERROR creating frame" => 500);
	};

	return $result->{new_frame_id};
}



1;
