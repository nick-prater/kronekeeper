package kronekeeper;

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
use Dancer2;
use Dancer2::Plugin::Database;
use Dancer2::Plugin::Auth::Extensible;
use kronekeeper::Frame;
use kronekeeper::Block;
use kronekeeper::Circuit;
use kronekeeper::Jumper;
use kronekeeper::User;
use kronekeeper::Activity_Log;

my $al = kronekeeper::Activity_Log->new();


our $VERSION = '0.1';


prefix '/' => sub {

	get '/' => sub {
		if(session('logged_in_user')) {
			redirect '/frame/';
		}
		else {
			redirect '/login';
		}
	};


	get '/login' => sub {
		template 'login';
	};

	post '/login' => sub {

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
