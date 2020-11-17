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

		user_has_role('configure_block_types') or do {
			send_error('forbidden' => 403);
		};

		template('block_types', {
			block_types => account_block_types(),
		});
	};

	get '/new' => require_login sub {

		user_has_role('configure_block_types') or do {
			send_error('forbidden' => 403);
		};

		my $block_type = {
			id => undef,
			name => '',
			circuit_count => '10',    # default 10 circuits
			circuit_pin_count => '2', # default to pairs (2 pins)
			html_colour => '#ffffff',
			in_use => undef,
		};

		my $template_data = {
			block_type => $block_type,
		};
		template('block_type', $template_data);
	};

	get '/:block_type_id' => require_login sub {

		user_has_role('configure_block_types') or do {
			send_error('forbidden' => 403);
		};

		my $block_type_id = param('block_type_id');
		my $block_type = block_type_info($block_type_id) or do {
			send_error('not found' => 404);
		};

		my $template_data = {
			block_type => $block_type,
		};
		template('block_type', $template_data);
	};

};


prefix '/api/block_type' => sub {

	post '' => require_login sub {

		unless(user_has_role('configure_block_types')) {
			error("user does not have configure_block_types role");
			send_error('forbidden' => 403);
		}

		debug request->body;
		my $data = from_json(request->body);

		unless($data->{name}) {
			error("name parameter missing or invalid");
			send_error("INVALID NAME" => 400);
		}

		# circuit and pin counts must be numeric
		foreach my $field (qw(circuit_count circuit_pin_count)) {
			unless ($data->{$field} && $data->{$field} =~ m/^\d+$/) {
				send_error("INVALID $field" => 400);
			}
		}

		# colour must be #rrggbb format
		unless(
			$data->{html_colour} &&
			$data->{html_colour} =~ m/^#[[:xdigit:]]{6}$/
		) {
			send_error("INVALID html_colour" => 400);
		}

		my $block_type_id = create_block_type($data);

		database->commit;
		return to_json block_type_info($block_type_id);
	};

	patch '/:block_type_id' => require_login sub {

		unless(user_has_role('configure_block_types')) {
			error("user does not have configure_block_types role");
			send_error('forbidden' => 403);
		}

		my $block_type_id = param('block_type_id');
		my $info = block_type_info($block_type_id) or do {
			send_error('block type does not exist' => 400);
		};

		debug request->body;
		my $data = from_json(request->body);
		my $changes = {};

		foreach my $field(keys %{$data}) {
			my $value = $data->{$field};
			for($field) {
				m/^name$/ and do {
					update_name($info, $value);
					$changes->{name} = $value;
					last;
				};

#			name: $("#name").val(),
#			circuit_count: $("#circuit_count").val(),
#			circuit_pin_count: $("#circuit_pin_count").val(),
#			html_colour: $("#html_colour").val(),

				m/^max_frame_(count|width|height)$/ and do {
					update_frame_limit($info, $field, $value);
					$changes->{$field} = $value;
					last;
				};
				# else
				error "failed to update unrecognised block_type field '$field'";
			}
		};

		database->commit;

		content_type 'application/json';
		return to_json $changes;
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

	return $q->fetchall_arrayref({});
}


sub block_type_info {
	my $account_id = session('account')->{id};
	my $block_type_id = shift;
	my $q = database->prepare("
		SELECT * FROM block_type_info
		WHERE account_id = ?
		AND id = ?
	");
	$q->execute(
		$account_id,
		$block_type_id,
	);

	return $q->fetchrow_hashref;
}


sub create_block_type {

	my $data = shift;
	my $account_id = session('account')->{id};

	my $q = database->prepare("
		SELECT create_block_type(?, ?, ?, ?, DECODE(?, 'hex'))
		AS block_type_id
	");

	# Strip leading # from the colour code
	$data->{html_colour} =~ s/^#//;

	$q->execute(
		$account_id,
		$data->{name},
		$data->{circuit_count},
		$data->{circuit_pin_count},
		$data->{html_colour},
	) or do {
		database->rollback;
		send_error('error creating block_type' => 500);
	};

	my $block_type_id = $q->fetchrow_hashref->{block_type_id} or die;

	# Update Activity Log
	my $note = sprintf(
		'created new block type "%s" with %u circuits of %u pins and default colour %s',
		$data->{name},
		$data->{circuit_count},
		$data->{circuit_pin_count},
		$data->{html_colour},
	);

	$al->record({
		function    => '/api/block_type/new',
		note        => $note,
		account_id  => $account_id,
	});

	return $block_type_id;
}


sub update_colour {


	# Strip leading # from the colour code		
	#$html_colour and $html_colour =~ s/^#//;

	# Rename circuit
	my $q = database->prepare("
		UPDATE block SET colour_html_code = DECODE(?, 'hex')
		WHERE id = ?
	");

}

1;
