package kronekeeper;

=head1 LICENCE

This file is part of Kronekeeper, a web based application for 
recording and managing wiring frame records.

Copyright (C) 2016-2017 NP Broadcast Limited

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
use Dancer2;
use Dancer2::Plugin::Database;
use Dancer2::Plugin::Auth::Extensible;
use kronekeeper::Account;
use kronekeeper::Frame;
use kronekeeper::Block;
use kronekeeper::Circuit;
use kronekeeper::Jumper;
use kronekeeper::User;
use kronekeeper::Activity_Log;
use kronekeeper::Frame::Import::KRIS;
use kronekeeper::Frame::Template;

use Carp::Always;

my $al = kronekeeper::Activity_Log->new();

our $VERSION = '0.3';


hook 'database_error' => sub {

	my $dbh = shift;
	error("ERROR: Caught database error - rolling back");
	database->rollback;
	send_error("Caught database error - rolling back" => 500);
};

hook 'before_template_render' => sub {

	# Add list of user roles to every template
	# so we can show/hide options as appropriate
	my $tokens = shift;

	if(logged_in_user) {
		my %user_roles = map {$_ => 1} user_roles;
		$tokens->{user_roles} = \%user_roles;
	}
};


prefix '/' => sub {

	get '/' => sub {
		if(session('logged_in_user')) {
			redirect '/frame/';
		}
		else {
			redirect '/login';
		}
	};

	get '/credits' => sub {
		template 'credits';
	};

	get '/login' => sub {

		# Can't login if we're already logged in
		if(logged_in_user) {
			redirect '/frame/';
		}

		template 'login';
	};

	post '/login' => sub {

		# If database password field is empty, authentication
		# will never succeed. We use this property to disable
		# certain user logins.
		my ($success, $realm) = authenticate_user(
			param('username'),
			param('password'),
		);
		if($success) {
			my $account = account_from_username(param('username'));
			session account => $account;
			session logged_in_user => param('username');
			session logged_in_user_realm => $realm;

			my $user = logged_in_user;
			delete $user->{password};  # Don't want password held in session
			session user => $user;

			$al->record({
				function   => '/login',
				person_id  => $user->{id},
				account_id => $user->{account_id},
				note       => sprintf("user '%s' logged in", param('username'))
			});
			database->commit;

			# Authentication OK - forward to requested page or default 
			# to frame view
			if(param('return_url')) {
				redirect(param('return_url'));
			}
			else {
				redirect('/frame/');
			}
		} else {
			# Authentication failed - return to login page
			template 'login' => {
				login_error => 1
			};
		}
	};

        
	any '/logout' => sub {

		my $user = logged_in_user;
		if($user) {
			$al->record({
				function   => '/logout',
				person_id  => $user->{id},
				account_id => $user->{account_id},
				note       => sprintf("user '%s' logged out", $user->{email}),
			});
			database->commit;
		}

		app->destroy_session;
		redirect('/login');
	};


	any '/denied' => sub {

		send_error('forbidden' => 403);
	};

};


sub account_from_username {

	my $username = shift;

	my $q = database->prepare("
		SELECT 
			account.id   AS id,
			account.name AS name
		FROM person
		JOIN account ON (account.id = person.account_id)
		WHERE person.email = ?
	");

	$q->execute($username);
	return $q->fetchrow_hashref;
}





1;
