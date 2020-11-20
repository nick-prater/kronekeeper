package kronekeeper::JumperTemplate;

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
use kronekeeper::Jumper qw(
	get_jumper_templates
	get_jumper_template_colour_names
	get_colours
);
use Exporter qw(import);
our $VERSION = '0.01';
our @EXPORT_OK = qw();


my $al = kronekeeper::Activity_Log->new();


prefix '/jumper_template' => sub {

	get '/' => require_login sub {

		user_has_role('configure_jumper_templates') or do {
			send_error('forbidden' => 403);
		};

		template('jumper_templates', {
			jumper_templates => get_jumper_templates(undef),
		});
	};

	get '/new' => require_login sub {

		user_has_role('configure_jumper_templates') or do {
			send_error('forbidden' => 403);
		};

		my $jumper_template = {
			id => undef,
			name => '',
			designation => '',
			wires => [],
		};

		my $template_data = {
			jumper_template => $jumper_template,
			wire_colours => get_colours(),
		};
		template('jumper_template', $template_data);
	};

	get '/:jumper_template_id' => require_login sub {

		user_has_role('configure_jumper_templates') or do {
			send_error('forbidden' => 403);
		};

		my $jumper_template_id = param('jumper_template_id');

		# Confirm jumper_template exists and belongs to the session's account
		my $jumper_template = jumper_template_info($jumper_template_id) or do {
			send_error('not found' => 404);
		};

		my $template_data = {
			jumper_template => $jumper_template,
			wire_colours => get_colours(),
		};

		template('jumper_template', $template_data);
	};
};


prefix '/api/jumper_template' => sub {

	post '' => require_login sub {

		unless(user_has_role('configure_jumper_templates')) {
			error("user does not have configure_jumper_templates role");
			send_error('forbidden' => 403);
		}

		debug request->body;
		my $data = from_json(request->body);

		unless($data->{name}) {
			error("name parameter missing or invalid");
			send_error("INVALID NAME" => 400);
		}
		unless($data->{designation}) {
			error("designation parameter missing or invalid");
			send_error("INVALID DESIGNATION" => 400);
		}

		my $jumper_template_id = create_jumper_template($data);

		database->commit;
		return to_json jumper_template_info($jumper_template_id);
	};

	del '/:jumper_template_id' => require_login sub {

		my $jumper_template_id = param('jumper_template_id');

		unless(user_has_role('configure_jumper_templates')) {
			error("user does not have configure_jumper_templates role");
			send_error('forbidden' => 403);
		}

		# Confirm jumper template exists and belongs to the session's account
		my $info = jumper_template_info($jumper_template_id) or do {
			send_error('jumper template does not exist or is invalid for this account' => 403);
		};

		delete_jumper_template($info);
		database->commit;
		return to_json({id => $jumper_template_id});
	};

	patch '/:jumper_template_id' => require_login sub {

		unless(user_has_role('configure_jumper_templates')) {
			error("user does not have configure_jumper_templates role");
			send_error('forbidden' => 403);
		}

		my $jumper_template_id = param('jumper_template_id');

		# Confirm jumper_template exists and belongs to the session's account
		my $info = jumper_template_info($jumper_template_id) or do {
			send_error('jumper_template does not exist' => 400);
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
				m/^designation$/ and do {
					update_designation($info, $value);
					$changes->{designation} = $value;
					last;
				};
				m/^wires$/ and do {
					update_wires($info, $value);
					$changes->{wires} = numify($value);
					last;
				};
				# else
				error "failed to update unrecognised jumper_template field '$field'";
			}
		};

		database->commit;

		content_type 'application/json';
		return to_json $changes;
	};

};


