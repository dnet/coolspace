#!/usr/bin/env escript
main(_) ->
	inets:start(),
	ssl:start(),
	coolspace:gen_temps().
