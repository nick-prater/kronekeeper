/* 
require.js configuration file

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

*/

require.config({
	baseUrl: '/js',

	paths: {
		jquery: 'jquery-2.2.4.min',
		jqueryui: 'jquery-ui-1.12.0.min',
		underscore: 'underscore-1.8.3.min',
		backbone: 'backbone-1.3.3.min'
	},

	shim: {
		underscore: {
			exports: '_'
		},
		backbone: {
			deps: ['underscore', 'jquery'],
			exports: 'Backbone'
		},
		jqueryui: {
			deps: ['jquery']
		}
	}
});

console.log("loaded main.js");