sub jumper_template_info {

	# This will only return info for jumper templates belonging to the
	# current session's account
	my $account_id = session('account')->{id};
	my $jumper_template_id = shift;
	my $q = database->prepare("
		SELECT * FROM jumper_template
		WHERE account_id = ?
		AND id = ?
	");
	$q->execute(
		$account_id,
		$jumper_template_id,
	);

	my $template = $q->fetchrow_hashref or return undef;

	# Add the wires for the template
	$q = database->prepare("
		SELECT colour_id
		FROM jumper_template_wire
		WHERE jumper_template_id = ?
		ORDER BY position ASC
	");

	$q->execute($template->{id});

	# Coerce wires into a flat array of numbers (rather than text)
	$template->{wires} = [
		map {$_->{colour_id} * 1}
		@{$q->fetchall_arrayref({})}
	];

	return $template;
}


sub create_jumper_template {

	my $info = shift;
	my $account_id = session('account')->{id};

	# First insert the jumper with no wires attached
	my $q = database->prepare("
		SELECT create_jumper_template(?, ?, ?, ARRAY[]::text[])
		AS jumper_template_id
	");
	$q->execute(
		$account_id,
		$info->{name},
		$info->{designation}
	);
	my $result = $q->fetchrow_hashref();
	$info->{id} = $result->{jumper_template_id};

	# Update Activity Log
	my $note = sprintf(
		'created new jumper template %s (id %u) with designation "%s"',
		$info->{name},
		$info->{id},
		$info->{designation},
	);

	$al->record({
		function   => 'kronekeeper::JumperTemplate::create_jumper_template',
                account_id => $account_id,
		note       => $note,
	});

	# Add wires to newly created jumper template
	update_wires($info, $info->{wires});

	return $info->{id};
}


sub delete_jumper_template {

	my $info = shift;
	my $account_id = session('account')->{id};

	my $q = database->prepare("SELECT delete_jumper_template(?)");
	$q->execute($info->{id});

	# Update Activity Log
	my $note = sprintf(
		'deleted jumper template "%s" (id %u)',
		$info->{name},
		$info->{id},
	);

	$al->record({
		function   => 'kronekeeper::JumperTemplate::delete_jumper_template',
                account_id => $account_id,
		note       => $note,
	});

	return;
}


sub update_name {

	my $info = shift;
	my $name = shift;
	my $account_id = session('account')->{id};

	my $q = database->prepare("
		UPDATE jumper_template SET name = ?
		WHERE id = ?
		AND account_id = ?
	");

	$q->execute(
		$name,
		$info->{id},
		$account_id
	) or do {
		database->rollback;
		send_error('error updating jumper_template name' => 500);
	};

	# Update Activity Log
	my $note = sprintf(
		'jumper template with id %u renamed to "%s" (was "%s")',
		$info->{id},
		$name,
		$info->{name},
	);

	$al->record({
		function   => 'kronekeeper::JumperTemplate::update_name',
                account_id => $account_id,
		note       => $note,
	});

	return;
}


sub update_designation {

	my $info = shift;
	my $designation = shift;
	my $account_id = session('account')->{id};

	my $q = database->prepare("
		UPDATE jumper_template SET designation = ?
		WHERE id = ?
		AND account_id = ?
	");

	$q->execute(
		$designation,
		$info->{id},
		$account_id
	) or do {
		database->rollback;
		send_error('error updating jumper_template designation' => 500);
	};

	# Update Activity Log
	my $note = sprintf(
		'jumper template %s (id %u) designation changed to "%s" (was "%s")',
		$info->{name},
		$info->{id},
		$designation,
		$info->{designation},
	);

	$al->record({
		function   => 'kronekeeper::JumperTemplate::update_designation',
                account_id => $account_id,
		note       => $note,
	});

	return;
}


sub update_wires {

	my $info = shift;
	my $wires = shift;
	my $account_id = session('account')->{id};

	unless($wires && ref $wires eq 'ARRAY' && scalar @{$wires} > 0) {
		database->rollback;
		send_error("invalid wires specification for jumper template", 400);
	};

	# Store old wire colour names to write descriptive activity log
	my @old_colours = @{get_jumper_template_colour_names($info->{id})};

	# Handle any changes to wires by deleting all wires for the template
	# then inserting the new specification
	my $q = database->prepare("
		DELETE FROM jumper_template_wire
		WHERE jumper_template_id = ?
	");
	$q->execute($info->{id}) or do {
		database->rollback;
		send_error('error removing old jumper template wires' => 500);
	};

	$q = database->prepare("
		INSERT INTO jumper_template_wire (
			jumper_template_id,
			position,
			colour_id
		) VALUES (?, ?, ?)
	");

	my $count = 1;
	foreach my $colour_id (@{$wires}) {

		unless($colour_id && $colour_id =~ m/^\d+$/) {
			database->rollback;
			send_error('invalid wire colour' => 400);
		}

		$q->execute(
			$info->{id},
			$count,
			$colour_id
		) or do {
			database->rollback;
			send_error('error inserting jumper_template_wire' => 500);
		};
		$count ++;
	}

	# Store new wire colour names to write descriptive activity log
	my @new_colours = @{get_jumper_template_colour_names($info->{id})};

	# Update Activity Log
	my $note = sprintf(
		'jumper template %s (id %u) wire colours changed to [%s] (previously [%s])',
		$info->{name},
		$info->{id},
		join(', ', @new_colours),
		join(', ', @old_colours),
	);

	$al->record({
		function   => 'kronekeeper::JumperTemplate::update_designation',
                account_id => $account_id,
		note       => $note,
	});

	return;
}


sub numify {
	# Coerce each element of an array into a number.
	# This is used with arrays of wire colour ids
	# so that they are not interpreted as strings when
	# converted to json.
	my $arrayref = shift;
	foreach my $element(@{$arrayref}) { $element *= 1 }
	return $arrayref;
}

1;
