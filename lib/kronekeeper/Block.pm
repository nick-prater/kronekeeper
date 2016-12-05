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
use feature 'switch';
use Dancer2 appname => 'kronekeeper';
use Dancer2::Plugin::Database;
use Dancer2::Plugin::Auth::Extensible;
use kronekeeper::Activity_Log;
use Exporter qw(import);
our $VERSION = '0.01';
our @EXPORT_OK = qw(
	block_id_valid_for_account
	block_info
	block_circuits
	block_is_free
);


my $al = kronekeeper::Activity_Log->new();


prefix '/block' => sub {

	get '/:block_id' => require_login sub {

		my $id = param('block_id');

		$id && $id =~ m/^\d+$/ or do {
			send_error('invalid block_id parameter', 400);
		};
		block_id_valid_for_account($id) or do {
			send_error('forbidden' => 403);
		};

		my $block_info = block_info($id);

		template('block', {
			block_info => $block_info,
			circuits   => block_circuits($id),
			blocks     => ordered_frame_blocks($block_info->{frame_id}),
		});
	};

};



prefix '/api/block' => sub {

	get '/:block_id' => require_login sub {

		my $id = param('block_id');

		$id && $id =~ m/^\d+$/ or do {
			send_error('invalid block_id parameter', 400);
		};
		block_id_valid_for_account($id) or do {
			send_error('forbidden' => 403);
		};

		content_type 'application/json';
		return to_json {
			block_info => block_info($id),
			circuits   => block_circuits($id),
		};
	};

	patch '/:block_id' => sub {

		user_has_role('edit') or do {
			send_error('forbidden' => 403);
		};

		my $id = param('block_id');
		block_id_valid_for_account($id) or do {
			send_error('forbidden' => 403);
		};
		debug "updating block: $id";

		debug request->body;
		my $data = from_json(request->body);
		my $changes = {};
		my $block_info = block_info($id);

		foreach my $field(keys %{$data}) {
			my $value = $data->{$field};
			given($field) {
				when('name') {
					update_name($block_info, $value);
					$changes->{name} = $value;
				};
				default {
					error "failed to update unrecognised circuit field '$field'";
				};					
			};
		};

		database->commit;

		content_type 'application/json';
		return to_json $changes;
	};

	any qr{/\d+(/\d+.*)} => require_login sub {
		
		# To keep a nice hierachy, allow access to 'circuit' routes
		# responds to routes of the form: /api/block/[block_id]/[circuit_id]/xxx...
		# forwards them to /api/circuit/[circuit_id]/xxx...
		my ($route) = splat;
		my $target =  "/api/circuit" . $route;
		debug "redirecting to $target";
		forward $target;
	};

};


sub block_id_valid_for_account {

	my $block_id = shift;
	my $account_id = shift || session('account')->{id};

	$block_id && $block_id =~ m/^\d+$/ or do {
		error "block_id is not an integer";
		return undef;
	};
	$account_id && $account_id =~ m/^\d+$/ or do {
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
		$block_id,
		$account_id,
	);

	return $q->fetchrow_hashref;
}


sub block_info {
	my $block_id = shift;
	my $q = database->prepare("
		SELECT *
		FROM block_info
		WHERE id=?
	");
	$q->execute($block_id);
	return $q->fetchrow_hashref;
};


sub block_is_free {
	my $block_id = shift;
	my $q = database->prepare("
		SELECT *
		FROM block_is_free(?) AS is_free
	");
	$q->execute($block_id);
	my $result = $q->fetchrow_hashref;
	return $result->{is_free};
}


sub block_circuits {
	my $block_id = shift;
	my $q = database->prepare("
		SELECT json_data 
		FROM json_block_circuits(?)
	");
	$q->execute($block_id);
	my $result = $q->fetchrow_hashref or return undef;

	# We set utf8=>0 here, because the database driver has already
	# done the character decoding. Failing to set this option triggers
	# an error when when accented characters or emoji.
	# Fix for our Github issue #12
	my $rv = from_json($result->{json_data}, {utf8 => 0});

	return $rv;
}


sub update_name {

	my $info = shift;
	my $name = shift;

	# Rename circuit
	my $q = database->prepare("
		UPDATE block SET name = ?
		WHERE id = ?
	");

	$q->execute(
		$name,
		$info->{id},
	) or do {
		database->rollback;
		send_error('error updating block' => 500);
	};

	# Update Activity Log
	my $note = sprintf(
		'block %s renamed "%s" (was "%s")',
		$info->{full_designation},
		$name,
		$info->{name} || '',
	);

	$al->record({
		function     => 'kronekeeper::Block::update_name',
		frame_id     => $info->{frame_id},
		block_id_a   => $info->{id},
		note         => $note,
	});
}


sub ordered_verticals {

	# Returns an array of verticals for the given frame
	# ordered by position
	my $frame_id = shift;

	my $q = database->prepare("
		SELECT id, designation, position
		FROM vertical
		WHERE frame_id = ?
		ORDER BY position ASC
	");
	$q->execute($frame_id);
	return $q->fetchall_arrayref({});
}


sub ordered_frame_blocks {

	# Returns a nested array of verticals and blocks for the given frame
	# ordered by position
	my $frame_id = shift;

	my $q = database->prepare("
		SELECT id, designation, position
		FROM block
		WHERE vertical_id = ?
		ORDER BY position ASC
	");

	my $verticals = ordered_verticals($frame_id);

	# Add array of blocks to each vertical element
	foreach my $vertical(@{$verticals}) {
		$q->execute($vertical->{id});
		$vertical->{blocks} = $q->fetchall_arrayref({});
	}

	return $verticals;
}



1;
