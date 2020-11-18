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

	};

};


prefix '/api/jumper_template' => sub {

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

	return $q->fetchrow_hashref;
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


1;