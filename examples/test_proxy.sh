#!/bin/sh
PERL_STARLIGHT_DEBUG=1 plackup -Ilib -s Starlight -E proxy -MPlack::App::Proxy -e 'enable q{AccessLog}; enable q{Proxy::Connect}; enable q{Proxy::AddVia}; enable q{Proxy::Requests}; Plack::App::Proxy->new->to_app' --workers 50 --max-reqs-per-child 100
