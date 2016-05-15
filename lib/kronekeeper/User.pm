package kronekeeper::User;

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

my $al = kronekeeper::Activity_Log->new();

#TODO Authentication for these routes


prefix '/api/user' => sub {

	post '/add' => sub {

		param('email')      or send_error('missing email parameter' => 400);
		param('account_id') or send_error('missing account_id parameter' => 400);
		param('name')       or send_error('missing name parameter' => 400);

		if(get_user_details(param('email'))) {
			error(sprintf("user %s already exists", param('email')));
			send_error('user already exists' => 400);
		}

		my $user_id = create_user(
			username   => param('email'),
			account_id => param('account_id'),
			name       => param('name'),
		) or do {
			database->rollback;
			send_error('error creating user' => 500);
		};

		$al->record({
			function   => '/api/user/add',
			account_id => param('account_id'),
			note       => sprintf("added new user '%s'", param('email'))
		});

		return to_json {
			user_id => $user_id
		};
	};


	post '/password' => sub {

		param('email')    or send_error('missing email parameter' => 400);
		param('password') or send_error('missing password parameter' => 400);

		user_password(
			username     => param('email'),
			new_password => param('password'),
		) or do {
			send_error('error changing password' => 500);
		};

		$al->record({
			function   => '/api/user/password',
			account_id => param('account_id'),
			note       => sprintf("changed password for user '%s'", param('email'))
		});

		return to_json {
			success => 1,
		};
	}

};




1;
