package kronekeeper::Frame;

=head1 LICENCE

This file is part of Kronekeeper, a web based application for 
recording and managing wiring frame records.

Copyright (C) 2016-2020 NP Broadcast Limited

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
	block_type_id_valid_for_account
);

my $al = kronekeeper::Activity_Log->new();


prefix '/template' => sub {

	# Templates are just frames with a flag set
	# Redirect them to the appropriate frame routes
	get '/' => require_login sub {
		forward '/frame/', { show_templates => 1 };
	};
	get '/add' => sub {
		forward '/frame/add', { is_template => 1 };
	};
	post '/add' => sub {
		forward '/frame/add';
	};
	get '/:frame_id' => sub {
		forward '/frame/' . param('frame_id');
	};
	any qr{/\d+(/\d+.*)} => require_login sub {

		# To keep a nice hierachy, allow access to 'block' routes
		# responds to routes of the form: /template/[frame_id]/[block_id]/xxx...
		# forwards them to /block/[block_id]/xxx...
		my ($route) = splat;
		my $target =  "/block" . $route;
		debug "redirecting to $target";
		forward $target;
	};
};


prefix '/frame' => sub {

	get '/' => require_login sub {

		my $want_templates = param('show_templates') ? 'TRUE' : 'FALSE';
		my $q = database->prepare("
			SELECT * FROM frame
			WHERE account_id = ?
			AND is_deleted IS FALSE
			AND is_template = $want_templates
			ORDER BY name ASC
		");
		$q->execute(
			session('account')->{id},
		);

		my $f = $q->fetchall_arrayref({});
		my $show_templates = param('show_templates') ? 1 : 0;

		template('frames', {
			frames => $f,
			show_templates => $show_templates,
		});
	};	

	get '/add' => sub {

		user_has_role('edit') or do {
			send_error('forbidden' => 403);
		};

		# Enforce account limit on maximum frames/template
		my $frame_count = frame_count();
		my $max_frames = max_frames();
		my $max_size = max_frame_size(); 
		if(defined $max_frames && ($frame_count >= $max_frames)) {
			error("cannot add frame as account limit has been reached");

			debug("frame_count", $frame_count);
			debug("max_frames", $max_frames);

			return template('too_many_frames', {
				is_template => param('is_template') ? 1 : 0,
				frame_count => $frame_count,
				max_frames  => $max_frames,
			});
		}
		else {
			return template('add_frame', {
				is_template => param('is_template') ? 1 : 0,
				max_height  => $max_size->{height},
				max_width   => $max_size->{width},
			});
		}
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
			block_types  => block_types(),
			templates    => templates(),
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

	post '/add' => sub {

		user_has_role('edit') or do {
			send_error('forbidden' => 403);
		};

		# Enforce account limit on maximum frames/template
		my $max_frames = max_frames();
		if(defined $max_frames && (frame_count() >= $max_frames)) {
			error("cannot add frame as account limit has been reached");

			# We return a json status here as UI needs to distinguish and
			# report the reason for this error. Arguably all api routes should
			# return json status, but elsewhere only the status code is checked.
			content_type 'application/json';
			status 403;
			return to_json {
				message    => 'Reached maximum frame limit for this account',
				error_code => 'TOO_MANY_FRAMES',
			};
		}

		debug request->body;
		my $data = from_json(request->body);

		# Validate parameters
		$data->{frame_name} or do {
			debug("invalid frame_name");
			send_error("invalid frame name" => 400);
		};
		$data->{frame_width} && $data->{frame_width} =~ m/^\d+$/ or do {
			debug("invalid frame_width");
			send_error("invalid frame_width" => 400);
		};
		$data->{frame_height} && $data->{frame_height} =~ m/^\d+$/ or do {
			debug("invalid frame_height");
			send_error("invalid frame_height" => 400);
		};

		my $designation_order_h = $data->{designation_order_h} || 'left-to-right';
		$designation_order_h =~ m/^(left-to-right|right-to-left)$/ or do {
			debug("invalid designation_order_h");
			send_error("invalid designation_order_h" => 400);
		};
			
		my $designation_order_v = $data->{designation_order_v} || 'bottom-to-top';
		$designation_order_v =~ m/^(bottom-to-top|top-to-bottom)$/ or do {
			debug("invalid designation_order_v");
			send_error("invalid designation_order_v" => 400);
		};

		my $is_template = $data->{is_template} ? 1 : 0;

		# Limit maximum size of frame
		my $max_size = max_frame_size(); 
		if($data->{frame_width} > $max_size->{width}) {
			error("requested frame width exceeds configured maximum");
			send_error("requested frame width exceeds configured maximum" => 400);
		}
		if($data->{frame_height} > $max_size->{height}) {
			error("requested frame height exceeds configured maximum");
			send_error("requested frame height exceeds configured maximum" => 400);
		}

		# Create frame
		my $frame_id = create_frame(
			$data->{frame_name},
			$data->{frame_width},
			$data->{frame_height},
			$designation_order_h,
			$designation_order_v,
			$is_template,
		) or do {
			error("Failed creating new frame");
			database->rollback;
			send_error("Failed creating new frame" => 500);
		};

		# Update Activity Log
		my $note = sprintf(
			'Created new %s "%s" with dimensions %d x %d',
			$is_template ? 'template' : 'frame',
			$data->{frame_name},
			$data->{frame_width},
			$data->{frame_height},
		);

		$al->record({
			function => 'kronekeeper::Frame::add_frame',
			frame_id => $frame_id,
			note     => $note,
		});

		database->commit;

		content_type 'application/json';
		return to_json {
			frame_id => $frame_id,
			is_template => $is_template, 
		};
	};


	del '/:frame_id' => sub {

		# This marks the specified frame as deleted
		# It remains in the database, just not displayed

		my $frame_id = param('frame_id');
		user_has_role('edit') or do {
			send_error('forbidden' => 403);
		};
		frame_id_valid_for_account($frame_id) or do {
			send_error('forbidden' => 403);
		};

		debug("deleting frame $frame_id");

		my $q = database->prepare("
			UPDATE frame
			SET is_deleted = TRUE
			WHERE id = ?
		");
		$q->execute(
			$frame_id
		) or do {
			database->rollback;
			error("failed to delete frame $frame_id");
			send_error("failed to delete frame" => 500);
		};

		database->commit;
			
		return to_json {
			frame_id => $frame_id
		};
	};


	patch '/:frame_id' => sub {

		user_has_role('edit') or do {
			send_error('forbidden' => 403);
		};

		my $id = param('frame_id');
		frame_id_valid_for_account($id) or do {
			send_error('forbidden' => 403);
		};
		debug "updating frame: $id";

		debug request->body;
		my $data = from_json(request->body);
		my $changes = {};
		my $frame_info = frame_info($id);

		foreach my $field(keys %{$data}) {
			my $value = $data->{$field};
			for($field) {
				m/^name$/ and do {
					update_name($frame_info, $value);
					$changes->{name} = $value;
					last;
				};
				# Else
				error "failed to update unrecognised frame field '$field'";
			}
		};

		database->commit;

		content_type 'application/json';
		return to_json $changes;
	};

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
		block_type_id_valid_for_account($data->{block_type}) or do {
			send_error("block_type invalid or forbidden" => 400);
		};

		debug("adding block type $data->{block_type} as block_id $data->{block_id}");
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
			$info->{block_type_name},
			$info->{full_designation},
		);

		$al->record({
			function     => 'kronekeeper::Frame::place_block',
			frame_id     => $info->{frame_id},
			block_id_a   => $info->{block_id},
			note         => $note,
		});

		database->commit;

		return to_json $info;
	};

	post '/remove_vertical' => sub {
		# Removes a vertical and all associated blocks, jumpers, circuits etc...
		
		user_has_role('edit') or do {
			send_error('forbidden' => 403);
		};

		debug request->body;
		my $data = from_json(request->body);

		vertical_id_valid_for_account($data->{vertical_id}) or do {
			send_error('block_id invalid or not permitted' => 403);
		};

		my $success = remove_vertical(
			$data->{vertical_id},
		) or do {
			database->rollback;
			send_error('failed to remove vertical' => 500);
		};

		database->commit;

		return to_json {
			success => $success,
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

		my $removed_block = remove_block(
			$data->{block_id},
		) or do {
			database->rollback;
			send_error("failed to remove block" => 500);
		};

		database->commit;

		return to_json {
			success => $removed_block,
		};
	};


	post '/remove_block_position' => sub {
		
		# Removes a block position, which must not be in use
		user_has_role('edit') or do {
			send_error('forbidden' => 403);
		};

		debug request->body;
		my $data = from_json(request->body);

		block_id_valid_for_account($data->{block_id}) or do {
			send_error("block_id invalid or not permitted" => 403);
		};
		my $info = block_info($data->{block_id});

		debug("removing position of block_id $data->{block_id}");
		my $success = remove_block_position(
			$data->{block_id},
		);

		# Update Activity Log
		my $note = sprintf(
			'Removed (marked inactive) unused block position %s',
			$info->{full_designation},
		);

		$al->record({
			function     => 'kronekeeper::Frame::remove_block_position',
			frame_id     => $info->{frame_id},
			block_id_a   => $info->{block_id},
			note         => $note,
		});

		database->commit;

		return to_json {
			success => $success,
			activity_log_note => $note,
		};
	};

	post '/enable_block_position' => sub {
		
		# Removes a block position, which must not be in use
		user_has_role('edit') or do {
			send_error('forbidden' => 403);
		};

		debug request->body;
		my $data = from_json(request->body);

		block_id_valid_for_account($data->{block_id}) or do {
			send_error("block_id invalid or not permitted" => 403);
		};
		my $info = block_info($data->{block_id});

		debug("enabling position of block_id $data->{block_id}");
		my $success = enable_block_position(
			$data->{block_id},
		);

		# Update Activity Log
		my $note = sprintf(
			'Enabled block position %s',
			$info->{full_designation},
		);

		$al->record({
			function     => 'kronekeeper::Frame::enable_block_position',
			frame_id     => $info->{frame_id},
			block_id_a   => $info->{block_id},
			note         => $note,
		});

		database->commit;

		return to_json {
			success => $success,
			activity_log_note => $note,
		};
	};


	post '/reverse_designations' => sub {

		user_has_role('edit') or do {
			send_error('forbidden' => 403);
		};

		debug "reverse_designations()";
		debug request->body;
		my $data = from_json(request->body);

		frame_id_valid_for_account($data->{frame_id}) or do {
			send_error("frame_id invalid or not permitted" => 403);
		};

		if($data->{vertical}) {
			reverse_vertical_designations($data->{frame_id});
			$al->record({
				function     => 'kronekeeper::Frame::reverse_designations',
				frame_id     => $data->{frame_id},
				note         => "Reversed vertical designations",
			});
		}

		if($data->{block}) {
			reverse_block_designations($data->{frame_id});
			$al->record({
				function     => 'kronekeeper::Frame::reverse_vertical_designations',
				frame_id     => $data->{frame_id},
				note         => "Reversed block designations",
			});
		}

		database->commit;

		return to_json $data;
	};


	post '/copy' => sub {

		my $user = logged_in_user;
		user_has_role('edit') or do {
			error('user does not have the edit role');
			send_error('forbidden' => 403);
		};

		debug request->body;
		my $data = from_json(request->body);

		frame_id_valid_for_account($data->{frame_id}) or do {
			error("frame_id is not valid for this account");
			send_error("frame_id invalid or not permitted" => 403);
		};

		my $frame_info = frame_info($data->{frame_id}) or do {
			error("unable to retrieve frame_info");
			send_error("failed to retrieve frame_info" => 500);
		};

		# New frame name can be provided, otherwise base it on the source frame
		my $frame_name = $data->{frame_name} || $frame_info->{name}.' (copy)';
		my $new_frame_id = create_frame(
			$frame_name,
			$frame_info->{vertical_count},
			$frame_info->{block_count},
			undef, # designation order doesn't matter - we'll overwrite them later
			undef, # designation order doesn't matter - we'll overwrite them later
			$frame_info->{is_template},
		) or do {
			database->rollback;
			send_error("failed to create new frame" => 500);
		};

		# Get origin block for new frame
		my $q = database->prepare("
			SELECT block.id AS block_id
			FROM block
			JOIN vertical ON (vertical.id = block.vertical_id)
			WHERE vertical.frame_id = ?
			AND vertical.position = 1
			AND block.position = 1
		");
		$q->execute($new_frame_id);
		my $r = $q->fetchrow_hashref;
		debug("origin of new frame is block_id $r->{block_id}");
		
		# Unusually for kronekeeper, this database call updates
		# the activity log, so we don't have to do that separately
		$q = database->prepare("SELECT COUNT(*) AS blocks_placed FROM place_template(?,?,?)");
		$q->execute(
			$r->{block_id},
			$data->{frame_id},
			$user->{id},
		);

		my $result = $q->fetchrow_hashref or do {
			database->rollback;
			error("error making copy");
			send_error("error copying frame as template" => 500);
		};

		database->commit;
		return to_json $result;
	};


	post '/rename_vertical' => sub {

		user_has_role('edit') or do {
			error('user does not have the edit role');
			send_error('forbidden' => 403);
		};

		debug request->body;
		my $data = from_json(request->body);

		# Confirm vertical exists for the logged-in account */
		my $info = vertical_info($data->{vertical_id}) or do {
			error("vertical does not exist or is invalid for this account");
			send_error("vertical_id invalid or not permitted" => 403);
		};

		# The designation must be supplied, but can be blank
		defined $data->{designation} or do {
			send_error("designation parameter not supplied" => 400);
		};

		# Only process update if there is a change
		if($data->{designation} ne $info->{designation}) {
			if(vertical_designation_exists(
				$info->{frame_id},
				$data->{designation},
			)) {
				debug("cannot rename vertical as the new designation conflicts with an existing vertical");
				send_error('Designation is already in use for this frame' => 409);
			}

			update_vertical_designation(
				$info,
				$data->{designation}
			);
			database->commit;
		}
		else {
			debug("vertical designation is unchanged - nothing to do");
		}

		my $rv = {
			vertical_id => $data->{vertical_id},
			designation => $data->{designation},
		};

		return to_json $rv;
	};

	post '/insert_vertical' => sub {

		user_has_role('edit') or do {
			error('user does not have the edit role');
			send_error('forbidden' => 403);
		};

		debug request->body;
		my $data = from_json(request->body);

		frame_id_valid_for_account($data->{frame_id}) or do {
			error("frame_id is not valid for this account");
			send_error("frame_id invalid or not permitted" => 403);
		};

		unless($data->{position} && $data->{position} =~ m/^\d+$/) {
			error("valid position parameter not supplied");
			send_error("valid position parameter not supplied" => 400);
		}

		my $info = insert_vertical(
			$data->{frame_id},
			$data->{position}
		);
		database->commit;
		return to_json $info;
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


sub vertical_id_valid_for_account {

	my $vertical_id = shift;
	my $account_id = shift || session('account')->{id};

	$vertical_id && $vertical_id =~ m/^\d+$/ or do {
		error "vertical_id is not an integer";
		return undef;
	};
	$account_id && $account_id =~ m/^\d+$/ or do {
		error "account_id is not an integer";
		return undef;
	};

	my $q = database->prepare("
		SELECT 1
		FROM vertical
		JOIN frame ON (frame.id = vertical.frame_id)
		WHERE vertical.id = ?
		AND frame.account_id = ?
	");

	$q->execute(
		$vertical_id,
		$account_id,
	);

	return $q->fetchrow_hashref;
}


sub max_frames {
	my $account_id = shift || session('account')->{id};
	my $q = database->prepare("
		SELECT max_frame_count AS max_frames
		FROM account
		WHERE id = ?
	");
	$q->execute($account_id);
	my $r = $q->fetchrow_hashref;

	return $r->{max_frames};
}


sub frame_count {
	my $account_id = shift || session('account')->{id};
	my $q = database->prepare("
		SELECT COUNT(*) AS frame_count
		FROM frame
		WHERE account_id = ?
		AND is_deleted IS FALSE
	");
	$q->execute($account_id);
	my $r = $q->fetchrow_hashref;

	return $r->{frame_count};
}


sub max_frame_size {
	my $account_id = shift || session('account')->{id};
	# Default size limit defined in this query
	my $q = database->prepare("
		SELECT 
			COALESCE(max_frame_height, 100) AS height,
			COALESCE(max_frame_width, 100) AS width
		FROM account
		WHERE id = ?
	");
	$q->execute($account_id);
	return $q->fetchrow_hashref;
}


sub frame_info {
	my $frame_id = shift;
	my $q = database->prepare("SELECT * FROM frame_info WHERE id = ?");
	$q->execute($frame_id);
	return $q->fetchrow_hashref;
}


sub vertical_info {
	my $vertical_id = shift;
	my $account_id = shift || session('account')->{id};

	my $q = database->prepare("
		SELECT * FROM vertical_info
		WHERE id = ?
		AND account_id = ?
	");
	$q->execute(
		$vertical_id,
		$account_id,
	);

	return $q->fetchrow_hashref;
}


sub vertical_designation_exists {
	my $frame_id = shift;
	my $vertical_designation = shift;

	my $q = database->prepare("
		SELECT 1
		FROM vertical
		WHERE frame_id = ?
		AND designation = ?
	");

	$q->execute(
		$frame_id,
		$vertical_designation
	);

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


sub vertical_blocks {
	my $vertical_id = shift;
	my $q = database->prepare("
		SELECT *
		FROM block_info
		WHERE vertical_id = ?
		ORDER BY position ASC
	");

	$q->execute($vertical_id);
	my $blocks = $q->fetchall_hashref('position');

	return $blocks;
}


sub frame_blocks {
	my $frame_id = shift;
	my $verticals = verticals($frame_id);

	# Query blocks vertical at a time	
	foreach my $vertical_position(keys %{$verticals}) {
		my $vertical = $verticals->{$vertical_position};
		$vertical->{blocks} = vertical_blocks($vertical->{id});
	}	

	return $verticals;
}


sub block_types {
	my $account_id = shift || session('account')->{id};
	my $q = database->prepare("
		SELECT id, name
		FROM block_type
		WHERE block_type.account_id = ?
		ORDER BY name ASC
	");
	$q->execute($account_id);
	return $q->fetchall_arrayref({});
}


sub block_type_id_valid_for_account {
	my $block_type_id = shift;
	my $account_id = shift || session('account')->{id};

	$block_type_id && $block_type_id =~ m/^\d+$/ or do {
		error "block_type_id is not an integer: [$block_type_id]";
		return undef;
	};

	my $q = database->prepare("
		SELECT 1
		FROM block_type
		WHERE block_type.account_id = ?
		AND block_type.id = ?
	");
	$q->execute(
		$account_id,
		$block_type_id
	);

	return $q->fetchall_arrayref({});
}


sub place_block {

	my $block_id = shift;
	my $block_type = shift;

	my $q = database->prepare("
		SELECT place_generic_block_type(?,?) AS placed_block_id
	");
	$q->execute(
		$block_id,
		$block_type
	) or do {
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


sub remove_vertical {

	my $vertical_id = shift;

	# We deal with the activity log at this application level,
	# rather than within the database. As we want to record the
	# removal of every active block (and its associated parts),
	# before the vertical itself is removed.

	debug("removing vertical $vertical_id");

	# Remove individual blocks one-by-one so that the removals
	# are recorded in the activity log. If we weren't bothered
	# about the activity log, we could skip this, as the blocks
	# would be removed anyway within the remove_vertical() database
	# function call.
	my $info = vertical_info($vertical_id);
	my $blocks = vertical_blocks($vertical_id);
	foreach my $position (keys %{$blocks}) {
		my $block = $blocks->{$position};

		unless($block->{is_active}) {
			debug(sprintf(
				'block %u is not active',
				$block->{id}
			));
			next;
		}
		elsif($block->{is_free}) {
			debug(sprintf(
				'block %u is not in use',
				$block->{id}
			));
			next;
		}
		else {
			remove_block($block->{id});
		}
	}

	# Finally remove the vertical and its empty block positions
	my $q = database->prepare("SELECT remove_vertical(?) AS success");
	$q->execute($vertical_id) or do {
		error("ERROR running database command to remove vertical");
		database->rollback;
		die;
	};

	my $result = $q->fetchrow_hashref or do {
		error("received no result back from database after removing vertical");
		database->rollback;
		die;
	};

	# Update Activity Log
	my $note = sprintf(
		'Removed vertical %s',
		$info->{designation},
	);
	$al->record({
		function     => 'kronekeeper::Frame::remove_vertical',
		frame_id     => $info->{frame_id},
		note         => $note,
	});

	return $result->{success};
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

	debug("removing block_id $block_id and all associated elements");

	# Get jumpers on this block
	my $info = block_info($block_id);
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

	return $result->{removed_block};
}


sub remove_block_position {

	my $block_id = shift;
	my $q = database->prepare("
		SELECT remove_block_position(?) AS success
	");
	$q->execute($block_id);
	my $result = $q->fetchrow_hashref;

	$result && $result->{success} or do {
		database->rollback;
		send_error("failed to remove block position $block_id");
	};	

	return $result->{success};
}


sub enable_block_position {

	my $block_id = shift;
	my $q = database->prepare("
		SELECT enable_block_position(?) AS success
	");
	$q->execute($block_id);
	my $result = $q->fetchrow_hashref;

	$result && $result->{success} or do {
		database->rollback;
		send_error("failed to enable block position $block_id");
	};	

	return $result->{success};
}


sub create_frame {

	my $frame_name = shift;
	my $frame_width = shift;
	my $frame_height = shift;
	my $designation_order_h = shift || 'left-to-right';
	my $designation_order_v = shift || 'bottom-to-top';
	my $is_template = shift;
	my $account_id = session('account')->{id};

	debug(sprintf(
		'creating %s "%s" with dimensions %dx%d',
		$is_template ? 'template' : 'frame',
		$frame_name,
		$frame_width,
		$frame_height,
	));
	debug("designations: $designation_order_h, $designation_order_v");


	my $q = database->prepare("
		SELECT create_regular_frame(?,?,?,?,?,?,?) AS new_frame_id
	");
	$q->execute(
		$account_id,
		$frame_name,
		$frame_width,
		$frame_height,
		($designation_order_h eq 'right-to-left' ? 't':'f'),  # whether to reverse or not
		($designation_order_v eq 'top-to-bottom' ? 't':'f'),  # whether to reverse or not
		($is_template ? 't':'f'),
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


sub reverse_vertical_designations {

	my $frame_id = shift;
	my $q = database->prepare("
		SELECT reverse_vertical_designations(?) AS success
	");
	$q->execute($frame_id);
	my $result = $q->fetchrow_hashref;

	$result && $result->{success} or do {
		database->rollback;
		send_error("failed to reverse vertical designations for frame_id $frame_id");
	};	

	return $result->{success};
}


sub reverse_block_designations {

	my $frame_id = shift;
	my $q = database->prepare("
		SELECT reverse_block_designations(?) AS success
	");
	$q->execute($frame_id);
	my $result = $q->fetchrow_hashref;

	$result && $result->{success} or do {
		database->rollback;
		send_error("failed to reverse block designations for frame_id $frame_id");
	};	

	return $result->{success};
}


sub update_name {

	my $info = shift;
	my $name = shift;

	# Rename circuit
	my $q = database->prepare("
		UPDATE frame SET name = ?
		WHERE id = ?
	");

	$q->execute(
		$name,
		$info->{id},
	) or do {
		database->rollback;
		send_error('error updating frame' => 500);
	};

	# Update Activity Log
	my $note = sprintf(
		'frame renamed "%s" (was "%s")',
		$name,
		$info->{name} || '',
	);

	$al->record({
		function     => 'kronekeeper::Frame::update_name',
		frame_id     => $info->{id},
		note         => $note,
	});
}


sub update_vertical_designation {

	my $info = shift;
	my $designation = shift;

	# Rename circuit
	my $q = database->prepare("
		UPDATE vertical SET designation = ?
		WHERE id = ?
	");

	$q->execute(
		$designation,
		$info->{id},
	) or do {
		database->rollback;
		send_error('error updating frame' => 500);
	};

	# Update Activity Log
	my $note = sprintf(
		'frame %s vertical position %u designation changed to "%s" (was "%s")',
		$info->{frame_name},
		$info->{position},
		$designation,
		$info->{designation} || '',
	);

	$al->record({
		function     => 'kronekeeper::Frame::update_vertical_designation',
		frame_id     => $info->{frame_id},
		note         => $note,
	});
}


sub insert_vertical {

	my $frame_id = shift;
	my $position = shift;

	my $q = database->prepare("
		SELECT insert_vertical(?, ?) as vertical_id
	");

	$q->execute(
		$frame_id,
		$position
	) or do {
		database->rollback;
		send_error('error inserting vertical' => 500);
	};

	my $r = $q->fetchrow_hashref();
	my $info = vertical_info($r->{vertical_id});

	# Update Activity Log
	my $note = sprintf(
		'inserted vertical "%s" in position %u',
		$info->{designation},
		$info->{position},
	);

	$al->record({
		function     => 'kronekeeper::Frame::insert_vertical',
		frame_id     => $frame_id,
		note         => $note,
	});

	return $info;
}


sub templates {
	my $q = database->prepare("
		SELECT * FROM frame_info
		WHERE account_id = ?
		AND is_deleted IS FALSE
		AND is_template IS TRUE
		ORDER BY name ASC
	");
	$q->execute(
		session('account')->{id}
	);
	return $q->fetchall_arrayref({});
}


1;
